import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/proxy.dart';
import '../../../i18n/app_strings.dart';
import '../group_type_label.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';
import '../node_list_filter.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final testing = ref.watch(delayTestingProvider);
    final isGroupTesting = testing.any((n) => group.all.contains(n));
    // Read delays for sort order only; NodeTile handles per-node rendering.
    // Skip watching when sort is default — avoids rebuilding 1000 tiles
    // every time any node's delay test completes.
    final delays = sortMode == NodeSortMode.defaultOrder
        ? const <String, int>{}
        : ref.watch(delayResultsProvider);
    final nodeList =
        sortAndFilterNodes(group.all, sortMode, delays, searchQuery);
    final isFiltered = searchQuery.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
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
                // See GroupCard for the rationale on ConstrainedBox vs
                // Flexible here: Flexible + Expanded both claim flex=1 and
                // split the residual Row width, opening a visible gap when
                // the selection label is short. ConstrainedBox keeps the
                // badge + count + lightning flush-right without that gap.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: _Badge(
                    label: groupSelectionLabel(context, group),
                    isDark: isDark,
                  ),
                ),
                if (sortMode == NodeSortMode.smartRecommend) ...[
                  const SizedBox(width: 4),
                  _Badge(
                    label: S.of(context).sortDefault == 'Default'
                        ? 'Smart'
                        : '推荐',
                    isDark: isDark,
                    accent: true,
                  ),
                ],
                const SizedBox(width: 4),
                _Badge(
                  label: isFiltered
                      ? '${nodeList.length}/${group.all.length}'
                      : '${group.all.length}',
                  isDark: isDark,
                  accent: isFiltered,
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: isGroupTesting
                      ? null
                      : () {
                          ref
                              .read(delayTestProvider)
                              .testGroup(group.name, group.all);
                          AppNotifier.info(
                              S.of(context).testingGroup(group.name));
                        },
                  icon: isGroupTesting
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: YLText.caption.copyWith(
          fontSize: 10,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
