import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores sensitive credentials in OS-native secure storage:
/// - macOS / iOS   → Keychain
/// - Android       → Keystore-backed EncryptedSharedPreferences
/// - Windows       → Credential Locker (DPAPI)
///
/// Only store fields that are truly sensitive (passwords, auth secrets).
/// Non-sensitive settings continue to live in SettingsService (plain JSON).
class SecureStorageService {
  SecureStorageService._();
  static final instance = SecureStorageService._();

  static const _storage = FlutterSecureStorage(
    // Android: encrypt with AES-256 key stored in Android Keystore
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // macOS/iOS: use Keychain with accessible-when-unlocked attribute
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.unlocked),
    // Windows: DPAPI (system-user-scoped encryption)
    wOptions: WindowsOptions(),
  );

  // ── WebDAV credentials ────────────────────────────────────────────────────

  static const _kWebDavUrl      = 'webdav_url';
  static const _kWebDavUsername = 'webdav_username';
  static const _kWebDavPassword = 'webdav_password';

  Future<Map<String, String>> getWebDavConfig() async {
    return {
      'url':      await _storage.read(key: _kWebDavUrl)      ?? '',
      'username': await _storage.read(key: _kWebDavUsername) ?? '',
      'password': await _storage.read(key: _kWebDavPassword) ?? '',
    };
  }

  Future<void> setWebDavConfig({
    required String url,
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _kWebDavUrl,      value: url);
    await _storage.write(key: _kWebDavUsername, value: username);
    await _storage.write(key: _kWebDavPassword, value: password);
  }

  Future<void> clearWebDavConfig() async {
    await _storage.delete(key: _kWebDavUrl);
    await _storage.delete(key: _kWebDavUsername);
    await _storage.delete(key: _kWebDavPassword);
  }

  // ── Subscription URL tokens ───────────────────────────────────────────────
  // Subscription URLs often contain auth tokens (e.g. ?token=xxx).
  // We store them keyed by profile ID so they never land in plain JSON.

  static String _subKey(String profileId) => 'sub_url_$profileId';

  Future<String?> getSubscriptionUrl(String profileId) async {
    return _storage.read(key: _subKey(profileId));
  }

  Future<void> setSubscriptionUrl(String profileId, String url) async {
    await _storage.write(key: _subKey(profileId), value: url);
  }

  Future<void> deleteSubscriptionUrl(String profileId) async {
    await _storage.delete(key: _subKey(profileId));
  }

  // ── API secret ────────────────────────────────────────────────────────────

  static const _kApiSecret = 'mihomo_api_secret';

  Future<String?> getApiSecret() => _storage.read(key: _kApiSecret);

  Future<void> setApiSecret(String secret) =>
      _storage.write(key: _kApiSecret, value: secret);
}
