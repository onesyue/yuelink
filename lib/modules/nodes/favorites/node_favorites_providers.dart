import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'node_favorites_service.dart';

export 'node_favorites_service.dart' show RecentNode;

// ── Toggle: show only favorited nodes ────────────────────────────────────────

final showFavoritesOnlyProvider = StateProvider<bool>((ref) => false);

// ── Favorites ─────────────────────────────────────────────────────────────────

final favoritesProvider =
    NotifierProvider<FavoritesNotifier, Set<String>>(FavoritesNotifier.new);

class FavoritesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    Future.microtask(_load);
    return {};
  }

  Future<void> _load() async {
    state = await NodeFavoritesService.getFavorites();
  }

  Future<void> toggle(String nodeName) async {
    final updated = Set<String>.from(state);
    if (updated.contains(nodeName)) {
      updated.remove(nodeName);
    } else {
      updated.add(nodeName);
    }
    state = updated; // optimistic update
    await NodeFavoritesService.saveFavorites(updated);
  }
}

/// Granular family provider so each NodeTile/NodeCardItem only rebuilds
/// when its own favorite status changes — not when any other node changes.
final nodeIsFavoriteProvider = Provider.family<bool, String>((ref, name) {
  return ref.watch(favoritesProvider.select((favs) => favs.contains(name)));
});

/// Granular family provider: true when [name] is in the recent-nodes list.
/// Uses .select() so only the tile for this specific node rebuilds on change.
final nodeIsRecentProvider = Provider.family<bool, String>((ref, name) {
  return ref.watch(
    recentNodesProvider.select((list) => list.any((n) => n.name == name)),
  );
});

// ── Recent nodes ──────────────────────────────────────────────────────────────

final recentNodesProvider =
    NotifierProvider<RecentNodesNotifier, List<RecentNode>>(
        RecentNodesNotifier.new);

class RecentNodesNotifier extends Notifier<List<RecentNode>> {
  @override
  List<RecentNode> build() {
    Future.microtask(_load);
    return [];
  }

  Future<void> _load() async {
    state = await NodeFavoritesService.getRecent();
  }

  /// Records [name]/[group] as the most-recently-used node.
  /// Deduplicates and trims to 5 entries.
  Future<void> record(String name, String group) async {
    final list = List<RecentNode>.from(state);
    list.removeWhere((n) => n.name == name && n.group == group);
    list.insert(0, RecentNode(name: name, group: group));
    if (list.length > 5) list.removeRange(5, list.length);
    state = list; // optimistic update
    await NodeFavoritesService.saveRecent(list);
  }
}
