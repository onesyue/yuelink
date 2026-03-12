import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/proxy.dart';
import '../../../l10n/app_strings.dart';
import '../../../theme.dart';
import '../providers/nodes_providers.dart';
import 'node_tile.dart';

/// Flat list view of a proxy group (non-expandable, always visible nodes).
///
/// Like [GroupCard], this widget does NOT watch [delayResultsProvider] for
/// rendering — each [NodeTile] does that independently.
class GroupListSection extends ConsumerWidget {
  const GroupListSection({
    super.key,
    required this.group,
    this.sortMode = NodeSortMode.defaultOrder,
    this.searchQuery = '',
  });

  final ProxyGroup group;
  final NodeSortMode sortMode;
  final String searchQuery;

  List<String> _sortedNodes(
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
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Read delays for sort order only; NodeTile handles rendering.
    final delays = ref.read(delayResultsProvider);
    final sorted = _sortedNodes(group.all, sortMode, delays);
    final query = searchQuery.trim().toLowerCase();
    final nodeList = query.isEmpty
        ? sorted
        : sorted.where((n) => n.toLowerCase().contains(query)).toList();
    final isFiltered = query.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header (non-expandable)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: YLSpacing.md, vertical: YLSpacing.sm),
            child: Row(
              children: [
                Text(group.name, style: YLText.titleMedium),
                const SizedBox(width: YLSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? YLColors.zinc800 : YLColors.zinc100,
                    borderRadius: BorderRadius.circular(YLRadius.sm),
                  ),
                  child: Text(
                    group.type,
                    style: YLText.caption.copyWith(
                        fontSize: 10,
                        color: YLColors.zinc500,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                Text(
                  isFiltered
                      ? '${nodeList.length}/${group.all.length}'
                      : S.of(context).nodesCountLabel(nodeList.length),
                  style: YLText.caption.copyWith(
                    color:
                        isFiltered ? YLColors.connected : YLColors.zinc500,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 0.5),
          // Flat node list — each NodeTile manages its own state.
          Column(
            children: List.generate(nodeList.length, (i) {
              final nodeName = nodeList[i];
              return Column(
                children: [
                  NodeTile(
                    name: nodeName,
                    groupName: group.name,
                  ),
                  if (i < nodeList.length - 1)
                    const Divider(height: 1, indent: 48),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
