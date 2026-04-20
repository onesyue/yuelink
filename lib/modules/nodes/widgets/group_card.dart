import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/settings_service.dart';
import '../../../domain/models/proxy.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';
import '../group_type_label.dart';
import '../../chain_proxy/chain_proxy_provider.dart';
import '../node_list_filter.dart';
import '../protocol_color.dart';
import '../providers/node_providers.dart';
import '../providers/nodes_providers.dart';
import '../favorites/node_favorites_providers.dart';

/// Expandable proxy group card.
///
/// In card mode nodes are shown in a responsive Wrap grid using [NodeCardItem].
/// Groups start EXPANDED by default; click the header to collapse/expand.
/// Each [NodeCardItem] watches its own per-node providers so only the affected
/// card rebuilds on delay or selection changes.
class GroupCard extends ConsumerStatefulWidget {
  const GroupCard({
    super.key,
    required this.group,
    this.sortMode = NodeSortMode.defaultOrder,
    this.searchQuery = '',
  });

  final ProxyGroup group;
  final NodeSortMode sortMode;
  final String searchQuery;

  @override
  ConsumerState<GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<GroupCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool _showAll = false; // For large groups: show all nodes or capped
  late AnimationController _animController;
  late Animation<double> _expandAnim;
  late Animation<double> _chevronAnim;

  @override
  void initState() {
    super.initState();
    // Restore persisted expansion state
    final expandedGroups = ref.read(expandedGroupNamesProvider);
    _expanded = expandedGroups.contains(widget.group.name);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: _expanded ? 1.0 : 0.0,
    );
    _expandAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _chevronAnim = Tween<double>(begin: 0, end: 0.5).animate(_expandAnim);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (!_expanded) _showAll = false; // Reset cap when collapsing
    });
    if (_expanded) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
    // Persist expansion state
    final current = Set<String>.from(ref.read(expandedGroupNamesProvider));
    if (_expanded) {
      current.add(widget.group.name);
    } else {
      current.remove(widget.group.name);
    }
    ref.read(expandedGroupNamesProvider.notifier).state = current;
    SettingsService.setExpandedGroups(current.toList());
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Only rebuild when testing state for THIS group's nodes changes
    final isGroupTesting = ref.watch(delayTestingProvider.select(
        (set) => set.any((n) => group.all.contains(n))));
    // Only rebuild when sort-relevant delays change (not every single node update)
    final sortMode = widget.sortMode;
    final delays = sortMode == NodeSortMode.defaultOrder
        ? const <String, int>{}
        : ref.watch(delayResultsProvider);
    // Pipe-in a 推荐 header when the Smart Recommend mode is active.
    // Matches the type-badge pill visual style (same _Badge widget).
    final showSmartHeader = sortMode == NodeSortMode.smartRecommend;
    final nodeList = sortAndFilterNodes(
        group.all, sortMode, delays, widget.searchQuery);
    final isFiltered = widget.searchQuery.trim().isNotEmpty;

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
          // ── Header (tap to toggle, long-press to add group to chain) ──
          InkWell(
            onTap: _toggle,
            onLongPress: () {
              ref.read(chainProxyProvider.notifier).addNode(group.name);
              AppNotifier.info(S.of(context).chainAddHint);
            },
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(YLRadius.xl),
              bottom: _expanded
                  ? Radius.zero
                  : const Radius.circular(YLRadius.xl),
            ),
            child: Padding(
              padding: const EdgeInsets.all(YLSpacing.md),
              child: Row(
                children: [
                  RotationTransition(
                    turns: _chevronAnim,
                    child: const Icon(Icons.expand_more_rounded,
                        size: 20, color: YLColors.zinc400),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                  Expanded(
                    child: Text(
                      group.name,
                      style: YLText.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                  // Selection badge — shows the currently selected node for
                  // manual groups, or the type label for auto groups.
                  //
                  // Width-bound via ConstrainedBox rather than Flexible: with
                  // `Expanded(name) + Flexible(selection)` both claim flex=1
                  // and split the remaining Row budget evenly. When selection
                  // is short (e.g. "自动"), Flexible's loose fit kept the
                  // `_Badge` at its intrinsic width but still consumed the
                  // allocated flex share, opening a visible gap between the
                  // selection pill and the count/lightning icons on the
                  // right — users (rightly) read it as "not right-aligned".
                  // ConstrainedBox participates in Row layout as an inline
                  // child, so count + lightning slide flush against the
                  // selection pill regardless of its label length (up to
                  // 180px, then ellipsis).
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: _Badge(
                      label: groupSelectionLabel(context, group),
                      isDark: isDark,
                    ),
                  ),
                  if (showSmartHeader) ...[
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
                  // Count badge — far right before lightning
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
          ),

          // ── Expandable node grid ────────────────────────────────────
          // Uses LayoutBuilder + Wrap for responsive column count.
          // minItemWidth 140px → narrow=1col, medium=2col, wide=3+col.
          SizeTransition(
            sizeFactor: _expandAnim,
            axisAlignment: -1.0,
            // Only build node widgets when expanded — avoids creating
            // 100+ widgets per collapsed group on Android.
            child: _expanded
                ? Column(
                    children: [
                      Divider(height: 1, thickness: 0.5, indent: 16, endIndent: 16,
                        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
                      Padding(
                        padding: const EdgeInsets.all(YLSpacing.sm),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const minItemWidth = 140.0;
                            const spacing = 8.0;
                            final cols =
                                ((constraints.maxWidth + spacing) /
                                        (minItemWidth + spacing))
                                    .floor()
                                    .clamp(1, 4);
                            final itemWidth =
                                (constraints.maxWidth - spacing * (cols - 1)) /
                                    cols;
                            // Cap visible nodes to avoid 200+ widgets in memory.
                            // User taps "show all" to override.
                            const maxVisible = 60;
                            final capped = !_showAll && nodeList.length > maxVisible;
                            final visible = capped
                                ? nodeList.sublist(0, maxVisible)
                                : nodeList;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: spacing,
                                  runSpacing: spacing,
                                  children: visible
                                      .map((name) => SizedBox(
                                            width: itemWidth,
                                            child: RepaintBoundary(
                                              child: NodeCardItem(
                                                name: name,
                                                groupName: group.name,
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                ),
                                if (capped)
                                  Center(
                                    child: TextButton(
                                      onPressed: () => setState(() => _showAll = true),
                                      child: Text(
                                        '展开全部 ${nodeList.length} 个节点',
                                        style: YLText.caption.copyWith(
                                          color: YLColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ── NodeCardItem — compact node card for the responsive grid ────────────────

class NodeCardItem extends ConsumerStatefulWidget {
  const NodeCardItem({
    super.key,
    required this.name,
    required this.groupName,
  });

  final String name;
  final String groupName;

  @override
  ConsumerState<NodeCardItem> createState() => _NodeCardItemState();
}

class _NodeCardItemState extends ConsumerState<NodeCardItem> {
  bool _isSwitching = false;

  Future<void> _handleSelect() async {
    final isSelected =
        ref.read(groupSelectedNodeProvider(widget.groupName)) == widget.name;
    if (_isSwitching || isSelected) return;
    setState(() => _isSwitching = true);
    final s = S.of(context);
    final ok = await ref
        .read(proxyGroupsProvider.notifier)
        .changeProxy(widget.groupName, widget.name);
    if (mounted) {
      setState(() => _isSwitching = false);
      if (ok) {
        AppNotifier.success(s.switchedTo(widget.name));
        ref
            .read(recentNodesProvider.notifier)
            .record(widget.name, widget.groupName);
      } else {
        AppNotifier.error(s.switchFailed);
      }
    }
  }

  Widget _buildName(BuildContext context, bool isSelected, bool isDark) {
    final query =
        ref.watch(nodeSearchQueryProvider).trim().toLowerCase();
    final name = widget.name;
    final baseStyle = YLText.body.copyWith(
      fontSize: 13,
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
      color: isSelected
          ? (isDark ? Colors.white : YLColors.primary)
          : (isDark ? Colors.white70 : YLColors.zinc700),
    );
    if (query.isEmpty) {
      return Text(name,
          style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final lower = name.toLowerCase();
    final idx = lower.indexOf(query);
    if (idx < 0) {
      return Text(name,
          style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(
        children: [
          if (idx > 0) TextSpan(text: name.substring(0, idx)),
          TextSpan(
            text: name.substring(idx, idx + query.length),
            style: baseStyle.copyWith(
              color: YLColors.connected,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (idx + query.length < name.length)
            TextSpan(text: name.substring(idx + query.length)),
        ],
        style: baseStyle,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final delay = ref.watch(nodeDelayProvider(widget.name));
    final isSelected =
        ref.watch(groupSelectedNodeProvider(widget.groupName)) == widget.name;
    final isTesting = ref.watch(nodeIsTestingProvider(widget.name));
    final nodeType = ref.watch(nodeTypeProvider(widget.name));
    final isFavorite = ref.watch(nodeIsFavoriteProvider(widget.name));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _handleSelect,
      onLongPress: () {
        ref.read(chainProxyProvider.notifier).addNode(widget.name);
        AppNotifier.info(S.of(context).chainAddHint);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? YLColors.connected.withValues(alpha: 0.15)
                  : YLColors.connected.withValues(alpha: 0.08))
              : (isDark ? YLColors.zinc800 : YLColors.zinc50),
          borderRadius: BorderRadius.circular(YLRadius.md),
          border: Border.all(
            color: isSelected
                ? YLColors.connected.withValues(alpha: 0.35)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06)),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _buildName(context, isSelected, isDark)),
                // Star / favorite button
                GestureDetector(
                  onTap: () => ref
                      .read(favoritesProvider.notifier)
                      .toggle(widget.name),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 13,
                      color: isFavorite ? Colors.amber : YLColors.zinc400,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                if (_isSwitching)
                  const CupertinoActivityIndicator(radius: 6)
                else if (isSelected)
                  const Icon(Icons.check_circle_rounded,
                      size: 13, color: YLColors.connected),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (nodeType != null) ...[
                  _Badge(label: nodeType, isDark: isDark,
                      protocolColor: protocolColor(nodeType)),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: GestureDetector(
                    onTap: isTesting
                        ? null
                        : () => ref.read(delayTestProvider).testDelay(widget.name),
                    child: YLDelayBadge(delay: delay, testing: isTesting),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared badge pill ────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final bool isDark;
  final bool accent;
  final Color? protocolColor;
  const _Badge({
    required this.label,
    required this.isDark,
    this.accent = false,
    this.protocolColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (protocolColor != null) {
      bg = protocolColor!.withValues(alpha: isDark ? 0.15 : 0.10);
      fg = protocolColor!;
    } else if (accent) {
      bg = YLColors.connected.withValues(alpha: 0.12);
      fg = YLColors.connected;
    } else {
      bg = isDark ? YLColors.zinc700 : YLColors.zinc100;
      fg = YLColors.zinc500;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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