import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/proxy.dart';
import '../providers/core_provider.dart';
import '../providers/proxy_provider.dart';
import '../services/app_notifier.dart';
import '../services/core_manager.dart';
import '../services/settings_service.dart';
import '../theme.dart';

class NodesPage extends ConsumerStatefulWidget {
  const NodesPage({super.key});

  @override
  ConsumerState<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends ConsumerState<NodesPage> {
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

    if (status != CoreStatus.running) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.router_outlined, size: 64, color: YLColors.zinc300),
              const SizedBox(height: YLSpacing.xl),
              Text(s.notConnectedHintProxy, style: YLText.titleLarge),
              const SizedBox(height: YLSpacing.sm),
              Text(
                s.connectToViewProxiesDesc,
                style: YLText.body.copyWith(color: YLColors.zinc500),
              ),
            ],
          ),
        ),
      );
    }

    if (groups.isEmpty) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                pinned: true,
                actions: [
                  _CompactRoutingMode(),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => ref.read(proxyGroupsProvider.notifier).refresh(),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                ],
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(YLSpacing.xl, YLSpacing.sm, YLSpacing.xl, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: YLSpacing.lg),
                        child: _GroupCard(group: groups[index]),
                      );
                    },
                    childCount: groups.length,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends ConsumerStatefulWidget {
  final ProxyGroup group;
  const _GroupCard({required this.group});

  @override
  ConsumerState<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<_GroupCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _animController;
  late Animation<double> _expandAnim;
  late Animation<double> _chevronAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 0.0,
    );
    _expandAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
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
    final delays = ref.watch(delayResultsProvider);
    final testing = ref.watch(delayTestingProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha:0.08) : Colors.black.withValues(alpha:0.04),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(YLRadius.xl),
              bottom: _expanded ? Radius.zero : const Radius.circular(YLRadius.xl),
            ),
            child: Padding(
              padding: const EdgeInsets.all(YLSpacing.md),
              child: Row(
                children: [
                  RotationTransition(
                    turns: _chevronAnim,
                    child: Icon(Icons.expand_more_rounded, size: 20, color: YLColors.zinc400),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                  Text(group.name, style: YLText.titleMedium),
                  const SizedBox(width: YLSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? YLColors.zinc800 : YLColors.zinc100,
                      borderRadius: BorderRadius.circular(YLRadius.sm),
                    ),
                    child: Text(
                      group.type,
                      style: YLText.caption.copyWith(fontSize: 10, color: YLColors.zinc500, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    S.of(context).nodesCountLabel(group.all.length),
                    style: YLText.caption.copyWith(color: YLColors.zinc500),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                  IconButton(
                    onPressed: testing.isNotEmpty
                        ? null
                        : () {
                            ref.read(delayTestProvider).testGroup(group.name, group.all);
                            AppNotifier.info(S.of(context).testingGroup(group.name));
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

          // List
          SizeTransition(
            sizeFactor: _expandAnim,
            axisAlignment: -1.0,
            child: Column(
              children: [
                Divider(height: 0.5),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: YLSpacing.xs),
                  child: Column(
                    children: List.generate(group.all.length, (i) {
                      final nodeName = group.all[i];
                      final isSelected = nodeName == group.now;
                      return Column(
                        children: [
                          _NodeTile(
                            name: nodeName,
                            isSelected: isSelected,
                            delay: delays[nodeName],
                            isTesting: testing.contains(nodeName),
                            onSelect: () async {
                              final s = S.of(context);
                              final ok = await ref.read(proxyGroupsProvider.notifier).changeProxy(group.name, nodeName);
                              if (ok) {
                                AppNotifier.success(s.switchedTo(nodeName));
                              } else {
                                AppNotifier.error(s.switchFailed);
                              }
                              return ok;
                            },
                            onTest: () => ref.read(delayTestProvider).testDelay(nodeName),
                          ),
                          if (i < group.all.length - 1)
                            Divider(height: 1, indent: 48),
                        ],
                      );
                    }),
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

class _NodeTile extends StatefulWidget {
  final String name;
  final bool isSelected;
  final int? delay;
  final bool isTesting;
  final Future<bool> Function() onSelect;
  final VoidCallback onTest;

  const _NodeTile({
    required this.name,
    required this.isSelected,
    this.delay,
    required this.isTesting,
    required this.onSelect,
    required this.onTest,
  });

  @override
  State<_NodeTile> createState() => _NodeTileState();
}

// ── Compact Routing Mode (AppBar) ────────────────────────────────────────────

class _CompactRoutingMode extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final routingMode = ref.watch(routingModeProvider);
    final status = ref.watch(coreStatusProvider);

    const modes = ['rule', 'global', 'direct'];
    final labels = [s.routeModeRule, s.routeModeGlobal, s.routeModeDirect];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Container(
        height: 32,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(YLRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(modes.length, (i) {
            final isSelected = modes[i] == routingMode;
            return Flexible(
              child: GestureDetector(
                onTap: () async {
                  ref.read(routingModeProvider.notifier).state = modes[i];
                  await SettingsService.setRoutingMode(modes[i]);
                  if (status == CoreStatus.running) {
                    try {
                      await CoreManager.instance.api.setRoutingMode(modes[i]);
                    } catch (_) {}
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? YLColors.zinc700 : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(YLRadius.pill),
                    boxShadow: isSelected ? YLShadow.sm(context) : [],
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YLText.caption.copyWith(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black)
                          : YLColors.zinc500,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ── Node Tile ───────────────────────────────────────────────────────────────

class _NodeTileState extends State<_NodeTile> {
  bool _isSwitching = false;

  void _handleSelect() async {
    if (_isSwitching || widget.isSelected) return;
    setState(() => _isSwitching = true);
    await widget.onSelect();
    if (mounted) setState(() => _isSwitching = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: YLSpacing.md, vertical: YLSpacing.sm),
          color: widget.isSelected
              ? (isDark ? Colors.white.withValues(alpha:0.08) : YLColors.primary.withValues(alpha:0.05))
              : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: _isSwitching
                    ? const CupertinoActivityIndicator(radius: 7)
                    : (widget.isSelected
                        ? Icon(Icons.check_rounded, color: isDark ? Colors.white : YLColors.primary, size: 18)
                        : null),
              ),
              const SizedBox(width: YLSpacing.xs),
              Expanded(
                child: Text(
                  widget.name,
                  style: YLText.body.copyWith(
                    fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: widget.isSelected
                        ? (isDark ? Colors.white : YLColors.primary)
                        : (isDark ? Colors.white : Colors.black),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: YLSpacing.sm),
              InkWell(
                onTap: widget.isTesting ? null : widget.onTest,
                borderRadius: BorderRadius.circular(YLRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: YLDelayBadge(delay: widget.delay, testing: widget.isTesting),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
