import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/auth_token_service.dart';
import '../../../infrastructure/datasources/xboard_api.dart';
import '../../../modules/profiles/providers/profiles_providers.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../services/profile_service.dart';

// ------------------------------------------------------------------
// Auth state
// ------------------------------------------------------------------

enum AuthStatus { unknown, loggedOut, loggedIn }

class AuthState {
  final AuthStatus status;
  final String? token;
  final UserProfile? userProfile;
  final String? error;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.token,
    this.userProfile,
    this.error,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? token,
    UserProfile? userProfile,
    String? error,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
      userProfile: userProfile ?? this.userProfile,
      error: error,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  bool get isLoggedIn => status == AuthStatus.loggedIn && token != null;
}

// ------------------------------------------------------------------
// XBoard API provider
// ------------------------------------------------------------------

/// Default XBoard panel URL — override via AuthTokenService.saveApiHost().
const _kDefaultApiHost = 'https://yueto.app';

final xboardApiProvider = Provider<XBoardApi>((ref) {
  // The actual host will be resolved asynchronously in AuthNotifier.
  // This provides a default instance; login flow overrides baseUrl.
  return XBoardApi(baseUrl: _kDefaultApiHost);
});

// ------------------------------------------------------------------
// Auth notifier
// ------------------------------------------------------------------

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState()) {
    _init();
  }

  final Ref _ref;
  final _authService = AuthTokenService.instance;

  /// Check if user has a saved token on app startup.
  Future<void> _init() async {
    final token = await _authService.getToken();
    if (token != null && token.isNotEmpty) {
      final cachedProfile = await _authService.getCachedProfile();
      state = AuthState(
        status: AuthStatus.loggedIn,
        token: token,
        userProfile: cachedProfile,
      );
      // Refresh user info in background
      _refreshUserInfo(token);
    } else {
      state = const AuthState(status: AuthStatus.loggedOut);
    }
  }

  /// Login with email and password.
  Future<bool> login(String email, String password, {String? apiHost}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Resolve API host
      final host = apiHost ?? _kDefaultApiHost;
      final api = XBoardApi(baseUrl: host);

      // 1. Login
      final loginResp = await api.login(email, password);
      final token = loginResp.token;

      // 2. Save token and host
      await _authService.saveToken(token);
      await _authService.saveApiHost(host);

      // 3. Get user info
      UserProfile? profile;
      try {
        profile = await api.getUserInfo(token);
        await _authService.cacheProfile(profile);
      } catch (e) {
        debugPrint('[Auth] Failed to fetch user info: $e');
      }

      // 4. Get subscribe URL and sync subscription
      try {
        final subscribeUrl = await api.getSubscribeUrl(token);
        await _authService.saveSubscribeUrl(subscribeUrl);
        // Auto-sync subscription in background
        _syncSubscription(subscribeUrl);
      } catch (e) {
        debugPrint('[Auth] Failed to get subscribe URL: $e');
      }

      state = AuthState(
        status: AuthStatus.loggedIn,
        token: token,
        userProfile: profile,
      );

      return true;
    } on XBoardApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Logout and clear all auth data.
  Future<void> logout() async {
    await _authService.clearAll();
    state = const AuthState(status: AuthStatus.loggedOut);
  }

  /// Refresh user info from server.
  Future<void> refreshUserInfo() async {
    final token = state.token;
    if (token == null) return;
    await _refreshUserInfo(token);
  }

  Future<void> _refreshUserInfo(String token) async {
    try {
      final host = await _authService.getApiHost() ?? _kDefaultApiHost;
      final api = XBoardApi(baseUrl: host);
      final profile = await api.getUserInfo(token);
      await _authService.cacheProfile(profile);
      if (mounted) {
        state = state.copyWith(userProfile: profile);
      }
    } catch (e) {
      debugPrint('[Auth] Failed to refresh user info: $e');
      // If 401/403, token may be expired
      if (e is XBoardApiException && (e.statusCode == 401 || e.statusCode == 403)) {
        await logout();
      }
    }
  }

  /// Sync subscription: download config and create/update profile.
  Future<void> syncSubscription() async {
    final subscribeUrl = await _authService.getSubscribeUrl();
    if (subscribeUrl == null) {
      // Try to fetch subscribe URL first
      final token = state.token;
      if (token == null) return;
      try {
        final host = await _authService.getApiHost() ?? _kDefaultApiHost;
        final api = XBoardApi(baseUrl: host);
        final url = await api.getSubscribeUrl(token);
        await _authService.saveSubscribeUrl(url);
        await _syncSubscription(url);
      } catch (e) {
        debugPrint('[Auth] Failed to sync subscription: $e');
      }
    } else {
      await _syncSubscription(subscribeUrl);
    }
  }

  /// Internal: download and save subscription config.
  Future<void> _syncSubscription(String subscribeUrl) async {
    try {
      debugPrint('[Auth] Syncing subscription from: ${subscribeUrl.substring(0, subscribeUrl.length.clamp(0, 50))}...');

      // Use ProfileService.addProfile for consistent config processing.
      // Check if we already have a "悦通" profile — update it instead of adding.
      final profiles = await ProfileService.loadProfiles();
      final existing = profiles.where((p) => p.name == '悦通').toList();

      final proxyPort = CoreManager.instance.isRunning
          ? CoreManager.instance.mixedPort
          : null;

      if (existing.isNotEmpty) {
        // Update existing profile
        final profile = existing.first;
        profile.url = subscribeUrl;
        await ProfileService.updateProfile(profile, proxyPort: proxyPort);
        debugPrint('[Auth] Updated existing 悦通 profile: ${profile.id}');
      } else {
        // Create new profile
        final profile = await ProfileService.addProfile(
          name: '悦通',
          url: subscribeUrl,
          proxyPort: proxyPort,
        );
        debugPrint('[Auth] Created new 悦通 profile: ${profile.id}');

        // Auto-select the new profile
        _ref.read(activeProfileIdProvider.notifier).select(profile.id);
      }

      // Refresh profiles list in UI
      _ref.read(profilesProvider.notifier).load();
    } catch (e) {
      debugPrint('[Auth] Subscription sync failed: $e');
    }
  }
}

// ------------------------------------------------------------------
// Convenience providers
// ------------------------------------------------------------------

/// Whether the user is currently logged in.
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isLoggedIn;
});

/// Current user profile (may be null if not logged in or not yet fetched).
final userProfileProvider = Provider<UserProfile?>((ref) {
  return ref.watch(authProvider).userProfile;
});
