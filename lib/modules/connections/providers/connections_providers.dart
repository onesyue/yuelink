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

/// Latest connections snapshot (totals + per-connection list). Pushed by
/// the WebSocket stream wired up in [connectionsStreamProvider]; consumed
/// by widgets via `select(...)` so they only rebuild on the slice they
/// care about.
///
/// Riverpod 3.0: migrated from `StateProvider<ConnectionsSnapshot>`. All
/// writers live inside this file (the stream provider + closeAll), so
/// only the local callsites need the new [ConnectionsSnapshotNotifier.set]
/// method.
class ConnectionsSnapshotNotifier extends Notifier<ConnectionsSnapshot> {
  @override
  ConnectionsSnapshot build() => const ConnectionsSnapshot(
    connections: [],
    downloadTotal: 0,
    uploadTotal: 0,
  );

  /// Replace the current snapshot. Used by the polling/stream code paths.
  void set(ConnectionsSnapshot snapshot) => state = snapshot;
}

final connectionsSnapshotProvider =
    NotifierProvider<ConnectionsSnapshotNotifier, ConnectionsSnapshot>(
      ConnectionsSnapshotNotifier.new,
    );

final connectionsStreamProvider = Provider<void>((ref) {
  final status = ref.watch(coreStatusProvider);

  // Battery optimization: pause connections WebSocket when app is in background.
  final inBackground = ref.watch(appInBackgroundProvider);

  // Closure-local dispose flag. `timer.cancel()` / `sub.cancel()` only stop
  // NEW ticks; a callback already past its `await` (mock poll) or a
  // broadcast-stream event already queued (real listener) can still land
  // `ref.read(...).state = ...` on a disposed provider and throw. Every
  // callback below early-returns on this flag.
  bool disposed = false;
  ref.onDispose(() => disposed = true);

  if (status != CoreStatus.running || inBackground) {
    // Defer state writes to after this provider's build phase — Riverpod
    // forbids modifying other providers synchronously during initialization.
    Future.microtask(() {
      if (disposed) return;
      ref
          .read(connectionsSnapshotProvider.notifier)
          .set(
            const ConnectionsSnapshot(
              connections: [],
              downloadTotal: 0,
              uploadTotal: 0,
            ),
          );
      ref.read(connectionSearchProvider.notifier).setQuery('');
    });
    return;
  }

  final manager = CoreManager.instance;

  if (manager.isMockMode) {
    // Mock mode: poll the unified ClashCore interface (no REST API in mock).
    Future<void> poll() async {
      try {
        final data = await manager.core.getConnections();
        if (disposed) return;
        final snapshot = ConnectionsSnapshot.fromJson(data);
        ref.read(connectionsSnapshotProvider.notifier).set(snapshot);
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
    if (disposed) return;
    ref.read(connectionsSnapshotProvider.notifier).set(snap);
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

/// Free-text search query for the connections page. Bound to a
/// [TextEditingController]; debounced upstream so we don't rebuild the
/// filter list on every keystroke.
///
/// Riverpod 3.0: migrated from `StateProvider<String>`. Public
/// [ConnectionSearchNotifier.setQuery] keeps writes explicit and grep-able.
class ConnectionSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// Update the current search query. Treats null as empty.
  void setQuery(String query) => state = query;
}

final connectionSearchProvider =
    NotifierProvider<ConnectionSearchNotifier, String>(
      ConnectionSearchNotifier.new,
    );

final filteredConnectionsProvider = Provider<List<ActiveConnection>>((ref) {
  // Watch only the connections list, not the whole snapshot — we don't
  // care about totals here, and the Provider subscribers shouldn't
  // re-enter this body when only the totals tick.
  final connections = ref.watch(
    connectionsSnapshotProvider.select((s) => s.connections),
  );
  final query = ref.watch(connectionSearchProvider).toLowerCase().trim();

  if (query.isEmpty) return connections;

  return connections.where((c) {
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
///
/// Only the top [_proxyStatsLimit] proxies (by total download) are returned —
/// that's all the UI ever renders in [ProxyStatsBar]. Capping here avoids
/// the consumer's `.take().toList()` re-allocation and keeps the provider's
/// output size bounded even when connections are spread across many exits.
final proxyStatsProvider = Provider<List<ProxyStats>>((ref) {
  final connections = ref.watch(
    connectionsSnapshotProvider.select((s) => s.connections),
  );
  final statsMap = <String, ProxyStats>{};

  for (final conn in connections) {
    // The last element in chains is the exit proxy
    final proxyName = conn.chains.isNotEmpty ? conn.chains.last : 'DIRECT';
    final stats = statsMap.putIfAbsent(
      proxyName,
      () => ProxyStats(proxyName: proxyName),
    );
    stats.connectionCount++;
    stats.totalDownload += conn.download;
    stats.totalUpload += conn.upload;
  }

  final sorted = statsMap.values.toList()
    ..sort((a, b) => b.totalDownload.compareTo(a.totalDownload));
  if (sorted.length <= _proxyStatsLimit) return sorted;
  return sorted.sublist(0, _proxyStatsLimit);
});

const _proxyStatsLimit = 5;

// ------------------------------------------------------------------
// Connection actions
// ------------------------------------------------------------------

final connectionActionsProvider = Provider<ConnectionActions>(
  (ref) => ConnectionActions(ref),
);

class ConnectionActions {
  final Ref ref;
  ConnectionActions(this.ref);

  Future<bool> close(String id) async {
    final ok = await ref.read(connectionRepositoryProvider).closeConnection(id);
    return ok;
  }

  Future<bool> closeAll() async {
    final ok = await ref
        .read(connectionRepositoryProvider)
        .closeAllConnections();
    if (ok) {
      ref
          .read(connectionsSnapshotProvider.notifier)
          .set(
            const ConnectionsSnapshot(
              connections: [],
              downloadTotal: 0,
              uploadTotal: 0,
            ),
          );
    }
    return ok;
  }
}
