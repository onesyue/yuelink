import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Stores credentials in OS-native secure storage.
///
/// Platform strategy:
/// - Android  → Keystore-backed EncryptedSharedPreferences
/// - iOS      → Data Protection Keychain
/// - macOS    → JSON file in Application Support directory
///              (Keychain requires Developer ID cert even in legacy mode for
///               unsigned debug builds; path_provider JSON is the standard
///               approach for non-App-Store macOS apps — used by FlClash, etc.)
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

  // ── macOS: path_provider JSON file ────────────────────────────────────────

  static const _kFileName = '.yuetong_cred.json';
  static File? _macosFile;
  static Map<String, String>? _macosCache;
  // Serialize concurrent saves — same pattern as SettingsService._saveGuard.
  static Future<void> _saveGuard = Future.value();

  static Future<File> _getFile() async {
    _macosFile ??= File(
      '${(await getApplicationSupportDirectory()).path}/$_kFileName',
    );
    return _macosFile!;
  }

  static Future<Map<String, String>> _loadMacos() async {
    if (_macosCache != null) return _macosCache!;
    try {
      final f = await _getFile();
      if (!f.existsSync()) {
        _macosCache = {};
        return _macosCache!;
      }
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _macosCache = raw.map((k, v) => MapEntry(k, v.toString()));
    } catch (e) {
      debugPrint('[SecureStorage] loadMacos failed: $e');
      _macosCache = {};
    }
    return _macosCache!;
  }

  static Future<void> _saveMacos(Map<String, String> data) {
    _macosCache = data;
    _saveGuard = _saveGuard.then((_) async {
      final f = await _getFile();
      final dir = f.parent;
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data));
      await tmp.rename(f.path);
    }, onError: (_) {});
    return _saveGuard;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<String?> read(String key) async {
    if (Platform.isMacOS) {
      return (await _loadMacos())[key];
    }
    return _storage.read(key: key);
  }

  Future<void> write(String key, String value) async {
    if (Platform.isMacOS) {
      final data = await _loadMacos();
      data[key] = value;
      await _saveMacos(data);
      return;
    }
    await _storage.write(key: key, value: value);
  }

  Future<void> delete(String key) async {
    if (Platform.isMacOS) {
      final data = await _loadMacos();
      data.remove(key);
      await _saveMacos(data);
      return;
    }
    await _storage.delete(key: key);
  }

  // ── WebDAV credentials ────────────────────────────────────────────────────

  static const _kWebDavUrl      = 'webdav_url';
  static const _kWebDavUsername = 'webdav_username';
  static const _kWebDavPassword = 'webdav_password';

  Future<Map<String, String>> getWebDavConfig() async => {
        'url':      await read(_kWebDavUrl)      ?? '',
        'username': await read(_kWebDavUsername) ?? '',
        'password': await read(_kWebDavPassword) ?? '',
      };

  Future<void> setWebDavConfig({
    required String url,
    required String username,
    required String password,
  }) async {
    await write(_kWebDavUrl,      url);
    await write(_kWebDavUsername, username);
    await write(_kWebDavPassword, password);
  }

  Future<void> clearWebDavConfig() async {
    await delete(_kWebDavUrl);
    await delete(_kWebDavUsername);
    await delete(_kWebDavPassword);
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
