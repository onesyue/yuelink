import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/yue_auth/providers/yue_auth_providers.dart';

/// Regression coverage for v1.0.22 P0-4b: AuthNotifier._init must
///   1. NOT run when bootstrap supplied a definitive preloaded state
///      (loggedIn / loggedOut), so the warm-path stays zero-await.
///   2. Run when bootstrap supplied `null` or `unknown` (the
///      "auth uncertain" signal main() emits when SecureStorage
///      timed out or threw at cold start).
///   3. Bottom out at AuthStatus.loggedOut on its own internal
///      timeout — never leave state permanently at AuthStatus.unknown,
///      which would render `_AuthGate` to a blank Scaffold.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Completer<dynamic>? hangCompleter;

  Future<dynamic> _maybeHang(dynamic onResolve) {
    if (hangCompleter != null) return hangCompleter!.future;
    return Future.value(onResolve);
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('yuelink_auth_init_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory' ||
            call.method == 'getApplicationDocumentsDirectory') {
          return _maybeHang(tempDir.path);
        }
        return null;
      },
    );

    // flutter_secure_storage path (non-macOS hosts).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'read') return _maybeHang(null);
        if (call.method == 'readAll') return _maybeHang(<String, String>{});
        return null;
      },
    );
  });

  tearDownAll(() {
    hangCompleter?.complete(null);
    tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    hangCompleter = null;
    AuthNotifier.initStorageTimeout = const Duration(seconds: 5);
  });

  tearDown(() {
    hangCompleter?.complete(null);
    hangCompleter = null;
    AuthNotifier.initStorageTimeout = const Duration(seconds: 5);
  });

  test(
    'preloaded loggedOut keeps state and never transitions through unknown '
    '— warm-path contract preserved',
    () async {
      final container = ProviderContainer(overrides: [
        preloadedAuthStateProvider
            .overrideWithValue(const AuthState(status: AuthStatus.loggedOut)),
      ]);
      addTearDown(container.dispose);

      // build()'s early-return path puts state at loggedOut directly —
      // no transient unknown means _init() was not invoked.
      final state = container.read(authProvider);
      expect(state.status, AuthStatus.loggedOut);

      // Allow microtasks to drain. State must still be loggedOut and
      // never have flickered through any other status.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(container.read(authProvider).status, AuthStatus.loggedOut);
    },
  );

  test(
    'preloaded null triggers _init() — observable via unknown→loggedOut '
    'transition',
    () async {
      final container = ProviderContainer(overrides: [
        preloadedAuthStateProvider.overrideWithValue(null),
      ]);
      addTearDown(container.dispose);

      // build() returns the empty AuthState (status=unknown) BEFORE
      // _init() resolves. This transient unknown is the observable
      // proof that the early-return fast path was skipped.
      final initial = container.read(authProvider);
      expect(
        initial.status,
        AuthStatus.unknown,
        reason: 'null preload must NOT short-circuit build(); _init() '
            'is responsible for landing on a definitive status',
      );

      // _init() runs against the storage mock (no token) and settles
      // to loggedOut. The transition unknown→loggedOut is the
      // signature of _init() having completed.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(container.read(authProvider).status, AuthStatus.loggedOut);
    },
  );

  test(
    'preloaded unknown also triggers _init() — symmetric with null',
    () async {
      // The bootstrap signal is documented as "null OR unknown means
      // uncertain". Both must produce the same recovery behaviour.
      final container = ProviderContainer(overrides: [
        preloadedAuthStateProvider
            .overrideWithValue(const AuthState(status: AuthStatus.unknown)),
      ]);
      addTearDown(container.dispose);

      final initial = container.read(authProvider);
      expect(initial.status, AuthStatus.unknown);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      final settled = container.read(authProvider);
      expect(settled.status, AuthStatus.loggedOut,
          reason: 'unknown preload must also trip _init()');
    },
  );

  test(
    '_init() storage hang bottoms out at loggedOut within timeout '
    '— no permanent unknown / blank screen',
    () async {
      // The exact white-screen scenario P0-4b targets: bootstrap
      // gave up (preloaded=null), _init() runs, but SecureStorage is
      // still wedged. With the timeout in place, state must settle
      // to loggedOut so the user sees a login page rather than the
      // AuthStatus.unknown → SizedBox.shrink() blank.
      AuthNotifier.initStorageTimeout = const Duration(milliseconds: 200);
      hangCompleter = Completer<dynamic>();

      final container = ProviderContainer(overrides: [
        preloadedAuthStateProvider.overrideWithValue(null),
      ]);
      addTearDown(container.dispose);

      final initial = container.read(authProvider);
      expect(initial.status, AuthStatus.unknown);

      // Wait long enough for the 200 ms timeout + the catch-block
      // state write to land. Generous grace: the goal is to prove
      // it eventually settles, not to assert exact wall-clock.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final settled = container.read(authProvider);
      expect(
        settled.status,
        AuthStatus.loggedOut,
        reason:
            'storage hang must settle to loggedOut, not stay at unknown',
      );
    },
  );

  test(
    'dispose during _init() storage hang does not write state',
    () async {
      // Defence in depth: even if _init() catches the timeout AFTER
      // the container has been disposed, the `_disposed` guard in the
      // catch block must prevent `state =` from throwing.
      AuthNotifier.initStorageTimeout = const Duration(milliseconds: 100);
      hangCompleter = Completer<dynamic>();

      final errors = <Object>[];
      final container = ProviderContainer(overrides: [
        preloadedAuthStateProvider.overrideWithValue(null),
      ]);
      // Read to instantiate, then dispose immediately.
      container.read(authProvider);
      container.dispose();

      // Hold the zone briefly so _init's timeout can fire post-dispose.
      await runZonedGuarded(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }, (e, _) {
        errors.add(e);
      });

      expect(
        errors.where(
          (e) => e.toString().toLowerCase().contains('disposed'),
        ),
        isEmpty,
        reason:
            'catch branch must respect _disposed before writing state',
      );
    },
  );
}
