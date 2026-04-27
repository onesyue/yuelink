import 'package:flutter/material.dart';

/// Minimal centred loader used by `_AuthGate` while
/// [AuthStatus.unknown] is the live value — the brief window between
/// `AuthNotifier.build()` returning the default `AuthState` and
/// `_init()` (or the bootstrap-supplied preload) landing a definitive
/// `loggedIn` / `loggedOut`.
///
/// v1.0.22 P0-4c: replaces the previous `SizedBox.shrink()` so a slow
/// SecureStorage cold-start renders a quiet spinner instead of a
/// blank Scaffold. Pairs with the bootstrap timeout in main()
/// (P0-4a) and the `_init()` timeout/catch in AuthNotifier (P0-4b)
/// — together they guarantee the unknown state is always transient,
/// so no copy / "having trouble?" affordance is needed here.
class AuthLoadingFallback extends StatelessWidget {
  const AuthLoadingFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
