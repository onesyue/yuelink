import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datasources/mihomo_api.dart';
import '../datasources/mihomo_stream.dart';
import '../../domain/models/connection.dart';
import '../../core/kernel/core_manager.dart';
import '../../providers/core_provider.dart';

/// Repository that wraps connection-related data operations.
///
/// Exposes a throttled [connectionsStream] (500 ms window) and close actions
/// that delegate to [MihomoApi].
class ConnectionRepository {
  ConnectionRepository(this._api, this._stream);

  final MihomoApi _api;
  final MihomoStream _stream;

  /// Broadcast stream of [ConnectionsSnapshot] with a 500 ms throttle.
  ///
  /// Throttling prevents UI overload when hundreds of connections change per
  /// second (e.g. BitTorrent downloads).
  Stream<ConnectionsSnapshot> connectionsStream() {
    ConnectionsSnapshot? pending;
    Timer? throttle;

    late StreamController<ConnectionsSnapshot> controller;
    StreamSubscription<Map<String, dynamic>>? sub;

    controller = StreamController<ConnectionsSnapshot>.broadcast(
      onListen: () {
        sub = _stream.connectionsStream().listen((data) {
          try {
            pending = ConnectionsSnapshot.fromJson(data);
            throttle ??= Timer(const Duration(milliseconds: 500), () {
              final snap = pending;
              if (snap != null) {
                if (!controller.isClosed) controller.add(snap);
                pending = null;
              }
              throttle = null;
            });
          } catch (_) {}
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

  Future<bool> closeConnection(String id) => _api.closeConnection(id);

  Future<bool> closeAllConnections() => _api.closeAllConnections();
}

final connectionRepositoryProvider = Provider<ConnectionRepository>((ref) {
  final api = ref.watch(mihomoApiProvider);
  final stream = CoreManager.instance.stream;
  return ConnectionRepository(api, stream);
});
