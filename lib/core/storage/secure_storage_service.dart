import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Stores credentials in OS-native secure storage.
///
/// Platform strategy:
/// - Android  → Keystore-backed EncryptedSharedPreferences
/// - iOS      → Data Protection Keychain
/// - macOS    → macOS Keychain via MethodChannel (Security.framework).
///              Uses SecItemAdd/SecItemCopyMatching directly — no
///              keychain-access-groups entitlement needed for single-app use.
///              On first run, migrates any legacy JSON file data into Keychain
///              and deletes the plaintext file.
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

  // ── macOS: Keychain via MethodChannel ─────────────────────────────────────

  static const _keychainChannel = MethodChannel('com.yueto.yuelink/keychain');

  /// Whether legacy JSON → Keychain migration has been attempted this session.
  static bool _migrationDone = false;

  /// Migrate legacy plaintext JSON file into Keychain (one-time, best-effort).
  static Future<void> _migrateLegacyIfNeeded() async {
    if (_migrationDone) return;
    _migrationDone = true;
    try {
      final appDir = await getApplicationSupportDirectory();
      final legacyFile = File('${appDir.path}/.yuetong_cred.json');
      if (!legacyFile.existsSync()) return;

      final raw =
          jsonDecode(await legacyFile.readAsString()) as Map<String, dynamic>;
      for (final entry in raw.entries) {
        await _keychainChannel.invokeMethod('write', {
          'key': entry.key,
          'value': entry.value.toString(),
        });
      }
      // Remove plaintext file after successful migration
      await legacyFile.delete();
      // Also remove any .tmp leftover
      final tmpFile = File('${legacyFile.path}.tmp');
      if (tmpFile.existsSync()) await tmpFile.delete();
      debugPrint('[SecureStorage] Migrated ${raw.length} keys from JSON to Keychain');
    } catch (e) {
      debugPrint('[SecureStorage] Legacy migration failed (non-fatal): $e');
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<String?> read(String key) async {
    if (Platform.isMacOS) {
      await _migrateLegacyIfNeeded();
      try {
        final value =
            await _keychainChannel.invokeMethod<String>('read', {'key': key});
        return value;
      } on PlatformException catch (e) {
        debugPrint('[SecureStorage] Keychain read failed: $e');
        return null;
      }
    }
    return _storage.read(key: key);
  }

  Future<void> write(String key, String value) async {
    if (Platform.isMacOS) {
      await _migrateLegacyIfNeeded();
      await _keychainChannel
          .invokeMethod('write', {'key': key, 'value': value});
      return;
    }
    await _storage.write(key: key, value: value);
  }

  Future<void> delete(String key) async {
    if (Platform.isMacOS) {
      await _migrateLegacyIfNeeded();
      await _keychainChannel.invokeMethod('delete', {'key': key});
      return;
    }
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
