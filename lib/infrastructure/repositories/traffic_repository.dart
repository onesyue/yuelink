import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datasources/mihomo_stream.dart';
import '../../domain/models/traffic.dart';
import '../../core/kernel/core_manager.dart';

/// Repository that wraps real-time traffic/memory streams from [MihomoStream].
///
/// Provides two streams:
/// - [trafficStream] — raw 1 s traffic ticks.
/// - [memoryStream] — memory usage throttled to 5 s windows.
///
/// Traffic history accumulation is handled by [trafficStreamProvider] using
/// in-place mutation + version counter (no per-tick copy).
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
        controller.close();
      },
    );

    return controller.stream;
  }
}

final trafficRepositoryProvider = Provider<TrafficRepository>((ref) {
  final stream = CoreManager.instance.stream;
  return TrafficRepository(stream);
});
