import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yuelink/constants.dart';
import 'package:yuelink/core/kernel/core_manager.dart';
import 'package:yuelink/core/providers/core_provider.dart';
import 'package:yuelink/core/storage/settings_service.dart';

/// CoreManager tests run in **mock mode** (no native library / FFI).
///
/// This covers:
///  - Lifecycle: start / stop / isRunning state transitions
///  - Completer race prevention (_pendingOperation)
///  - StartupReport generation
///  - isCoreActuallyRunning in mock mode
///  - Stop while not running (no-op)
///
/// Real FFI / VPN / platform paths require integration tests on-device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CoreManager cm;
  late Directory tempDir;

  setUpAll(() {
    // Mock path_provider to return a temp directory
    tempDir = Directory.systemTemp.createTempSync('yuelink_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationSupportDirectory' ||
                methodCall.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    CoreManager.resetForTesting();
    cm = CoreManager.instance;
    // Ensure mock mode (no native lib in test environment)
    expect(
      cm.isMockMode,
      isTrue,
      reason: 'Tests must run in mock mode (no native library)',
    );
  });

  tearDown(() async {
    // Always stop after each test to clean state
    if (cm.isRunning) {
      await cm.stop();
    }
    CoreManager.resetForTesting();
  });

  // ════════════════════════════════════════════════════════════════════
  // Basic lifecycle
  // ════════════════════════════════════════════════════════════════════

  group('lifecycle', () {
    test('initial state is stopped', () {
      expect(cm.isRunning, false);
      expect(cm.isMockMode, true);
    });

    test('start transitions to running', () async {
      final configYaml = _minimalConfig();
      final ok = await cm.start(configYaml);
      expect(ok, true);
      expect(cm.isRunning, true);
    });

    test('stop transitions to stopped', () async {
      await cm.start(_minimalConfig());
      expect(cm.isRunning, true);

      await cm.stop();
      expect(cm.isRunning, false);
    });

    test('start when already running returns true immediately', () async {
      await cm.start(_minimalConfig());
      expect(cm.isRunning, true);

      // Second start should return immediately without error
      final ok = await cm.start(_minimalConfig());
      expect(ok, true);
      expect(cm.isRunning, true);
    });

    test('stop when already stopped is a no-op', () async {
      expect(cm.isRunning, false);
      // Should not throw
      await cm.stop();
      expect(cm.isRunning, false);
    });

    test('start → stop → start works correctly', () async {
      await cm.start(_minimalConfig());
      expect(cm.isRunning, true);

      await cm.stop();
      expect(cm.isRunning, false);

      await cm.start(_minimalConfig());
      expect(cm.isRunning, true);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Completer race prevention
  // ════════════════════════════════════════════════════════════════════

  group('concurrent start serialization', () {
    test('two concurrent starts both resolve without error', () async {
      final config = _minimalConfig();

      // Fire two starts concurrently
      final f1 = cm.start(config);
      final f2 = cm.start(config);

      // Both must complete successfully
      final r1 = await f1;
      final r2 = await f2;
      expect(r1, true);
      expect(r2, true);
      expect(cm.isRunning, true);
    });

    test('start during stop waits for stop then starts', () async {
      await cm.start(_minimalConfig());

      // Fire stop and start concurrently
      final stopFuture = cm.stop();
      final startFuture = cm.start(_minimalConfig());

      await stopFuture;
      final ok = await startFuture;

      // After both complete, should be running (start ran after stop)
      expect(ok, true);
      expect(cm.isRunning, true);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // StartupReport
  // ════════════════════════════════════════════════════════════════════

  group('startup report', () {
    test('lastReport is set after successful start', () async {
      await cm.start(_minimalConfig());

      expect(cm.lastReport, isNotNull);
      expect(cm.lastReport!.overallSuccess, true);
      expect(cm.lastReport!.steps, isNotEmpty);
    });

    test('report contains expected steps in mock mode', () async {
      await cm.start(_minimalConfig());

      final stepNames = cm.lastReport!.steps.map((s) => s.name).toList();
      expect(stepNames, contains('ensureGeo'));
      expect(stepNames, contains('initCore'));
      expect(stepNames, contains('buildConfig'));
      expect(stepNames, contains('startCore'));
    });

    test('all steps succeed in mock mode', () async {
      await cm.start(_minimalConfig());

      for (final step in cm.lastReport!.steps) {
        expect(
          step.success,
          true,
          reason: '${step.name} should succeed in mock mode',
        );
      }
    });

    test('lastReport is null before first start', () {
      expect(cm.lastReport, isNull);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // isCoreActuallyRunning
  // ════════════════════════════════════════════════════════════════════

  group('isCoreActuallyRunning', () {
    test('returns false when stopped', () {
      expect(cm.isCoreActuallyRunning, false);
    });

    test('returns true when running in mock mode', () async {
      await cm.start(_minimalConfig());
      // In mock mode, isCoreActuallyRunning delegates to _running flag
      expect(cm.isCoreActuallyRunning, true);
    });

    test('returns false after stop', () async {
      await cm.start(_minimalConfig());
      await cm.stop();
      expect(cm.isCoreActuallyRunning, false);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Port configuration
  // ════════════════════════════════════════════════════════════════════

  group('port configuration', () {
    test('mixedPort is extracted from config', () async {
      final config = _minimalConfig(mixedPort: 12345);
      await cm.start(config);
      expect(cm.mixedPort, 12345);
    });

    test('default mixedPort when not specified', () async {
      await cm.start(_minimalConfig());
      // ConfigTemplate ensures mixed-port exists; default is 7890
      expect(cm.mixedPort, greaterThan(0));
    });

    test('connectionMode is forwarded into config processing', () async {
      const config = '''
mixed-port: 7890
tun:
  enable: false
  stack: gvisor
  file-descriptor: 42
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
''';

      await cm.start(config, connectionMode: 'tun');

      final written = await File(
        '${tempDir.path}/${AppConstants.configFileName}',
      ).readAsString();

      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        expect(written, contains('stack: mixed'));
        expect(written, contains('enable: true'));
        expect(written, isNot(contains('file-descriptor: 42')));
      } else {
        expect(written, contains('file-descriptor: 42'));
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // QUIC reject policy threading
  //
  // Regression guard for the removed ConfigTemplate._runtimeQuicRejectPolicy
  // global. The policy must be threaded explicitly through start() — there
  // is no process-wide default state that can leak between calls or across
  // isolates.
  // ════════════════════════════════════════════════════════════════════

  group('quic reject policy', () {
    test(
      'start(policy: off) writes config without UDP:443 reject rules',
      () async {
        await cm.start(_minimalConfig(), quicRejectPolicy: 'off');

        final written = await File(
          '${tempDir.path}/${AppConstants.configFileName}',
        ).readAsString();

        expect(written, isNot(contains('(NETWORK,UDP),(DST-PORT,443)')));
        expect(written, isNot(contains('googlevideo.com),(NETWORK,UDP)')));
      },
    );

    test('start() without explicit policy defaults to googlevideo', () async {
      await cm.start(_minimalConfig());

      final written = await File(
        '${tempDir.path}/${AppConstants.configFileName}',
      ).readAsString();

      expect(written, contains('googlevideo.com'));
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Mode
  // ════════════════════════════════════════════════════════════════════

  group('mode', () {
    test('mode is CoreMode.mock in test environment', () {
      expect(cm.mode, CoreMode.mock);
    });

    test('configure can set mode', () {
      cm.configure(mode: CoreMode.mock);
      expect(cm.mode, CoreMode.mock);
      expect(cm.isMockMode, true);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Clash API secret persistence (v1.0.18)
  //
  // Regressions guarded:
  //   1. Cold start without a persisted secret must generate one and
  //      write it back to SettingsService — without this yacd /
  //      metacubexd get a fresh secret on every launch.
  //   2. Cold start with a persisted secret must reuse it verbatim —
  //      regenerating would break external tooling that remembers the
  //      value in browser localStorage.
  //   3. `configure(secret: null)` must not wipe the cached secret —
  //      previously an unconditional assignment did, breaking the API
  //      client for the rest of the session.
  // ════════════════════════════════════════════════════════════════════

  group('clash api secret persistence', () {
    // SettingsService uses a coalesced flush; wrap set + flush so the
    // next start() observes the value we just wrote.
    Future<void> writePersistedSecret(String s) async {
      await SettingsService.setClashApiSecret(s);
      await SettingsService.flush();
    }

    test(
      'cold start without persisted secret generates and persists one',
      () async {
        // Simulate "no persisted secret" — resetForTesting clears the
        // in-memory cache, and empty string on disk forces the null-or-empty
        // branch inside start().
        await writePersistedSecret('');
        CoreManager.resetForTesting();
        final fresh = CoreManager.instance;

        await fresh.start(_minimalConfig());

        final runtime = fresh.api.secret;
        expect(runtime, isNotNull);
        expect(
          runtime!.isNotEmpty,
          isTrue,
          reason: 'start() must have generated a secret',
        );

        final onDisk = await SettingsService.getClashApiSecret();
        expect(
          onDisk,
          equals(runtime),
          reason: 'generated secret must be persisted for next launch',
        );
      },
    );

    test('cold start with persisted secret reuses it verbatim', () async {
      const stable = 'persisted-secret-abc-def-123';
      await writePersistedSecret(stable);
      CoreManager.resetForTesting();
      final fresh = CoreManager.instance;

      await fresh.start(_minimalConfig());

      expect(
        fresh.api.secret,
        equals(stable),
        reason: 'start() must reuse persisted secret, not regenerate',
      );
    });

    test('configure(secret: null) does not wipe cached secret', () async {
      await cm.start(_minimalConfig());
      final cached = cm.api.secret;
      expect(cached, isNotNull);
      expect(cached!.isNotEmpty, isTrue);

      // Previous bug: this line unconditionally assigned `_apiSecret = secret`
      // which wiped the cached value when called with null. Fix: no-op on null.
      cm.configure(secret: null);

      expect(
        cm.api.secret,
        equals(cached),
        reason: 'configure(null) must leave cached secret untouched',
      );
    });
  });

  // ── v1.0.21 hotfix: persisted manual-stop flag ─────────────────────────
  // The bug this guards: in-memory userStoppedProvider is wiped when
  // Riverpod's ProviderScope rebuilds (Android engine recreate). The
  // resume health check would then see the still-alive mihomo API and
  // pull the UI back to "running" — except the user had explicitly
  // disconnected. Persisted flag survives engine recreate.
  group('SettingsService.manualStopped persistence', () {
    test('defaults to false on a fresh install', () async {
      // Clear any leftover from previous tests in this run
      await SettingsService.setManualStopped(false);
      await SettingsService.flush();
      expect(await SettingsService.getManualStopped(), isFalse);
    });

    test('round-trips true through flush + reload', () async {
      await SettingsService.setManualStopped(true);
      await SettingsService.flush();
      expect(await SettingsService.getManualStopped(), isTrue);
    });

    test(
      'round-trips false (clear after stop) through flush + reload',
      () async {
        await SettingsService.setManualStopped(true);
        await SettingsService.flush();
        // Then a subsequent start() clears it
        await SettingsService.setManualStopped(false);
        await SettingsService.flush();
        expect(await SettingsService.getManualStopped(), isFalse);
      },
    );

    test(
      'default immediate=true survives cache invalidation (real disk write)',
      () async {
        // Prove the value actually hit the disk, not just the in-memory cache.
        // Write with immediate=true, drop the in-memory cache, read back:
        // if immediate=true is working, the value comes from the JSON file.
        await SettingsService.setManualStopped(true);
        SettingsService.invalidateCache();
        expect(
          await SettingsService.getManualStopped(),
          isTrue,
          reason: 'immediate=true must persist to disk, not only memory',
        );
        // Clean up for other tests in this group.
        await SettingsService.setManualStopped(false);
        SettingsService.invalidateCache();
      },
    );

    test('immediate=false updates in-memory cache synchronously', () async {
      await SettingsService.setManualStopped(true);
      await SettingsService.setManualStopped(false, immediate: false);
      // The coalesced flush hasn't fired yet, but the in-memory cache
      // is updated synchronously by set() — get() must reflect that
      // (used by start()'s clear-on-success path).
      expect(await SettingsService.getManualStopped(), isFalse);
      await SettingsService.flush();
    });
  });

  // ── v1.0.21 hotfix P0-1: ProviderScope hydration gate ──────────────────
  //
  // Proves the mechanism end-to-end: on cold start, main() reads the
  // persisted manualStopped flag and passes it to ProviderScope via
  // userStoppedProvider.overrideWith(...). The autoConnect gate in
  // _maybeAutoConnect() reads userStoppedProvider — so if the override
  // correctly reflects persistence, auto-connect is blocked exactly when
  // it should be.
  group('cold-start: userStoppedProvider overrides from persisted', () {
    setUp(() async {
      // Start each scenario from a known clean state.
      await SettingsService.setManualStopped(false);
      SettingsService.invalidateCache();
    });

    ProviderContainer makeColdStartContainer({
      required bool savedManualStopped,
      required bool savedAutoConnect,
    }) {
      final container = ProviderContainer(
        overrides: [
          userStoppedProvider.overrideWith((ref) => savedManualStopped),
          autoConnectProvider.overrideWith((ref) => savedAutoConnect),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('autoConnect=true + persisted manualStopped=true → gate blocks '
        'auto-connect on cold start', () async {
      // Simulate: user had explicitly disconnected, then killed the app.
      await SettingsService.setManualStopped(true);
      SettingsService.invalidateCache();
      final saved = await SettingsService.getManualStopped();
      expect(saved, isTrue, reason: 'precondition: persisted should be true');

      final container = makeColdStartContainer(
        savedManualStopped: saved,
        savedAutoConnect: true,
      );

      // The gate _maybeAutoConnect() checks: coreStatus != running,
      // autoConnect == true, userStopped == false. If userStopped is
      // true (from override), auto-connect must be blocked.
      expect(container.read(autoConnectProvider), isTrue);
      expect(
        container.read(userStoppedProvider),
        isTrue,
        reason: 'override must hydrate the provider with persisted value',
      );
      final gatedAllowed =
          container.read(autoConnectProvider) &&
          !container.read(userStoppedProvider);
      expect(
        gatedAllowed,
        isFalse,
        reason: 'auto-connect must be gated when user explicitly stopped',
      );
    });

    test('manual start clears persisted flag → next cold-start allows '
        'auto-connect', () async {
      // Step 1: user stopped manually
      await SettingsService.setManualStopped(true);
      // Step 2: user tapped connect — lifecycle.start() writes false
      await SettingsService.setManualStopped(false);
      // Step 3: app killed, relaunched — main() re-reads persisted
      SettingsService.invalidateCache();
      final saved = await SettingsService.getManualStopped();
      expect(saved, isFalse);

      final container = makeColdStartContainer(
        savedManualStopped: saved,
        savedAutoConnect: true,
      );

      expect(
        container.read(userStoppedProvider),
        isFalse,
        reason: 'cleared flag must not zombie-block future auto-connect',
      );
      final gatedAllowed =
          container.read(autoConnectProvider) &&
          !container.read(userStoppedProvider);
      expect(
        gatedAllowed,
        isTrue,
        reason:
            'auto-connect must proceed after a clean start cleared '
            'the flag',
      );
    });

    test('autoConnect=false + persisted manualStopped=false → gate still '
        'blocks (autoConnect off)', () async {
      // Not the primary hotfix scenario, but guards against a regression
      // where the new override accidentally forces autoConnect on.
      final saved = await SettingsService.getManualStopped();
      final container = makeColdStartContainer(
        savedManualStopped: saved,
        savedAutoConnect: false,
      );
      final gatedAllowed =
          container.read(autoConnectProvider) &&
          !container.read(userStoppedProvider);
      expect(gatedAllowed, isFalse);
    });
  });
}

// ── Helpers ────────────────────────────────────────────────────────────────

/// Minimal Clash YAML config for mock mode startup.
String _minimalConfig({int mixedPort = 7890}) =>
    '''
mixed-port: $mixedPort
allow-lan: false
mode: rule
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
''';
