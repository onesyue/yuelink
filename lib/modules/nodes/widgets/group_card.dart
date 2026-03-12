import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/proxy.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';
import '../providers/node_providers.dart';
import '../providers/nodes_providers.dart';

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
  bool _expanded = true;
  late AnimationController _animController;
  late Animation<double> _expandAnim;
  late Animation<double> _chevronAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0, // start expanded
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
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final testing = ref.watch(delayTestingProvider);
    final delays = ref.read(delayResultsProvider);
    final sorted = _sortedNodes(group.all, widget.sortMode, delays);
    final query = widget.searchQuery.trim().toLowerCase();
    final nodeList = query.isEmpty
        ? sorted
        : sorted
            .where((n) => n.toLowerCase().contains(query))
            .toList();
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
          // ── Header (tap to toggle) ──────────────────────────────────
          InkWell(
            onTap: _toggle,
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
                    child: Icon(Icons.expand_more_rounded,
                        size: 20, color: YLColors.zinc400),
                  ),
                  const SizedBox(width: YLSpacing.sm),
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
                        : S.of(context).nodesCountLabel(group.all.length),
                    style: YLText.caption.copyWith(
                      color: isFiltered
                          ? YLColors.connected
                          : YLColors.zinc500,
                    ),
                  ),
                  const SizedBox(width: YLSpacing.sm),
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
          ),

          // ── Expandable node grid ────────────────────────────────────
          // Uses LayoutBuilder + Wrap for responsive column count.
          // minItemWidth 140px → narrow=1col, medium=2col, wide=3+col.
          SizeTransition(
            sizeFactor: _expandAnim,
            axisAlignment: -1.0,
            child: Column(
              children: [
                const Divider(height: 0.5),
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
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: nodeList
                            .map((name) => SizedBox(
                                  width: itemWidth,
                                  child: NodeCardItem(
                                    name: name,
                                    groupName: group.name,
                                  ),
                                ))
                            .toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _handleSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
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
                if (_isSwitching)
                  const CupertinoActivityIndicator(radius: 6)
                else if (isSelected)
                  Icon(Icons.check_circle_rounded,
                      size: 13, color: YLColors.connected),
              ],
            ),
            const SizedBox(height: 4),
            YLDelayBadge(delay: delay, testing: isTesting),
          ],
        ),
      ),
    );
  }
}
