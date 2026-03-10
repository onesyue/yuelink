import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/proxy.dart';
import '../providers/core_provider.dart';
import '../providers/proxy_provider.dart';
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
    Future.microtask(
        () => ref.read(proxyGroupsProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final status = ref.watch(coreStatusProvider);
    final groups = ref.watch(proxyGroupsProvider);

    if (status != CoreStatus.running) {
      return Scaffold(
        body: YLEmptyState(
          icon: Icons.router_outlined,
          message: s.notConnectedHintProxy,
        ),
      );
    }

    if (groups.isEmpty) {
      return Scaffold(
        body: const Center(child: CircularProgressIndicator()),
        floatingActionButton: FloatingActionButton.small(
          onPressed: () =>
              ref.read(proxyGroupsProvider.notifier).refresh(),
          child: const Icon(Icons.refresh),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          // ── Top bar ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.navNodes.toUpperCase(),
                  style: YLText.caption.copyWith(
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w600,
                    color: YLColors.zinc400,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.navNodes,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 0.5,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),

          // Routing mode bar
          _RoutingModeBar(),
          Divider(
            height: 1,
            thickness: 0.5,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
          // Group list
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.read(proxyGroupsProvider.notifier).refresh(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                itemCount: groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) =>
                    _GroupCard(group: groups[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Routing Mode Bar ──────────────────────────────────────────────────────────

class _RoutingModeBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final mode = ref.watch(routingModeProvider);
    final isRunning =
        ref.watch(coreStatusProvider) == CoreStatus.running;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SegmentedButton<String>(
        style: SegmentedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          textStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        segments: [
          ButtonSegment(
              value: 'rule',
              label: Text(s.routeModeRule),
              icon: const Icon(Icons.rule_rounded, size: 14)),
          ButtonSegment(
              value: 'global',
              label: Text(s.routeModeGlobal),
              icon: const Icon(Icons.public_rounded, size: 14)),
          ButtonSegment(
              value: 'direct',
              label: Text(s.routeModeDirect),
              icon: const Icon(Icons.wifi_tethering_rounded, size: 14)),
        ],
        selected: {mode},
        onSelectionChanged: (set) async {
          final newMode = set.first;
          ref.read(routingModeProvider.notifier).state = newMode;
          await SettingsService.setRoutingMode(newMode);
          if (isRunning) {
            try {
              await ref.read(mihomoApiProvider).setRoutingMode(newMode);
            } catch (_) {}
          }
        },
      ),
    );
  }
}

// ── Group Card ────────────────────────────────────────────────────────────────

class _GroupCard extends ConsumerStatefulWidget {
  final ProxyGroup group;
  const _GroupCard({required this.group});

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
      value: 1.0, // start expanded
    );
    _expandAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
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
    final s = S.of(context);
    final delays = ref.watch(delayResultsProvider);
    final testing = ref.watch(delayTestingProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Group header (tappable to collapse) ──────────────────
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(YLRadius.xl),
              bottom: _expanded
                  ? Radius.zero
                  : const Radius.circular(YLRadius.xl),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  // Chevron
                  RotationTransition(
                    turns: _chevronAnim,
                    child: Icon(Icons.expand_more_rounded,
                        size: 18,
                        color: isDark ? YLColors.zinc500 : YLColors.zinc400),
                  ),
                  const SizedBox(width: 4),
                  Icon(_groupIcon(group.name),
                      size: 14,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(group.name, style: YLText.titleMedium),
                  const SizedBox(width: 6),
                  _TypeChip(type: group.type),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      group.now,
                      style: YLText.caption.copyWith(
                        color: isDark ? YLColors.zinc500 : YLColors.zinc400,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  // Node count badge (always visible)
                  Text(
                    '${group.all.length}',
                    style: YLText.caption.copyWith(
                      color: isDark ? YLColors.zinc600 : YLColors.zinc400,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Test all button
                  InkWell(
                    onTap: testing.isNotEmpty
                        ? null
                        : () => ref
                            .read(delayTestProvider)
                            .testGroup(group.name, group.all),
                    borderRadius: BorderRadius.circular(YLRadius.md),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: testing.isNotEmpty
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5))
                          : Icon(Icons.bolt_rounded,
                              size: 14,
                              color: isDark
                                  ? YLColors.zinc400
                                  : YLColors.zinc500),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Collapsible node list ──────────────────────────────
          SizeTransition(
            sizeFactor: _expandAnim,
            axisAlignment: -1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Divider between header and list
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                ),

                // Node list
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Column(
                    children: [
                      for (int i = 0; i < group.all.length; i++) ...[
                        YLNodeTile(
                          name: group.all[i],
                          isSelected: group.all[i] == group.now,
                          delay: delays[group.all[i]],
                          isTesting: testing.contains(group.all[i]),
                          onSelect: () => ref
                              .read(proxyGroupsProvider.notifier)
                              .changeProxy(group.name, group.all[i]),
                          onTest: () => ref
                              .read(delayTestProvider)
                              .testDelay(group.all[i]),
                        ),
                        if (i < group.all.length - 1)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 25,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _groupIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('youtube')) return Icons.play_circle_outline;
    if (n.contains('tiktok')) return Icons.music_note;
    if (n.contains('ai') ||
        n.contains('openai') ||
        n.contains('claude')) {
      return Icons.auto_awesome;
    }
    if (n.contains('google')) return Icons.search;
    if (n.contains('telegram')) return Icons.send;
    if (n.contains('github')) return Icons.code;
    if (n.contains('流媒体') ||
        n.contains('netflix') ||
        n.contains('disney')) {
      return Icons.movie_outlined;
    }
    if (n.contains('社交') ||
        n.contains('twitter') ||
        n.contains('facebook')) {
      return Icons.people_outline;
    }
    if (n.contains('游戏') ||
        n.contains('game') ||
        n.contains('steam')) {
      return Icons.sports_esports;
    }
    if (n.contains('兜底') ||
        n.contains('fallback') ||
        n.contains('漏网')) {
      return Icons.catching_pokemon;
    }
    if (n.contains('自动') ||
        n.contains('url-test') ||
        n.contains('auto')) {
      return Icons.speed;
    }
    if (n.contains('故障') || n.contains('转移')) return Icons.swap_horiz;
    if (n.contains('香港') || n.contains('🇭🇰')) return Icons.location_on;
    if (n.contains('聚合') || n.contains('balance')) return Icons.balance;
    if (n.contains('更多')) return Icons.language;
    return Icons.dns_outlined;
  }
}

// ── Type Chip ─────────────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final color = _color(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Text(
        _label(type, s),
        style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color),
      ),
    );
  }

  String _label(String type, S s) {
    switch (type) {
      case 'Selector': return s.typeManual;
      case 'URLTest':  return s.typeAuto;
      case 'Fallback': return s.typeFallback;
      case 'LoadBalance': return s.typeLoadBalance;
      default: return type;
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'Selector':    return Colors.blue;
      case 'URLTest':     return Colors.green;
      case 'Fallback':    return Colors.orange;
      case 'LoadBalance': return Colors.purple;
      default:            return Colors.grey;
    }
  }
}
