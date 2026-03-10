import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/proxy.dart';
import '../providers/core_provider.dart';
import '../providers/proxy_provider.dart';
import '../services/app_notifier.dart';
import '../theme.dart';

class NodesPage extends ConsumerStatefulWidget {
  const NodesPage({super.key});

  @override
  ConsumerState<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends ConsumerState<NodesPage> {
  String _search = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(proxyGroupsProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final status = ref.watch(coreStatusProvider);
    final groups = ref.watch(proxyGroupsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (status != CoreStatus.running) {
      return Scaffold(
        body: YLEmptyState(
          icon: Icons.dns_outlined,
          message: s.notConnectedHintProxy,
          action: Text(
            'Start the connection first.',
            style: YLText.caption.copyWith(color: YLColors.zinc400),
          ),
        ),
      );
    }

    if (groups.isEmpty) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }

    // Filter groups by search
    final filteredGroups = _search.isEmpty
        ? groups
        : groups.where((g) {
            if (g.name.toLowerCase().contains(_search)) return true;
            return g.all.any((n) => n.toLowerCase().contains(_search));
          }).toList();

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(s.navNodes, style: YLText.display.copyWith(
                      fontSize: 28,
                      color: isDark ? Colors.white : Colors.black,
                    )),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    color: YLColors.zinc400,
                    onPressed: () =>
                        ref.read(proxyGroupsProvider.notifier).refresh(),
                  ),
                ],
              ),
            ),
          ),

          // Search
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: TextField(
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
                style: YLText.body,
                decoration: InputDecoration(
                  hintText: 'Search nodes...',
                  hintStyle: YLText.body.copyWith(color: YLColors.zinc400),
                  prefixIcon: const Icon(Icons.search, size: 20, color: YLColors.zinc400),
                  filled: true,
                  fillColor: isDark ? YLColors.surfaceDark : YLColors.surfaceLight,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(YLRadius.md),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                      width: 0.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(YLRadius.md),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                      width: 0.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(YLRadius.md),
                    borderSide: const BorderSide(color: YLColors.primary, width: 1),
                  ),
                ),
              ),
            ),
          ),

          // Groups
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _GroupCard(
                      group: filteredGroups[index],
                      searchQuery: _search,
                    ),
                  );
                },
                childCount: filteredGroups.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Group Card ───────────────────────────────────────────────────────────────

class _GroupCard extends ConsumerStatefulWidget {
  final ProxyGroup group;
  final String searchQuery;
  const _GroupCard({required this.group, this.searchQuery = ''});

  @override
  ConsumerState<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<_GroupCard>
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
      value: 1.0,
    );
    _expandAnim = CurvedAnimation(
        parent: _animController, curve: Curves.easeOutCubic);
    _chevronAnim =
        Tween<double>(begin: 0, end: 0.5).animate(_expandAnim);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _animController.forward() : _animController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final delays = ref.watch(delayResultsProvider);
    final testing = ref.watch(delayTestingProvider);

    // Filter nodes if searching
    final nodes = widget.searchQuery.isEmpty
        ? group.all
        : group.all
            .where(
                (n) => n.toLowerCase().contains(widget.searchQuery))
            .toList();

    return YLSurface(
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(YLRadius.xl),
              bottom: _expanded
                  ? Radius.zero
                  : const Radius.circular(YLRadius.xl),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  RotationTransition(
                    turns: _chevronAnim,
                    child: const Icon(Icons.expand_more_rounded,
                        size: 20, color: YLColors.zinc400),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(group.name, style: YLText.titleMedium),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.06)
                          : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(YLRadius.sm),
                    ),
                    child: Text(
                      '${nodes.length}',
                      style: YLText.caption.copyWith(
                          color: YLColors.zinc500,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: testing.isNotEmpty
                          ? null
                          : () {
                              ref
                                  .read(delayTestProvider)
                                  .testGroup(group.name, group.all);
                            },
                      icon: testing.isNotEmpty
                          ? const CupertinoActivityIndicator(radius: 7)
                          : const Icon(Icons.bolt_rounded, size: 18),
                      color: YLColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Node list
          SizeTransition(
            sizeFactor: _expandAnim,
            axisAlignment: -1.0,
            child: Column(
              children: [
                const Divider(height: 0.5, indent: 16, endIndent: 16),
                ...List.generate(nodes.length, (i) {
                  final nodeName = nodes[i];
                  final isSelected = nodeName == group.now;
                  return _NodeTile(
                    name: nodeName,
                    isSelected: isSelected,
                    delay: delays[nodeName],
                    isTesting: testing.contains(nodeName),
                    showDivider: i < nodes.length - 1,
                    onSelect: () async {
                      final ok = await ref
                          .read(proxyGroupsProvider.notifier)
                          .changeProxy(group.name, nodeName);
                      if (ok) {
                        ref.read(proxyGroupsProvider.notifier).refresh();
                      }
                      return ok;
                    },
                    onTest: () =>
                        ref.read(delayTestProvider).testDelay(nodeName),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Node Tile ────────────────────────────────────────────────────────────────

class _NodeTile extends StatefulWidget {
  final String name;
  final bool isSelected;
  final int? delay;
  final bool isTesting;
  final bool showDivider;
  final Future<bool> Function() onSelect;
  final VoidCallback onTest;

  const _NodeTile({
    required this.name,
    required this.isSelected,
    this.delay,
    required this.isTesting,
    this.showDivider = true,
    required this.onSelect,
    required this.onTest,
  });

  @override
  State<_NodeTile> createState() => _NodeTileState();
}

class _NodeTileState extends State<_NodeTile> {
  bool _switching = false;

  void _handleSelect() async {
    if (_switching || widget.isSelected) return;
    setState(() => _switching = true);
    await widget.onSelect();
    if (mounted) setState(() => _switching = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleSelect,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: _switching
                        ? const CupertinoActivityIndicator(radius: 7)
                        : widget.isSelected
                            ? const Icon(Icons.check_rounded,
                                color: YLColors.primary, size: 18)
                            : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.name,
                      style: YLText.body.copyWith(
                        fontWeight: widget.isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: widget.isSelected
                            ? YLColors.primary
                            : (isDark ? Colors.white : Colors.black),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.isTesting ? null : widget.onTest,
                    child: YLDelayBadge(
                        delay: widget.delay, testing: widget.isTesting),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.showDivider)
          Divider(height: 0.5, indent: 48, endIndent: 16),
      ],
    );
  }
}
