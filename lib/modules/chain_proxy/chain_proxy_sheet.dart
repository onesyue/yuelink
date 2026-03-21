import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/proxy.dart';
import '../../l10n/app_strings.dart';
import '../../shared/app_notifier.dart';
import '../../theme.dart';
import '../nodes/providers/nodes_providers.dart';
import 'chain_proxy_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ChainProxySheet — main bottom sheet
// ══════════════════════════════════════════════════════════════════════════════

class ChainProxySheet extends ConsumerWidget {
  const ChainProxySheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: const ChainProxySheet(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chain = ref.watch(chainProxyProvider);
    final groups = ref.watch(proxyGroupsProvider);

    return Column(
      children: [
        // ── Handle bar ──────────────────────────────────────────────────
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: YLColors.zinc300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // ── Header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.link_rounded,
                  size: 20,
                  color: chain.connected
                      ? YLColors.connected
                      : YLColors.zinc500),
              const SizedBox(width: 8),
              Text(s.chainProxy, style: YLText.titleMedium),
              const Spacer(),
              if (chain.nodes.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      ref.read(chainProxyProvider.notifier).clear(),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(s.chainClear,
                      style:
                          YLText.caption.copyWith(color: YLColors.error)),
                ),
              const SizedBox(width: 4),
              // + add button
              GestureDetector(
                onTap: () => _ChainPickerSheet.show(context, groups),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDark
                        ? YLColors.zinc700
                        : YLColors.zinc100,
                    borderRadius: BorderRadius.circular(YLRadius.md),
                  ),
                  child: Icon(Icons.add_rounded,
                      size: 18,
                      color: isDark ? Colors.white70 : YLColors.zinc700),
                ),
              ),
            ],
          ),
        ),

        // ── Active-group selector ────────────────────────────────────────
        if (groups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _GroupSelector(
              groups: groups,
              selected: chain.activeGroup,
              onChanged: (g) =>
                  ref.read(chainProxyProvider.notifier).setActiveGroup(g),
            ),
          ),

        const SizedBox(height: 8),

        // ── Chain nodes list ─────────────────────────────────────────────
        Expanded(
          child: chain.nodes.isEmpty
              ? _EmptyState(onAdd: () => _ChainPickerSheet.show(context, groups))
              : Builder(builder: (context) {
                  final groupNames = groups.map((g) => g.name).toSet();
                  return ReorderableListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: chain.nodes.length,
                    onReorder: (oldI, newI) => ref
                        .read(chainProxyProvider.notifier)
                        .reorder(oldI, newI),
                    itemBuilder: (context, index) {
                      final name = chain.nodes[index];
                      final isEntry = index == 0;
                      final isExit =
                          index == chain.nodes.length - 1 &&
                              chain.nodes.length >= 2;
                      return _ChainNodeTile(
                        key: ValueKey(name),
                        name: name,
                        index: index,
                        isEntry: isEntry,
                        isExit: isExit,
                        isGroup: groupNames.contains(name),
                        isDark: isDark,
                        onRemove: () => ref
                            .read(chainProxyProvider.notifier)
                            .removeNode(index),
                      );
                    },
                  );
                }),
        ),

        // ── Connect / Disconnect button ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: chain.connected
                ? OutlinedButton.icon(
                    onPressed: chain.loading
                        ? null
                        : () => ref
                            .read(chainProxyProvider.notifier)
                            .disconnect(),
                    icon: chain.loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2))
                        : const Icon(Icons.link_off_rounded, size: 18),
                    label: Text(s.chainDisconnect),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: YLColors.error,
                      side: const BorderSide(color: YLColors.error),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(YLRadius.lg),
                      ),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: chain.canConnect
                        ? () => ref
                            .read(chainProxyProvider.notifier)
                            .connect()
                        : null,
                    icon: chain.loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Icon(Icons.link_rounded, size: 18),
                    label: Text(chain.nodes.length < 2
                        ? s.chainNeedTwoNodes
                        : s.chainConnect),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(YLRadius.lg),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Empty state with add button
// ══════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_link_rounded, size: 48, color: YLColors.zinc300),
          const SizedBox(height: 12),
          Text(s.chainEmptyHint,
              style: YLText.body.copyWith(color: YLColors.zinc400)),
          const SizedBox(height: 4),
          Text(s.chainEmptyDesc,
              style: YLText.caption.copyWith(color: YLColors.zinc400),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(s.chainPickerTitle),
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YLRadius.pill),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ChainPickerSheet — node / group picker
// ══════════════════════════════════════════════════════════════════════════════

class _ChainPickerSheet extends ConsumerStatefulWidget {
  final List<ProxyGroup> groups;
  const _ChainPickerSheet({required this.groups});

  static void show(BuildContext context, List<ProxyGroup> groups) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, _) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: _ChainPickerSheet(groups: groups),
        ),
      ),
    );
  }

  @override
  ConsumerState<_ChainPickerSheet> createState() =>
      _ChainPickerSheetState();
}

class _ChainPickerSheetState extends ConsumerState<_ChainPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chainNodes = ref.watch(
        chainProxyProvider.select((c) => c.nodes.toSet()));

    // Build filtered item list
    final q = _query.trim().toLowerCase();

    // ── Groups section ────────────────────────────────────────────────
    final filteredGroups = widget.groups
        .where((g) => q.isEmpty || g.name.toLowerCase().contains(q))
        .toList();

    // ── Nodes section (per group) ─────────────────────────────────────
    // Build a deduplicated flat list: (groupName, nodeName) pairs
    final seenNodes = <String>{};
    // Collect groups that have matching nodes
    final nodesByGroup = <_GroupNodes>[];
    for (final group in widget.groups) {
      final matchingNodes = group.all
          .where((n) => !seenNodes.contains(n))
          .where((n) => q.isEmpty || n.toLowerCase().contains(q))
          .toList();
      for (final n in group.all) {
        seenNodes.add(n);
      }
      if (matchingNodes.isNotEmpty) {
        nodesByGroup.add(_GroupNodes(group.name, matchingNodes));
      }
    }

    final hasResults =
        filteredGroups.isNotEmpty || nodesByGroup.isNotEmpty;

    return Column(
      children: [
        // Handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: YLColors.zinc300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              Text(s.chainPickerTitle, style: YLText.titleMedium),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close_rounded,
                    size: 20, color: YLColors.zinc400),
              ),
            ],
          ),
        ),

        // Search bar
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchCtrl,
            autofocus: false,
            onChanged: (v) => setState(() => _query = v),
            style: YLText.body,
            decoration: InputDecoration(
              hintText: s.chainPickerSearch,
              hintStyle:
                  YLText.body.copyWith(color: YLColors.zinc400),
              prefixIcon: const Icon(Icons.search_rounded,
                  size: 18, color: YLColors.zinc400),
              suffixIcon: _query.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: YLColors.zinc400),
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  vertical: 10, horizontal: 12),
              filled: true,
              fillColor:
                  isDark ? YLColors.zinc800 : YLColors.zinc100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(YLRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Results list
        Expanded(
          child: !hasResults
              ? Center(
                  child: Text(
                    _query.isEmpty ? '' : '无匹配结果',
                    style:
                        YLText.body.copyWith(color: YLColors.zinc400),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(
                      left: 16, right: 16, bottom: 24),
                  children: [
                    // ── Groups ────────────────────────────────────────
                    if (filteredGroups.isNotEmpty) ...[
                      _SectionHeader(label: s.chainSectionGroups),
                      for (final group in filteredGroups)
                        _PickerItem(
                          icon: Icons.account_tree_rounded,
                          iconColor: Colors.purple.shade300,
                          name: group.name,
                          subtitle: group.type,
                          inChain: chainNodes.contains(group.name),
                          isDark: isDark,
                          onTap: () => _toggle(group.name),
                        ),
                      const SizedBox(height: 4),
                    ],

                    // ── Nodes ─────────────────────────────────────────
                    if (nodesByGroup.isNotEmpty) ...[
                      _SectionHeader(label: s.chainSectionNodes),
                      for (final entry in nodesByGroup) ...[
                        // Group label (only shown when not searching
                        // or when multiple groups have results)
                        if (nodesByGroup.length > 1 || q.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 4, top: 6, bottom: 2),
                            child: Text(
                              entry.groupName,
                              style: YLText.caption.copyWith(
                                  color: YLColors.zinc500,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        for (final nodeName in entry.nodes)
                          _PickerItem(
                            icon: Icons.wifi_tethering_rounded,
                            iconColor: YLColors.zinc400,
                            name: nodeName,
                            subtitle: null,
                            inChain: chainNodes.contains(nodeName),
                            isDark: isDark,
                            onTap: () => _toggle(nodeName),
                          ),
                      ],
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  void _toggle(String name) {
    final notifier = ref.read(chainProxyProvider.notifier);
    final nodes = ref.read(chainProxyProvider).nodes;
    if (nodes.contains(name)) {
      notifier.removeNode(nodes.indexOf(name));
    } else {
      notifier.addNode(name);
      AppNotifier.info(S.current.chainAddHint);
    }
  }
}

// ── Data helper ───────────────────────────────────────────────────────────────

class _GroupNodes {
  final String groupName;
  final List<String> nodes;
  const _GroupNodes(this.groupName, this.nodes);
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6, left: 4),
      child: Text(
        label,
        style: YLText.caption.copyWith(
          color: YLColors.zinc400,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Picker item ───────────────────────────────────────────────────────────────

class _PickerItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String? subtitle;
  final bool inChain;
  final bool isDark;
  final VoidCallback onTap;

  const _PickerItem({
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.subtitle,
    required this.inChain,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(YLRadius.md);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: inChain
            ? (isDark
                ? YLColors.zinc700.withValues(alpha: 0.4)
                : YLColors.zinc50)
            : (isDark ? YLColors.zinc800 : Colors.white),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: inChain
                    ? (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.06))
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06)),
                width: 0.5,
              ),
            ),
            child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: inChain
                    ? YLColors.zinc500.withValues(alpha: 0.5)
                    : iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: YLText.body.copyWith(
                      color: inChain
                          ? YLColors.zinc400
                          : (isDark ? Colors.white : YLColors.zinc900),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: YLText.caption
                          .copyWith(fontSize: 10, color: YLColors.zinc500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (inChain)
              Icon(Icons.remove_circle_rounded,
                  size: 16, color: YLColors.error.withValues(alpha: 0.7))
            else
              Icon(Icons.add_rounded,
                  size: 16,
                  color: isDark ? YLColors.zinc500 : YLColors.zinc400),
          ],
        ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Active-group selector dropdown
// ══════════════════════════════════════════════════════════════════════════════

class _GroupSelector extends StatelessWidget {
  final List<ProxyGroup> groups;
  final String? selected;
  final ValueChanged<String> onChanged;

  const _GroupSelector({
    required this.groups,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectorGroups =
        groups.where((g) => g.type.toLowerCase() == 'selector').toList();
    if (selectorGroups.isEmpty) return const SizedBox.shrink();

    final effectiveSelected = selected ??
        (selectorGroups.isNotEmpty ? selectorGroups.first.name : null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : YLColors.zinc100,
        borderRadius: BorderRadius.circular(YLRadius.md),
      ),
      child: DropdownButton<String>(
        value: effectiveSelected,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: isDark ? YLColors.zinc800 : Colors.white,
        style: YLText.body.copyWith(
          color: isDark ? Colors.white : YLColors.zinc900,
        ),
        items: selectorGroups
            .map((g) => DropdownMenuItem(
                  value: g.name,
                  child: Text(g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Chain node tile (in the main sheet)
// ══════════════════════════════════════════════════════════════════════════════

class _ChainNodeTile extends StatelessWidget {
  final String name;
  final int index;
  final bool isEntry;
  final bool isExit;
  final bool isGroup;
  final bool isDark;
  final VoidCallback onRemove;

  const _ChainNodeTile({
    super.key,
    required this.name,
    required this.index,
    required this.isEntry,
    required this.isExit,
    required this.isGroup,
    required this.isDark,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc800 : Colors.white,
          borderRadius: BorderRadius.circular(YLRadius.md),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.drag_handle_rounded,
                size: 18, color: YLColors.zinc400),
            const SizedBox(width: 8),
            Icon(
              isGroup
                  ? Icons.account_tree_rounded
                  : Icons.wifi_tethering_rounded,
              size: 14,
              color:
                  isGroup ? Colors.purple.shade300 : YLColors.zinc400,
            ),
            const SizedBox(width: 6),
            if (isEntry || isExit)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: isEntry
                      ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(YLRadius.sm),
                ),
                child: Text(
                  isEntry ? s.chainEntry : s.chainExit,
                  style: YLText.caption.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color:
                        isEntry ? const Color(0xFF22C55E) : Colors.orange,
                  ),
                ),
              ),
            Expanded(
              child: Text(name,
                  style: YLText.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (!isExit && index < 99)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 14, color: YLColors.zinc400),
              ),
            GestureDetector(
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close_rounded,
                    size: 16, color: YLColors.zinc400),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
