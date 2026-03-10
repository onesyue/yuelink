import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/proxy.dart';
import '../providers/core_provider.dart';
import '../providers/proxy_provider.dart';
import '../services/app_notifier.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (status != CoreStatus.running) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(YLSpacing.xl),
                decoration: BoxDecoration(
                  color: isDark ? YLColors.zinc900 : YLColors.zinc100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.router_outlined, size: 48, color: YLColors.zinc400),
              ),
              const SizedBox(height: YLSpacing.xl),
              Text(s.notConnectedHintProxy, style: YLText.titleLarge),
              const SizedBox(height: YLSpacing.sm),
              Text(
                'Connect to the core to view and manage proxies.',
                style: YLText.body.copyWith(color: YLColors.zinc500),
              ),
            ],
          ),
        ),
      );
    }

    if (groups.isEmpty) {
      return Scaffold(
        body: const Center(child: CircularProgressIndicator()),
        floatingActionButton: FloatingActionButton.small(
          onPressed: () => ref.read(proxyGroupsProvider.notifier).refresh(),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: isDark ? Colors.black : Colors.white,
          elevation: 0,
          child: const Icon(Icons.refresh_rounded),
        ),
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(YLSpacing.xl, YLSpacing.xxl, YLSpacing.xl, YLSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.navNodes.toUpperCase(),
                  style: YLText.caption.copyWith(
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.navNodes,
                  style: YLText.display.copyWith(
                    color: isDark ? YLColors.zinc50 : YLColors.zinc900,
                  ),
                ),
              ],
            ),
          ),

          // Routing mode bar
          _RoutingModeBar(),
          
          Divider(
            height: 1,
            thickness: 0.5,
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
          ),
          
          // Group list
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.read(proxyGroupsProvider.notifier).refresh(),
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: isDark ? YLColors.zinc800 : Colors.white,
              child: ListView.separated(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(YLSpacing.lg, YLSpacing.lg, YLSpacing.lg, YLSpacing.massive),
                itemCount: groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: YLSpacing.lg),
                itemBuilder: (context, i) => _GroupCard(group: groups[i]),
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
    final isRunning = ref.watch(coreStatusProvider) == CoreStatus.running;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: YLSpacing.lg, vertical: YLSpacing.md),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: [
            ButtonSegment(
                value: 'rule',
                label: Text(s.routeModeRule),
                icon: const Icon(Icons.rule_rounded, size: 16)),
            ButtonSegment(
                value: 'global',
                label: Text(s.routeModeGlobal),
                icon: const Icon(Icons.public_rounded, size: 16)),
            ButtonSegment(
                value: 'direct',
                label: Text(s.routeModeDirect),
                icon: const Icon(Icons.wifi_tethering_rounded, size: 16)),
          ],
          selected: {mode},
          onSelectionChanged: (Set<String> newSelection) async {
            final newMode = newSelection.first;
            ref.read(routingModeProvider.notifier).state = newMode;
            await SettingsService.setRoutingMode(newMode);
            if (isRunning) {
              try {
                final ok = await ref.read(mihomoApiProvider).setRoutingMode(newMode);
                if (ok) {
                  AppNotifier.success('已切换至 ${newMode.toUpperCase()} 模式');
                }
              } catch (_) {
                AppNotifier.error('模式切换失败');
              }
            }
          },
          showSelectedIcon: false,
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final delays = ref.watch(delayResultsProvider);
    final testing = ref.watch(delayTestingProvider);

    return YLSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Group header (tappable to collapse) ──────────────────
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
                  // Chevron
                  RotationTransition(
                    turns: _chevronAnim,
                    child: Icon(Icons.expand_more_rounded,
                        size: 20,
                        color: isDark ? YLColors.zinc500 : YLColors.zinc400),
                  ),
                  const SizedBox(width: YLSpacing.xs),
                  Icon(_groupIcon(group.name),
                      size: 18,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: YLSpacing.sm),
                  Text(group.name, style: YLText.titleMedium),
                  const SizedBox(width: YLSpacing.sm),
                  _TypeChip(type: group.type),
                  const SizedBox(width: YLSpacing.sm),
                  Expanded(
                    child: Text(
                      group.now,
                      style: YLText.caption.copyWith(
                        color: isDark ? YLColors.zinc500 : YLColors.zinc500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                  // Node count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? YLColors.zinc800 : YLColors.zinc100,
                      borderRadius: BorderRadius.circular(YLRadius.sm),
                    ),
                    child: Text(
                      '${group.all.length}',
                      style: YLText.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? YLColors.zinc400 : YLColors.zinc600,
                      ),
                    ),
                  ),
                  const SizedBox(width: YLSpacing.xs),
                  // Test all button
                  IconButton(
                    onPressed: testing.isNotEmpty
                        ? null
                        : () {
                            ref.read(delayTestProvider).testGroup(group.name, group.all);
                            AppNotifier.info('开始测速: ${group.name}');
                          },
                    icon: testing.isNotEmpty
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.bolt_rounded),
                    iconSize: 18,
                    color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Test All',
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
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: YLSpacing.xs),
                  child: Column(
                    children: [
                      for (int i = 0; i < group.all.length; i++) ...[
                        _NodeTile(
                          name: group.all[i],
                          isSelected: group.all[i] == group.now,
                          delay: delays[group.all[i]],
                          isTesting: testing.contains(group.all[i]),
                          onSelect: () {
                            ref.read(proxyGroupsProvider.notifier).changeProxy(group.name, group.all[i]);
                            AppNotifier.success('已切换至: ${group.all[i]}');
                          },
                          onTest: () => ref.read(delayTestProvider).testDelay(group.all[i]),
                        ),
                        if (i < group.all.length - 1)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 40, // Align with text
                            color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
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
    if (n.contains('youtube')) return Icons.play_circle_outline_rounded;
    if (n.contains('tiktok')) return Icons.music_note_rounded;
    if (n.contains('ai') || n.contains('openai') || n.contains('claude')) return Icons.auto_awesome_rounded;
    if (n.contains('google')) return Icons.search_rounded;
    if (n.contains('telegram')) return Icons.send_rounded;
    if (n.contains('github')) return Icons.code_rounded;
    if (n.contains('流媒体') || n.contains('netflix') || n.contains('disney')) return Icons.movie_outlined;
    if (n.contains('社交') || n.contains('twitter') || n.contains('facebook')) return Icons.people_outline_rounded;
    if (n.contains('游戏') || n.contains('game') || n.contains('steam')) return Icons.sports_esports_rounded;
    if (n.contains('兜底') || n.contains('fallback') || n.contains('漏网')) return Icons.catching_pokemon;
    if (n.contains('自动') || n.contains('url-test') || n.contains('auto')) return Icons.speed_rounded;
    if (n.contains('故障') || n.contains('转移')) return Icons.swap_horiz_rounded;
    if (n.contains('香港') || n.contains('🇭🇰')) return Icons.location_on_rounded;
    if (n.contains('聚合') || n.contains('balance')) return Icons.balance_rounded;
    if (n.contains('更多')) return Icons.language_rounded;
    return Icons.dns_outlined;
  }
}

// ── Node Tile (Compact & Interactive) ─────────────────────────────────────────

class _NodeTile extends StatelessWidget {
  final String name;
  final bool isSelected;
  final int? delay;
  final bool isTesting;
  final VoidCallback onSelect;
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: YLSpacing.md, vertical: YLSpacing.sm),
          child: Row(
            children: [
              // Selection Indicator
              SizedBox(
                width: 24,
                child: isSelected
                    ? Icon(Icons.check_circle_rounded, color: primary, size: 18)
                    : Icon(Icons.circle_outlined, color: isDark ? YLColors.zinc700 : YLColors.zinc300, size: 18),
              ),
              const SizedBox(width: YLSpacing.xs),
              
              // Node Name
              Expanded(
                child: Text(
                  name,
                  style: YLText.body.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected 
                        ? (isDark ? Colors.white : YLColors.zinc900) 
                        : (isDark ? YLColors.zinc300 : YLColors.zinc700),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              const SizedBox(width: YLSpacing.sm),
              
              // Delay Badge (Tappable for single test)
              InkWell(
                onTap: isTesting ? null : onTest,
                borderRadius: BorderRadius.circular(YLRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: YLDelayBadge(delay: delay, testing: isTesting),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(YLRadius.sm),
        border: Border.all(color: color.withOpacity(0.2), width: 0.5),
      ),
      child: Text(
        _label(type, s),
        style: YLText.caption.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
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
      case 'Selector':    return Colors.blue.shade500;
      case 'URLTest':     return YLColors.connected;
      case 'Fallback':    return YLColors.connecting;
      case 'LoadBalance': return Colors.purple.shade500;
      default:            return YLColors.zinc500;
    }
  }
}
