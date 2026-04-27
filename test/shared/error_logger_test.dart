import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/error_logger.dart';
import 'package:yuelink/shared/telemetry.dart';

/// Regression guards for ErrorLogger telemetry dedup.
///
/// One exception can reach [_capture] from multiple handlers (FlutterError /
/// PlatformDispatcher / runZonedGuarded / manual captureException) but the
/// telemetry pipeline should see it at most once per [_dedupTtl] window.
/// The local crash.log, EventLog, and remote reporter are expected to keep
/// every write — only the Telemetry.event emission is gated.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    // Telemetry.setEnabled + write paths inside ErrorLogger touch
    // path_provider. Point everything at a throwaway tempdir so nothing
    // escapes to the host filesystem.
    tempDir = Directory.systemTemp.createTempSync('yuelink_err_logger_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    // Clean dedup window per test; turn telemetry ON so emissions land in
    // Telemetry.recentEvents() where we can observe them.
    ErrorLogger.debugResetDedup();
    Telemetry.setEnabled(true);
  });

  tearDown(() {
    Telemetry.setEnabled(false);
    ErrorLogger.debugResetDedup();
  });

  // Count only crash / networkError events — session_start and other
  // Telemetry.event callers are irrelevant to dedup behaviour.
  int crashCount() => Telemetry.recentEvents()
      .where(
        (e) =>
            e['event'] == TelemetryEvents.crash ||
            e['event'] == TelemetryEvents.networkError,
      )
      .length;

  group('ErrorLogger telemetry dedup', () {
    test('same error + same stack within TTL → one telemetry event', () {
      final error = StateError('widget build failed');
      final stack = StackTrace.fromString(
        '#0      _MyWidget.build (package:app/widget.dart:42:7)\n'
        '#1      StatelessWidget.createElement (package:flutter/src/widgets/framework.dart:1:1)\n'
        '#2      Element.mount (package:flutter/src/widgets/framework.dart:1:1)',
      );
      final before = crashCount();

      ErrorLogger.captureException(error, stack, source: 'FlutterError');
      ErrorLogger.captureException(error, stack, source: 'Zone');

      expect(
        crashCount() - before,
        1,
        reason: 'both handlers observed the same exception — one event only',
      );
    });

    test('source differs but error+stack same → still deduped', () {
      // Fingerprint intentionally excludes source so a FlutterError + Zone
      // + PlatformDispatcher triad on one exception collapses to a single
      // telemetry row.
      final error = StateError('same state');
      final stack = StackTrace.fromString(
        '#0      frame0\n#1      frame1\n#2      frame2',
      );
      final before = crashCount();

      ErrorLogger.captureException(error, stack, source: 'FlutterError');
      ErrorLogger.captureException(error, stack, source: 'PlatformDispatcher');
      ErrorLogger.captureException(error, stack, source: 'Zone');

      expect(crashCount() - before, 1);
    });

    test('different stack → not deduped', () {
      final error = StateError('widget build failed');
      final stackA = StackTrace.fromString(
        '#0      _MyWidget.build (package:app/widget.dart:42:7)\n'
        '#1      StatelessWidget.createElement\n'
        '#2      Element.mount',
      );
      final stackB = StackTrace.fromString(
        '#0      _OtherWidget.build (package:app/other.dart:7:9)\n'
        '#1      StatelessWidget.createElement\n'
        '#2      Element.mount',
      );
      final before = crashCount();

      ErrorLogger.captureException(error, stackA, source: 'X');
      ErrorLogger.captureException(error, stackB, source: 'X');

      expect(
        crashCount() - before,
        2,
        reason: 'distinct call sites must not be collapsed',
      );
    });

    test('different error string → not deduped', () {
      final stack = StackTrace.fromString(
        '#0      foo (package:app/a.dart:1:1)\n'
        '#1      bar (package:app/b.dart:1:1)\n'
        '#2      baz (package:app/c.dart:1:1)',
      );
      final before = crashCount();

      ErrorLogger.captureException(StateError('a'), stack, source: 'X');
      ErrorLogger.captureException(StateError('b'), stack, source: 'X');

      expect(
        crashCount() - before,
        2,
        reason: 'distinct error strings must not be collapsed',
      );
    });

    test('network-type and crash-type share the same dedup window', () {
      // A SocketException + same stack emitted twice should only count
      // once (as networkError), confirming the gate covers both buckets.
      const error = SocketException('connection refused');
      final stack = StackTrace.fromString(
        '#0      connect (package:app/net.dart:1:1)\n'
        '#1      dial (package:app/net.dart:2:1)\n'
        '#2      fetch (package:app/client.dart:3:1)',
      );
      final before = crashCount();

      ErrorLogger.captureException(error, stack, source: 'X');
      ErrorLogger.captureException(error, stack, source: 'Y');

      expect(crashCount() - before, 1);
    });
  });
}
