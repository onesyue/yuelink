import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/proxy.dart';
import '../../../l10n/app_strings.dart';
import '../group_type_label.dart';
import '../../../shared/app_notifier.dart';
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
    final testing = ref.watch(delayTestingProvider);
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
                Expanded(
                  child: Text(
                    group.name,
                    style: YLText.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: YLSpacing.sm),
                _Badge(label: groupTypeLabel(context, group.type), isDark: isDark),
                const SizedBox(width: YLSpacing.sm),
                _Badge(
                  label: isFiltered
                      ? '${nodeList.length}/${group.all.length}'
                      : '${group.all.length}',
                  isDark: isDark,
                  accent: isFiltered,
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: testing.isNotEmpty
                      ? null
                      : () {
                          ref
                              .read(delayTestProvider)
                              .testGroup(group.name, group.all);
                          AppNotifier.info(
                              S.of(context).testingGroup(group.name));
                        },
                  icon: testing.isNotEmpty
                      ? const CupertinoActivityIndicator(radius: 7)
                      : const Icon(Icons.bolt_rounded),
                  iconSize: 18,
                  color: isDark ? Colors.white : YLColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 0.5),
          // Flat node list — each NodeTile manages its own state.
          // Wrap each tile in RepaintBoundary to isolate repaints.
          Column(
            children: List.generate(nodeList.length, (i) {
              final nodeName = nodeList[i];
              return RepaintBoundary(
                child: Column(
                  children: [
                    NodeTile(
                      name: nodeName,
                      groupName: group.name,
                    ),
                    if (i < nodeList.length - 1)
                      const Divider(height: 1, indent: 48),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final bool isDark;
  final bool accent;
  const _Badge({required this.label, required this.isDark, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final bg = accent
        ? YLColors.connected.withValues(alpha: 0.12)
        : (isDark ? YLColors.zinc700 : YLColors.zinc100);
    final fg = accent ? YLColors.connected : YLColors.zinc500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Text(
        label,
        style: YLText.caption.copyWith(
          fontSize: 10,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
