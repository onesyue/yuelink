import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/core_mock.dart';
import '../../../domain/models/connection.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../infrastructure/repositories/connection_repository.dart';
import '../../../providers/core_provider.dart';

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

  // Battery optimization: pause connections WebSocket when app is in background.
  final inBackground = ref.watch(appInBackgroundProvider);

  if (status != CoreStatus.running || inBackground) {
    // Defer state writes to after this provider's build phase — Riverpod
    // forbids modifying other providers synchronously during initialization.
    Future.microtask(() {
      ref.read(connectionsSnapshotProvider.notifier).state =
          const ConnectionsSnapshot(
              connections: [], downloadTotal: 0, uploadTotal: 0);
      ref.read(connectionSearchProvider.notifier).state = '';
    });
    return;
  }

  final manager = CoreManager.instance;

  if (manager.isMockMode) {
    // Mock mode: use CoreMock data directly (no REST API in mock mode)
    Future<void> poll() async {
      try {
        final data = CoreMock.instance.getConnections();
        final snapshot = ConnectionsSnapshot.fromJson(data);
        ref.read(connectionsSnapshotProvider.notifier).state = snapshot;
      } catch (e) {
        debugPrint('[Connections] mock poll failed: $e');
      }
    }

    poll();
    final timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
    ref.onDispose(() => timer.cancel());
    return;
  }

  // Real mode: use ConnectionRepository's throttled stream
  final repo = ref.watch(connectionRepositoryProvider);
  final sub = repo.connectionsStream().listen((snap) {
    ref.read(connectionsSnapshotProvider.notifier).state = snap;
  });
  ref.onDispose(() => sub.cancel());
});

// Derived count — cheap int comparison avoids rebuilds on every connection update
final connectionCountProvider = Provider<int>((ref) {
  return ref.watch(connectionsSnapshotProvider).connections.length;
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
    final ok =
        await ref.read(connectionRepositoryProvider).closeConnection(id);
    return ok;
  }

  Future<bool> closeAll() async {
    final ok =
        await ref.read(connectionRepositoryProvider).closeAllConnections();
    if (ok) {
      ref.read(connectionsSnapshotProvider.notifier).state =
          const ConnectionsSnapshot(
              connections: [], downloadTotal: 0, uploadTotal: 0);
    }
    return ok;
  }
}
