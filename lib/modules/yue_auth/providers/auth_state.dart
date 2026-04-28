import '../../../infrastructure/datasources/xboard/index.dart' show UserProfile;

/// Auth lifecycle phases the UI can render against.
///
/// `unknown` is the cold-start placeholder before bootstrap reads the
/// persisted token; the auth gate must NOT show login UI in this phase
/// (a 100ms flash would be jarring).
enum AuthStatus { unknown, loggedOut, loggedIn, guest }

/// Immutable snapshot of the auth subsystem.
///
/// Was inlined in `yue_auth_providers.dart` (~50 lines). Pulled into its
/// own file so widgets that only need the state shape don't drag in
/// AuthNotifier's heavy import surface (CoreManager, RecoveryManager,
/// AppNotifier, …).
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

  /// Copy with nullable field support. Pass `clearToken` or `clearProfile`
  /// as `true` to explicitly null out the field (since `null` means
  /// "keep").
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
