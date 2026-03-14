import 'dart:convert';

import 'secure_storage_service.dart';
import '../../infrastructure/datasources/xboard_api.dart';

/// Stores authentication credentials in OS-native secure storage.
///
/// Persists:
/// - auth_token: XBoard API token
/// - subscribe_url: user's subscription URL
/// - user_profile: cached user info (plan, traffic, expiry)
/// - api_host: XBoard panel base URL
class AuthTokenService {
  AuthTokenService._();
  static final instance = AuthTokenService._();

  SecureStorageService get _secure => SecureStorageService.instance;

  // Key constants
  static const _kToken = 'yue_auth_token';
  static const _kSubscribeUrl = 'yue_subscribe_url';
  static const _kUserProfile = 'yue_user_profile';
  static const _kApiHost = 'yue_api_host';

  // ── Token ───────────────────────────────────────────────────────────────────

  Future<String?> getToken() => _secure.read(_kToken);

  Future<void> saveToken(String token) => _secure.write(_kToken, token);

  Future<void> clearToken() => _secure.delete(_kToken);

  /// Whether the user has a saved auth token.
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ── Subscribe URL ───────────────────────────────────────────────────────────

  Future<String?> getSubscribeUrl() => _secure.read(_kSubscribeUrl);

  Future<void> saveSubscribeUrl(String url) =>
      _secure.write(_kSubscribeUrl, url);

  Future<void> clearSubscribeUrl() => _secure.delete(_kSubscribeUrl);

  // ── User profile (cached) ──────────────────────────────────────────────────

  Future<UserProfile?> getCachedProfile() async {
    final raw = await _secure.read(_kUserProfile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return UserProfile.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheProfile(UserProfile profile) =>
      _secure.write(_kUserProfile, jsonEncode(profile.toJson()));

  Future<void> clearCachedProfile() => _secure.delete(_kUserProfile);

  // ── API host ────────────────────────────────────────────────────────────────

  Future<String?> getApiHost() => _secure.read(_kApiHost);

  Future<void> saveApiHost(String host) => _secure.write(_kApiHost, host);

  // ── Clear all ───────────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    await clearToken();
    await clearSubscribeUrl();
    await clearCachedProfile();
  }
}
