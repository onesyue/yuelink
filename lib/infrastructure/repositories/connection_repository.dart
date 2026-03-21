import 'dart:async';

import 'package:flutter/foundation.dart';
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
  ///
  /// Performance: raw JSON is stored and only parsed when the throttle timer
  /// fires — intermediate frames are discarded without parsing.
  Stream<ConnectionsSnapshot> connectionsStream() {
    Map<String, dynamic>? pendingRaw;
    Timer? throttle;

    late StreamController<ConnectionsSnapshot> controller;
    StreamSubscription<Map<String, dynamic>>? sub;

    controller = StreamController<ConnectionsSnapshot>.broadcast(
      onListen: () {
        sub = _stream.connectionsStream().listen((data) {
          // Store raw JSON — defer expensive fromJson until throttle fires
          pendingRaw = data;
          throttle ??= Timer(const Duration(milliseconds: 500), () {
            final raw = pendingRaw;
            if (raw != null && !controller.isClosed) {
              try {
                controller.add(ConnectionsSnapshot.fromJson(raw));
              } catch (e) {
                debugPrint('[ConnectionRepo] parse snapshot failed: $e');
              }
              pendingRaw = null;
            }
            throttle = null;
          });
        });
      },
      onCancel: () {
        sub?.cancel();
        throttle?.cancel();
        sub = null;
        throttle = null;
        pendingRaw = null;
        controller.close();
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
