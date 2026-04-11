import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../domain/models/connection.dart';
import '../../../infrastructure/repositories/connection_repository.dart';
import '../../../core/providers/core_provider.dart';

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
    // Mock mode: poll the unified ClashCore interface (no REST API in mock).
    Future<void> poll() async {
      try {
        final data = await manager.core.getConnections();
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
  return ref.watch(
    connectionsSnapshotProvider.select((s) => s.connections.length),
  );
});

/// Cheap "is the connection list empty" — bool, only flips on transition.
/// Lets the page hide/show the empty state without watching the whole list.
final connectionsEmptyProvider = Provider<bool>((ref) {
  return ref.watch(
    connectionsSnapshotProvider.select((s) => s.connections.isEmpty),
  );
});

/// Per-tick totals (down/up bytes) — used by the summary bar without
/// needing to watch the whole connections list.
final connectionsTotalsProvider = Provider<({int down, int up})>((ref) {
  return ref.watch(
    connectionsSnapshotProvider.select(
      (s) => (down: s.downloadTotal, up: s.uploadTotal),
    ),
  );
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
// Per-proxy aggregated stats
// ------------------------------------------------------------------

class ProxyStats {
  final String proxyName;
  int connectionCount;
  int totalDownload;
  int totalUpload;

  ProxyStats({
    required this.proxyName,
    this.connectionCount = 0,
    this.totalDownload = 0,
    this.totalUpload = 0,
  });
}

/// Aggregate connection stats by the last proxy in the chain (the exit node).
final proxyStatsProvider = Provider<List<ProxyStats>>((ref) {
  final snapshot = ref.watch(connectionsSnapshotProvider);
  final statsMap = <String, ProxyStats>{};

  for (final conn in snapshot.connections) {
    // The last element in chains is the exit proxy
    final proxyName =
        conn.chains.isNotEmpty ? conn.chains.last : 'DIRECT';
    final stats = statsMap.putIfAbsent(
      proxyName,
      () => ProxyStats(proxyName: proxyName),
    );
    stats.connectionCount++;
    stats.totalDownload += conn.download;
    stats.totalUpload += conn.upload;
  }

  final result = statsMap.values.toList()
    ..sort((a, b) => b.totalDownload.compareTo(a.totalDownload));
  return result;
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
