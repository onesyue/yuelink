import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'secure_storage_service.dart';
import '../../infrastructure/datasources/xboard/index.dart';

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

  static const _kProfileCachedAt = 'yue_profile_cached_at';

  Future<UserProfile?> getCachedProfile() async {
    final raw = await _secure.read(_kUserProfile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return UserProfile.fromJson(json);
    } catch (e) {
      debugPrint('[AuthTokenService] Failed to parse cached profile: $e');
      return null;
    }
  }

  /// Whether the cached profile is older than [maxAge] (default 1 hour).
  Future<bool> isProfileStale({Duration maxAge = const Duration(hours: 1)}) async {
    final raw = await _secure.read(_kProfileCachedAt);
    if (raw == null || raw.isEmpty) return true;
    final cachedAt = DateTime.tryParse(raw);
    if (cachedAt == null) return true;
    return DateTime.now().difference(cachedAt) > maxAge;
  }

  Future<void> cacheProfile(UserProfile profile) async {
    await _secure.write(_kUserProfile, jsonEncode(profile.toJson()));
    await _secure.write(_kProfileCachedAt, DateTime.now().toIso8601String());
  }

  Future<void> clearCachedProfile() async {
    await _secure.delete(_kUserProfile);
    await _secure.delete(_kProfileCachedAt);
  }

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
