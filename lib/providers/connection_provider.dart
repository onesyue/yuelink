import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection.dart';
import '../services/core_manager.dart';
import 'core_provider.dart';

// ------------------------------------------------------------------
// Connections snapshot (polled every second via WebSocket stream)
// ------------------------------------------------------------------

final connectionsSnapshotProvider =
    StateProvider<ConnectionsSnapshot>((ref) => const ConnectionsSnapshot(
          connections: [],
          downloadTotal: 0,
          uploadTotal: 0,
        ));

final connectionsStreamProvider = Provider<void>((ref) {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) {
    // Clear on disconnect
    ref.read(connectionsSnapshotProvider.notifier).state =
        const ConnectionsSnapshot(
            connections: [], downloadTotal: 0, uploadTotal: 0);
    return;
  }

  final manager = CoreManager.instance;
  if (manager.isMockMode) return;

  final sub = manager.stream.connectionsStream().listen((data) {
    try {
      final snapshot = ConnectionsSnapshot.fromJson(data);
      ref.read(connectionsSnapshotProvider.notifier).state = snapshot;
    } catch (_) {}
  });
  ref.onDispose(() => sub.cancel());
});

// ------------------------------------------------------------------
// Connection filter / search
// ------------------------------------------------------------------

final connectionSearchProvider = StateProvider<String>((ref) => '');

final filteredConnectionsProvider =
    Provider<List<ActiveConnection>>((ref) {
  final snapshot = ref.watch(connectionsSnapshotProvider);
  final query = ref.watch(connectionSearchProvider).toLowerCase().trim();

  if (query.isEmpty) return snapshot.connections;

  return snapshot.connections.where((c) {
    return c.target.toLowerCase().contains(query) ||
        c.processName.toLowerCase().contains(query) ||
        c.rule.toLowerCase().contains(query) ||
        c.chains.any((ch) => ch.toLowerCase().contains(query));
  }).toList();
});

// ------------------------------------------------------------------
// Connection actions
// ------------------------------------------------------------------

final connectionActionsProvider =
    Provider<ConnectionActions>((ref) => ConnectionActions(ref));

class ConnectionActions {
  final Ref ref;
  ConnectionActions(this.ref);

  Future<bool> close(String id) async {
    final ok = await CoreManager.instance.api.closeConnection(id);
    return ok;
  }

  Future<bool> closeAll() async {
    final ok = await CoreManager.instance.api.closeAllConnections();
    if (ok) {
      ref.read(connectionsSnapshotProvider.notifier).state =
          const ConnectionsSnapshot(
              connections: [], downloadTotal: 0, uploadTotal: 0);
    }
    return ok;
  }
}
