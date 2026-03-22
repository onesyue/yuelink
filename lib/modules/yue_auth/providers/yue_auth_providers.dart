import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/auth_token_service.dart';
import '../../../infrastructure/datasources/xboard_api.dart';
import '../../../l10n/app_strings.dart';
import '../../../modules/profiles/providers/profiles_providers.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../infrastructure/repositories/profile_repository.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/event_log.dart';

// ------------------------------------------------------------------
// Auth state
// ------------------------------------------------------------------

enum AuthStatus { unknown, loggedOut, loggedIn, guest }

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

  /// Copy with nullable field support. Pass [_clearToken] or [_clearProfile]
  /// as `true` to explicitly null out the field (since `null` means "keep").
  AuthState copyWith({
    AuthStatus? status,
    String? token,
    bool clearToken = false,
    UserProfile? userProfile,
    bool clearProfile = false,
    String? error,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: clearToken ? null : (token ?? this.token),
      userProfile: clearProfile ? null : (userProfile ?? this.userProfile),
      error: error,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  bool get isLoggedIn => status == AuthStatus.loggedIn && token != null;
  bool get isGuest => status == AuthStatus.guest;
}

// ------------------------------------------------------------------
// XBoard API provider
// ------------------------------------------------------------------

/// Default XBoard panel URL — override via AuthTokenService.saveApiHost().
/// Must match the CloudFront custom domain so TLS SNI handshake succeeds.
const _kDefaultApiHost = 'https://d7ccm19ki90mg.cloudfront.net';

/// Tracks the current API host — updated on login and restored from storage.
final _apiHostProvider = StateProvider<String>((ref) => _kDefaultApiHost);

final xboardApiProvider = Provider<XBoardApi>((ref) {
  final host = ref.watch(_apiHostProvider);
  return XBoardApi(baseUrl: host);
});

// ------------------------------------------------------------------
// Auth notifier
// ------------------------------------------------------------------

/// Pre-loaded auth state, overridden in main.dart ProviderScope to
/// eliminate the blank screen from async AuthNotifier._init().
final preloadedAuthStateProvider = Provider<AuthState?>((ref) => null);

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthState> {
  late final AuthTokenService _authService;
  bool _disposed = false;

  @override
  AuthState build() {
    _disposed = false;
    _authService = AuthTokenService.instance;
    ref.onDispose(() => _disposed = true);

    final initial = ref.read(preloadedAuthStateProvider);
    if (initial != null && initial.status != AuthStatus.unknown) {
      // Pre-loaded in main() — skip async _init(), just refresh in background
      if (initial.token != null) _refreshUserInfo(initial.token!);
      return initial;
    }
    _init();
    return const AuthState();
  }

  /// Check if user has a saved token on app startup.
  Future<void> _init() async {
    final token = await _authService.getToken();
    if (token != null && token.isNotEmpty) {
      // Restore saved API host so all providers use the correct endpoint
      final savedHost = await _authService.getApiHost();
      if (savedHost != null && savedHost.isNotEmpty) {
        ref.read(_apiHostProvider.notifier).state = savedHost;
      }
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

      // 2. Save token and host, update provider so all consumers get correct host
      await _authService.saveToken(token);
      await _authService.saveApiHost(host);
      ref.read(_apiHostProvider.notifier).state = host;
      EventLog.write('[Auth] login_ok');

      // 3. Get subscribe data (profile + URL) in one request.
      //    /api/v1/user/getSubscribe returns plan name, u/d traffic, expiry, subscribe_url.
      //    /api/v1/user/info does NOT return u/d or nested plan object — do not use it.
      UserProfile? profile;
      try {
        final sub = await api.getSubscribeData(token);
        profile = sub.profile;
        await _authService.cacheProfile(profile);
        await _authService.saveSubscribeUrl(sub.subscribeUrl);
        // Auto-sync subscription config in background (errors handled inside)
        _syncSubscription(sub.subscribeUrl).catchError((e) {
          debugPrint('[Auth] Background sync failed: $e');
        });
      } catch (e) {
        debugPrint('[Auth] Failed to fetch subscribe data: $e');
      }

      state = AuthState(
        status: AuthStatus.loggedIn,
        token: token,
        userProfile: profile,
      );

      return true;
    } on XBoardApiException catch (e) {
      EventLog.write('[Auth] login_fail status=${e.statusCode}');
      state = state.copyWith(
        isLoading: false,
        error: _friendlyLoginError(e),
      );
      return false;
    } catch (e) {
      EventLog.write('[Auth] login_fail error=${e.runtimeType}');
      state = state.copyWith(
        isLoading: false,
        error: _friendlyNetworkError(e),
      );
      return false;
    }
  }

  /// Maps API/network exceptions to user-friendly login error messages.
  static String _friendlyLoginError(XBoardApiException e) {
    if (e.statusCode == 401 || e.statusCode == 422 || e.statusCode == 400) {
      // Check if server sent a readable message (XBoard often does)
      final msg = e.message;
      if (msg.isNotEmpty && msg.length < 80 && !msg.startsWith('{')) return msg;
      return S.current.authErrorBadCredentials;
    }
    if (e.statusCode >= 500) return S.current.authErrorServer;
    if (e.statusCode == 0) return S.current.authErrorNetwork;
    final msg = e.message;
    if (msg.isNotEmpty && msg.length < 80) return msg;
    return S.current.authErrorServer;
  }

  static String _friendlyNetworkError(dynamic e) {
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('HandshakeException') ||
        s.contains('TimeoutException') ||
        s.contains('NetworkException')) {
      return S.current.authErrorNetwork;
    }
    return S.current.authErrorNetwork;
  }

  /// Enter guest mode (skip login). User can import profiles manually.
  void skipLogin() {
    state = const AuthState(status: AuthStatus.guest);
  }

  /// Logout and clear all auth data, profiles, and stop VPN.
  Future<void> logout() async {
    // Stop running VPN/core before clearing data
    try {
      final manager = CoreManager.instance;
      if (manager.isRunning) await manager.stop();
    } catch (e) {
      debugPrint('[Auth] stop core on logout failed: $e');
    }

    // Clear all subscription profiles
    try {
      final repo = ref.read(profileRepositoryProvider);
      final profiles = await repo.loadProfiles();
      for (final p in profiles) {
        await repo.deleteProfile(p.id);
      }
    } catch (e) {
      debugPrint('[Auth] clear profiles on logout failed: $e');
    }

    await _authService.clearAll();
    state = const AuthState(status: AuthStatus.loggedOut);
  }

  /// Called when any API returns 401/403. Shows a toast and logs out.
  /// Call this from any provider that detects token expiry.
  Future<void> handleUnauthenticated() async {
    if (state.status != AuthStatus.loggedIn) return; // already logged out
    EventLog.write('[Auth] session_expired auto_logout');
    AppNotifier.warning(S.current.authSessionExpired);
    await logout();
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
      final sub = await api.getSubscribeData(token);
      await _authService.cacheProfile(sub.profile);
      // Also update subscribe URL in case it changed
      await _authService.saveSubscribeUrl(sub.subscribeUrl);
      if (!_disposed) {
        state = state.copyWith(userProfile: sub.profile);
      }
    } catch (e) {
      debugPrint('[Auth] Failed to refresh user info: $e');
      if (e is XBoardApiException && (e.statusCode == 401 || e.statusCode == 403)) {
        await handleUnauthenticated();
      }
    }
  }

  /// Sync subscription: refresh profile data and download proxy config.
  Future<void> syncSubscription() async {
    final token = state.token;
    if (token == null) return;
    try {
      final host = await _authService.getApiHost() ?? _kDefaultApiHost;
      final api = XBoardApi(baseUrl: host);
      // Always fetch fresh from server — also updates profile data
      final sub = await api.getSubscribeData(token);
      await _authService.cacheProfile(sub.profile);
      await _authService.saveSubscribeUrl(sub.subscribeUrl);
      if (!_disposed) state = state.copyWith(userProfile: sub.profile);
      await _syncSubscription(sub.subscribeUrl);
    } catch (e) {
      debugPrint('[Auth] Failed to sync subscription: $e');
      if (e is XBoardApiException && (e.statusCode == 401 || e.statusCode == 403)) {
        await handleUnauthenticated();
        return; // after logout, don't rethrow
      }
      rethrow;
    }
  }

  /// Internal: download and save subscription config.
  Future<void> _syncSubscription(String subscribeUrl) async {
    debugPrint('[Auth] Syncing subscription from: ${subscribeUrl.substring(0, subscribeUrl.length.clamp(0, 50))}...');

    // Use ProfileRepository for consistent config processing.
    // Check if we already have a "悦通" profile — update it instead of adding.
    final repo = ref.read(profileRepositoryProvider);
    final profiles = await repo.loadProfiles();
    final existing = profiles.where((p) => p.name == '悦通').toList();
    final isFirstTime = existing.isEmpty;

    final proxyPort = CoreManager.instance.isRunning
        ? CoreManager.instance.mixedPort
        : null;

    if (existing.isNotEmpty) {
      // Update existing profile
      final profile = existing.first;
      profile.url = subscribeUrl;
      await repo.updateProfile(profile, proxyPort: proxyPort);
      debugPrint('[Auth] Updated existing 悦通 profile: ${profile.id}');
    } else {
      // Create new profile
      final profile = await repo.addProfile(
        name: '悦通',
        url: subscribeUrl,
        proxyPort: proxyPort,
      );
      debugPrint('[Auth] Created new 悦通 profile: ${profile.id}');

      // Auto-select the new profile
      ref.read(activeProfileIdProvider.notifier).select(profile.id);
    }

    // Refresh profiles list in UI
    ref.read(profilesProvider.notifier).load();

    // First-time sync: welcome the user
    if (isFirstTime) {
      EventLog.write('[Sync] sync_ok first_time=true');
      AppNotifier.success(S.current.syncFirstSuccess);
    } else {
      EventLog.write('[Sync] sync_ok update=true');
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
