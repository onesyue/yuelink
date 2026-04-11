import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:yuelink/main.dart' as app;

/// Core business flow E2E test.
///
/// Verifies that the app launches without crashing and renders its first
/// frame containing both a `MaterialApp` and a `Scaffold`. This is the
/// minimum smoke test that catches catastrophic regressions in the auth
/// gate / Riverpod wiring / window manager — the things most likely to
/// break a desktop release.
///
/// Integration tests REQUIRE a device target. `flutter test integration_test/`
/// without `-d` will silently report "No tests were found" — that's not a
/// missing test, it's the test runner refusing to run integration_test
/// without a device.
///
/// Local on macOS host:
///   flutter test integration_test/ -d macos
///
/// Local on connected Android emulator / device:
///   `flutter test integration_test/ -d {emulator-id}`
///
/// CI: see .github/workflows/build.yml `integration` job — runs
/// `flutter test integration_test/ -d macos` on the macos-latest runner.
///
/// IMPORTANT: there is exactly ONE testWidgets case in this file. Calling
/// `app.main()` more than once in the same test process re-initialises the
/// Riverpod ProviderScope, window_manager, hotkey_manager, and other
/// singletons that don't tolerate double-init — the second test would
/// hang in `pumpAndSettle` because YueLink has long-lived timers
/// (heartbeat, traffic stream, profile sync) that never settle. To assert
/// multiple things about the launched app, do them all inside the single
/// case below.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches and renders dashboard scaffold', (tester) async {
    app.main();

    // YueLink has long-lived timers (heartbeat, traffic, sync) that
    // pumpAndSettle would never wait out. Use fixed pump duration instead
    // — 8 seconds is enough for the auth gate to resolve and the first
    // frame to render on a CI runner.
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));

    // 1. The Flutter app shell mounted
    expect(find.byType(MaterialApp), findsOneWidget,
        reason: 'MaterialApp must be the root widget');

    // 2. Some Scaffold rendered (auth gate or main shell). The auth gate
    //    can return either Scaffold (logged out) or MainShell (logged in
    //    from cache); both contain at least one Scaffold.
    expect(find.byType(Scaffold), findsWidgets,
        reason: 'A Scaffold should be visible after launch');
  });
}
