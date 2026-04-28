import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/proxy.dart';
import '../../i18n/app_strings.dart';
import '../../shared/app_notifier.dart';
import '../../shared/widgets/empty_state.dart';
import '../../theme.dart';
import 'chain_proxy_provider.dart';
import 'cross_profile_nodes_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ChainPickerSheet — node / group picker
// ══════════════════════════════════════════════════════════════════════════════

class ChainPickerSheet extends ConsumerStatefulWidget {
  final List<ProxyGroup> groups;
  const ChainPickerSheet({super.key, required this.groups});

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
          child: ChainPickerSheet(groups: groups),
        ),
      ),
    );
  }

  @override
  ConsumerState<ChainPickerSheet> createState() =>
      _ChainPickerSheetState();
}

class _ChainPickerSheetState extends ConsumerState<ChainPickerSheet> {
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
                child: const Icon(Icons.close_rounded,
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
                  child: _query.isEmpty
                      ? const SizedBox.shrink()
                      : const YLEmptyState(
                          icon: Icons.search_off_rounded,
                          title: '无匹配结果',
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

                    // ── Other subscriptions ──────────────────────
                    ..._buildCrossProfileSection(
                        ref, chainNodes, isDark, q),
                  ],
                ),
        ),
      ],
    );
  }

  /// Build the "其他订阅" section showing nodes from non-active profiles.
  List<Widget> _buildCrossProfileSection(
      WidgetRef ref, Set<String> chainNodes, bool isDark, String q) {
    final crossAsync = ref.watch(crossProfileNodesProvider);
    return crossAsync.when(
      loading: () => const [],
      error: (_, _) => const [],
      data: (entries) {
        if (entries.isEmpty) return [];
        final widgets = <Widget>[
          const SizedBox(height: 8),
          _SectionHeader(label: S.current.otherSubscriptions),
        ];
        for (final entry in entries) {
          final filtered = q.isEmpty
              ? entry.nodeNames
              : entry.nodeNames
                  .where((n) => n.toLowerCase().contains(q))
                  .toList();
          if (filtered.isEmpty) continue;
          widgets.add(Padding(
            padding: const EdgeInsets.only(left: 4, top: 6, bottom: 2),
            child: Text(
              entry.profileName,
              style: YLText.caption.copyWith(
                  color: Colors.orange.shade400,
                  fontWeight: FontWeight.w600),
            ),
          ));
          for (final nodeName in filtered) {
            widgets.add(_PickerItem(
              icon: Icons.language_rounded,
              iconColor: Colors.orange.shade300,
              name: nodeName,
              subtitle: entry.profileName,
              inChain: chainNodes.contains(nodeName),
              isDark: isDark,
              onTap: () => _toggleExternal(nodeName, entry.profileId),
            ));
          }
        }
        return widgets;
      },
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

  void _toggleExternal(String name, String profileId) {
    final notifier = ref.read(chainProxyProvider.notifier);
    final nodes = ref.read(chainProxyProvider).nodes;
    if (nodes.contains(name)) {
      notifier.removeNode(nodes.indexOf(name));
    } else {
      notifier.addNode(name, profileId: profileId);
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
