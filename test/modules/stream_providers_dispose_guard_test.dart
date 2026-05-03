import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/kernel/core_manager.dart';
import 'package:yuelink/core/providers/core_provider.dart';
import 'package:yuelink/modules/dashboard/providers/traffic_providers.dart';
import 'package:yuelink/domain/models/connection.dart';
import 'package:yuelink/domain/models/traffic.dart';
import 'package:yuelink/infrastructure/repositories/connection_repository.dart';
import 'package:yuelink/infrastructure/repositories/traffic_repository.dart';
import 'package:yuelink/modules/connections/providers/connections_providers.dart';

/// Regression guards for P0-B final pair: connections + traffic stream
/// providers. Each stream subscriber wrote `ref.read(...).state = ...`
/// without any dispose check; `sub.cancel()` alone can't stop a broadcast
/// event that was already queued for dispatch right before the provider
/// tore down, nor a mock-timer tick whose async callback was past its
/// await. Closure-local `disposed` flags now gate every state write.

class _FakeConnectionRepo implements ConnectionRepository {
  _FakeConnectionRepo(this._stream);
  final Stream<ConnectionsSnapshot> _stream;

  @override
  Stream<ConnectionsSnapshot> connectionsStream() => _stream;

  @override
  Future<bool> closeConnection(String id) async => true;

  @override
  Future<bool> closeAllConnections() async => true;
}

class _FakeTrafficRepo implements TrafficRepository {
  _FakeTrafficRepo({required Stream<Traffic> traffic, Stream<int>? memory})
    : _traffic = traffic,
      _memory = memory;

  final Stream<Traffic> _traffic;
  final Stream<int>? _memory;

  @override
  Stream<Traffic> trafficStream() => _traffic;

  @override
  Stream<int> memoryStream() => _memory ?? const Stream<int>.empty();
}

bool _isDisposeError(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('disposed') ||
      s.contains('cannot use state') ||
      s.contains('after it was disposed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    // Some deep dependencies (MihomoApi constructor, etc.) read
    // path_provider even when we hand them a fake repo. Point it at a
    // tempdir so no request escapes to the host filesystem.
    tempDir = Directory.systemTemp.createTempSync('yuelink_stream_guard_');
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
    // Put CoreManager in non-mock mode so connectionsStreamProvider /
    // trafficStreamProvider take the repository-stream branch (the branch
    // our fakes can inject into). resetForTesting + configure(ffi) keeps
    // the singleton honest across tests.
    CoreManager.resetForTesting();
    CoreManager.instance.configure(mode: CoreMode.ffi);
  });

  tearDown(() {
    CoreManager.resetForTesting();
  });

  // ── case A: connections stream listener after dispose ──────────────
  test('connections listener after dispose does not write state', () async {
    final controller = StreamController<ConnectionsSnapshot>.broadcast();
    final errors = <Object>[];

    await runZonedGuarded<Future<void>>(() async {
      final container = ProviderContainer(
        overrides: [
          connectionRepositoryProvider.overrideWithValue(
            _FakeConnectionRepo(controller.stream),
          ),
        ],
      );

      // coreStatus = running + foreground (default) to take the listener path
      container.read(coreStatusProvider.notifier).set(CoreStatus.running);

      // Activate provider → sub.listen attached
      container.read(connectionsStreamProvider);

      // Let the subscription mount
      await Future<void>.delayed(Duration.zero);

      // Dispose synchronously — disposed=true, sub.cancel queued
      container.dispose();

      // Emit a late event. Broadcast semantics may still dispatch to a
      // just-cancelled subscriber's pending microtask on some Dart versions;
      // the closure-local `disposed` guard must short-circuit the state
      // write regardless.
      controller.add(
        const ConnectionsSnapshot(
          connections: [],
          downloadTotal: 0,
          uploadTotal: 0,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
    }, (err, _) => errors.add(err));

    await controller.close();

    final bad = errors.where(_isDisposeError).toList();
    expect(
      bad,
      isEmpty,
      reason: 'connections listener must guard against dispose; got: $bad',
    );
  });

  // ── case B: traffic stream listener after dispose ──────────────────
  test('traffic listener after dispose does not write state', () async {
    final trafficCtl = StreamController<Traffic>.broadcast();
    final errors = <Object>[];

    await runZonedGuarded<Future<void>>(() async {
      final container = ProviderContainer(
        overrides: [
          trafficRepositoryProvider.overrideWithValue(
            _FakeTrafficRepo(traffic: trafficCtl.stream),
          ),
        ],
      );

      container.read(coreStatusProvider.notifier).set(CoreStatus.running);

      // Activate provider — wires traffic listener + memory listener
      container.read(trafficStreamProvider);

      await Future<void>.delayed(Duration.zero);

      container.dispose();

      // Late traffic tick — listener must not touch state
      trafficCtl.add(const Traffic(up: 1234, down: 5678));

      await Future<void>.delayed(const Duration(milliseconds: 30));
    }, (err, _) => errors.add(err));

    await trafficCtl.close();

    final bad = errors.where(_isDisposeError).toList();
    expect(
      bad,
      isEmpty,
      reason: 'traffic listener must guard against dispose; got: $bad',
    );
  });
}
