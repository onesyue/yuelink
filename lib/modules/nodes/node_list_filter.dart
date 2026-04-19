import 'providers/nodes_providers.dart' show NodeSortMode;
import 'smart_score.dart';

/// Sort [nodes] according to [mode], then apply a case-insensitive
/// substring filter with [searchQuery]. Returns the input list by
/// reference when the operation is a no-op (default order + empty
/// query) so callers that key on identity can skip downstream work.
///
/// Extracted from the duplicate `_sortedNodes` + inline filter in
/// `widgets/group_card.dart` and `widgets/group_list_section.dart`.
/// Both call sites now go through here so sort semantics stay in one
/// place.
List<String> sortAndFilterNodes(
  List<String> nodes,
  NodeSortMode mode,
  Map<String, int> delays,
  String searchQuery,
) {
  final sorted = _sortNodes(nodes, mode, delays);
  final query = searchQuery.trim().toLowerCase();
  if (query.isEmpty) return sorted;
  return sorted.where((n) => n.toLowerCase().contains(query)).toList();
}

List<String> _sortNodes(
    List<String> nodes, NodeSortMode mode, Map<String, int> delays) {
  switch (mode) {
    case NodeSortMode.defaultOrder:
      return nodes;
    case NodeSortMode.nameAsc:
      final copy = List<String>.from(nodes)..sort();
      return copy;
    case NodeSortMode.latencyAsc:
      final copy = List<String>.from(nodes);
      copy.sort((a, b) {
        final da = delays[a];
        final db = delays[b];
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        if (da < 0 && db < 0) return 0;
        if (da < 0) return 1;
        if (db < 0) return -1;
        return da.compareTo(db);
      });
      return copy;
    case NodeSortMode.latencyDesc:
      final copy = List<String>.from(nodes);
      copy.sort((a, b) {
        final da = delays[a];
        final db = delays[b];
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        if (da < 0 && db < 0) return 0;
        if (da < 0) return 1;
        if (db < 0) return -1;
        return db.compareTo(da);
      });
      return copy;
    case NodeSortMode.smartRecommend:
      return sortBySmartScore(nodes, delays);
  }
}
