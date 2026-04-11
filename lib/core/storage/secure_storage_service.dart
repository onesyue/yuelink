import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' as ag;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Stores credentials in OS-native secure storage.
///
/// Platform strategy:
/// - Android  → Keystore-backed EncryptedSharedPreferences
/// - iOS      → Data Protection Keychain
/// - macOS    → Encrypted JSON file in Application Support directory.
///              The macOS Keychain (both legacy and Data Protection) requires
///              code-signing entitlements that block `flutter run` debug
///              builds without a paid developer account, so we use a file
///              backend instead — but the file is **AES-256-GCM encrypted**
///              with a key derived from the macOS hardware UUID
///              (`IOPlatformUUID` via `ioreg`). An attacker who copies the
///              file off the machine can't decrypt it without also
///              extracting the hardware UUID, and an attacker who can read
///              the user's home dir can also call ioreg — they're equivalent
///              to YueLink itself, which is the right threat boundary.
/// - Windows  → Credential Locker (DPAPI)
class SecureStorageService {
  SecureStorageService._();
  static final instance = SecureStorageService._();

  // ── Non-macOS: flutter_secure_storage ─────────────────────────────────────

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked),
    wOptions: WindowsOptions(),
  );

  // ── macOS: encrypted JSON file backend ────────────────────────────────────

  static final _macStore = _MacEncryptedStore();

  // ── Public API ────────────────────────────────────────────────────────────

  Future<String?> read(String key) async {
    if (Platform.isMacOS) return _macStore.read(key);
    return _storage.read(key: key);
  }

  Future<void> write(String key, String value) async {
    if (Platform.isMacOS) return _macStore.write(key, value);
    await _storage.write(key: key, value: value);
  }

  Future<void> delete(String key) async {
    if (Platform.isMacOS) return _macStore.delete(key);
    await _storage.delete(key: key);
  }

  // ── Subscription URL tokens ───────────────────────────────────────────────

  static String _subKey(String profileId) => 'sub_url_$profileId';

  Future<String?> getSubscriptionUrl(String profileId) =>
      read(_subKey(profileId));

  Future<void> setSubscriptionUrl(String profileId, String url) =>
      write(_subKey(profileId), url);

  Future<void> deleteSubscriptionUrl(String profileId) =>
      delete(_subKey(profileId));

  // ── API secret ────────────────────────────────────────────────────────────

  static const _kApiSecret = 'mihomo_api_secret';

  Future<String?> getApiSecret() => read(_kApiSecret);
  Future<void> setApiSecret(String secret) => write(_kApiSecret, secret);
}

/// AES-256-GCM encrypted key/value store for macOS. The encryption key is
/// derived from the macOS hardware UUID, so the file on disk is unreadable
/// without access to the originating machine's `IOPlatformUUID`.
///
/// On-disk envelope format (single JSON object):
///
///     {
///       "v": 1,
///       "nonce": "<base64 12-byte AES-GCM nonce>",
///       "ct": "<base64 ciphertext>",
///       "mac": "<base64 16-byte GCM auth tag>"
///     }
///
/// Plaintext map (encrypted as ct) is `{"key1": "value1", ...}`.
///
/// Migration: if the file is detected as legacy plaintext (a JSON object
/// with the credential keys directly at top level), it is decoded, immediately
/// re-encrypted to v1 envelope, and the plaintext is overwritten.
class _MacEncryptedStore {
  static const _filename = '.yuelink_secure.json';
  static const _envelopeVersion = 1;

  /// In-memory cache of the decrypted map. Loaded once per app launch.
  Map<String, String>? _cache;
  Future<File>? _filePending;
  Future<ag.SecretKey>? _keyPending;

  // Serialise writes so concurrent callers don't race on tmp+rename.
  Future<void> _writeChain = Future.value();

  Future<File> _file() {
    return _filePending ??= getApplicationSupportDirectory()
        .then((dir) => File('${dir.path}/$_filename'));
  }

  /// Derive a 256-bit AES key from the macOS hardware UUID.
  ///
  /// Uses HKDF-SHA256 with a static info string so the derivation is stable
  /// across launches but unique to (machine, app). The hardware UUID is
  /// fetched via `ioreg` and cached for the process lifetime.
  Future<ag.SecretKey> _key() {
    return _keyPending ??= () async {
      final hwUuid = await _getMacHardwareUuid();
      final hkdf = ag.Hkdf(hmac: ag.Hmac.sha256(), outputLength: 32);
      return hkdf.deriveKey(
        secretKey: ag.SecretKey(utf8.encode(hwUuid)),
        nonce: utf8.encode('com.yueto.yuelink.secure_storage.v1'),
        info: utf8.encode('aes-256-gcm-master-key'),
      );
    }();
  }

  /// Read `IOPlatformUUID` from the macOS IORegistry. This is a per-machine
  /// UUID that survives reboots and OS reinstalls, but changes if the file
  /// is copied to another machine. Falls back to a hostname-based string
  /// if `ioreg` is unavailable (which would mean the machine is heavily
  /// modified — best-effort fallback).
  Future<String> _getMacHardwareUuid() async {
    try {
      final result = await Process.run(
        '/usr/sbin/ioreg',
        ['-rd1', '-c', 'IOPlatformExpertDevice'],
      );
      final stdout = result.stdout.toString();
      final match =
          RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"').firstMatch(stdout);
      if (match != null) return match.group(1)!;
    } catch (e) {
      debugPrint('[SecureStorage] ioreg lookup failed: $e');
    }
    // Last-resort fallback — at least binds to the username + hostname so
    // a stolen file can't be opened by a different user account.
    return 'fallback:${Platform.localHostname}:'
        '${Platform.environment['USER'] ?? 'unknown'}';
  }

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _file();
      if (!await file.exists()) {
        _cache = <String, String>{};
        return _cache!;
      }
      final raw = await file.readAsString();
      if (raw.isEmpty) {
        _cache = <String, String>{};
        return _cache!;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _cache = <String, String>{};
        return _cache!;
      }

      // Detect envelope vs legacy plaintext.
      if (decoded['v'] is int && decoded['ct'] is String) {
        _cache = await _decryptEnvelope(decoded as Map<String, dynamic>);
      } else {
        // Legacy plaintext (v0): re-encrypt on next persist.
        debugPrint('[SecureStorage] migrating legacy plaintext file → v1 envelope');
        _cache = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        // Force a persist to overwrite the plaintext file. Don't await — it
        // will run on the write chain in the background.
        unawaited(_persist());
      }
    } catch (e) {
      debugPrint('[SecureStorage] load failed, starting fresh: $e');
      _cache = <String, String>{};
    }
    return _cache!;
  }

  Future<Map<String, String>> _decryptEnvelope(
      Map<String, dynamic> envelope) async {
    try {
      final nonce = base64Decode(envelope['nonce'] as String);
      final ct = base64Decode(envelope['ct'] as String);
      final macBytes = base64Decode(envelope['mac'] as String);
      final algo = ag.AesGcm.with256bits();
      final key = await _key();
      final secretBox = ag.SecretBox(
        ct,
        nonce: nonce,
        mac: ag.Mac(macBytes),
      );
      final plain = await algo.decrypt(secretBox, secretKey: key);
      final json = utf8.decode(plain);
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (e) {
      debugPrint('[SecureStorage] decrypt failed (key/file mismatch): $e');
    }
    return <String, String>{};
  }

  Future<Map<String, dynamic>> _encryptEnvelope(Map<String, String> map) async {
    final algo = ag.AesGcm.with256bits();
    final key = await _key();
    final plaintext = utf8.encode(jsonEncode(map));
    final secretBox = await algo.encrypt(plaintext, secretKey: key);
    return {
      'v': _envelopeVersion,
      'nonce': base64Encode(secretBox.nonce),
      'ct': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  Future<void> _persist() async {
    final next = _writeChain.then((_) async {
      try {
        final file = await _file();
        await file.parent.create(recursive: true);
        final envelope = await _encryptEnvelope(_cache ?? const {});
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(jsonEncode(envelope));
        await tmp.rename(file.path);
        // chmod 600 so other users on multi-user macOS can't read it.
        await Process.run('chmod', ['600', file.path]);
      } catch (e) {
        debugPrint('[SecureStorage] persist failed: $e');
      }
    });
    _writeChain = next;
    return next;
  }

  Future<String?> read(String key) async {
    final map = await _load();
    return map[key];
  }

  Future<void> write(String key, String value) async {
    final map = await _load();
    map[key] = value;
    await _persist();
  }

  Future<void> delete(String key) async {
    final map = await _load();
    if (map.remove(key) != null) {
      await _persist();
    }
  }
}
