import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yuelink/core/kernel/core_manager.dart';
import 'package:yuelink/core/ffi/core_controller.dart';

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
    expect(cm.isMockMode, isTrue,
        reason: 'Tests must run in mock mode (no native library)');
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
        expect(step.success, true,
            reason: '${step.name} should succeed in mock mode');
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
}

// ── Helpers ────────────────────────────────────────────────────────────────

/// Minimal Clash YAML config for mock mode startup.
String _minimalConfig({int mixedPort = 7890}) => '''
mixed-port: $mixedPort
allow-lan: false
mode: rule
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
''';
