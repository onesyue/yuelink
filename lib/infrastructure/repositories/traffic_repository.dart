import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datasources/mihomo_stream.dart';
import '../../domain/models/traffic.dart';
import '../../domain/models/traffic_history.dart';
import '../../core/kernel/core_manager.dart';

/// Repository that wraps real-time traffic/memory streams from [MihomoStream].
///
/// Provides three streams:
/// - [trafficStream] — raw 1 s traffic ticks.
/// - [memoryStream] — memory usage throttled to 5 s windows.
/// - [historyStream] — accumulates ticks into a [TrafficHistory] ring buffer
///   and emits an updated copy every tick.
class TrafficRepository {
  TrafficRepository(this._stream);

  final MihomoStream _stream;

  // ------------------------------------------------------------------
  // Traffic stream — raw 1 s ticks
  // ------------------------------------------------------------------

  Stream<Traffic> trafficStream() {
    return _stream.trafficStream().map((t) => Traffic(up: t.up, down: t.down));
  }

  // ------------------------------------------------------------------
  // Memory stream — 5 s throttle
  // ------------------------------------------------------------------

  Stream<int> memoryStream() {
    int? pending;
    Timer? throttle;

    late StreamController<int> controller;
    StreamSubscription<int>? sub;

    controller = StreamController<int>.broadcast(
      onListen: () {
        sub = _stream.memoryStream().listen((bytes) {
          pending = bytes;
          throttle ??= Timer(const Duration(seconds: 5), () {
            final v = pending;
            if (v != null && !controller.isClosed) controller.add(v);
            pending = null;
            throttle = null;
          });
        });
      },
      onCancel: () {
        sub?.cancel();
        throttle?.cancel();
        sub = null;
        throttle = null;
      },
    );

    return controller.stream;
  }

  // ------------------------------------------------------------------
  // History stream — accumulates ticks into a ring buffer
  // ------------------------------------------------------------------

  Stream<TrafficHistory> historyStream() {
    final history = TrafficHistory();

    late StreamController<TrafficHistory> controller;
    StreamSubscription<({int up, int down})>? sub;

    controller = StreamController<TrafficHistory>.broadcast(
      onListen: () {
        sub = _stream.trafficStream().listen((t) {
          history.add(t.up, t.down);
          if (!controller.isClosed) controller.add(history.copy());
        });
      },
      onCancel: () {
        sub?.cancel();
        sub = null;
      },
    );

    return controller.stream;
  }
}

final trafficRepositoryProvider = Provider<TrafficRepository>((ref) {
  final stream = CoreManager.instance.stream;
  return TrafficRepository(stream);
});
