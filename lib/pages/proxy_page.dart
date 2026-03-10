import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/proxy.dart';
import '../providers/core_provider.dart';
import '../providers/proxy_provider.dart';
import '../services/settings_service.dart';

class ProxyPage extends ConsumerStatefulWidget {
  const ProxyPage({super.key});

  @override
  ConsumerState<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends ConsumerState<ProxyPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(proxyGroupsProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final groups = ref.watch(proxyGroupsProvider);
    final status = ref.watch(coreStatusProvider);

    if (status != CoreStatus.running) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_outlined,
                  size: 48,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(s.notConnectedHintProxy,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant)),
            ],
          ),
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

    return Scaffold(
      body: Column(
        children: [
          // Routing mode bar
          _RoutingModeBar(),

          Divider(
            height: 1,
            thickness: 0.5,
            color: Theme.of(context).dividerColor,
          ),

          // Group list
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.read(proxyGroupsProvider.notifier).refresh(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                itemCount: groups.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _ProxyGroupCard(group: groups[index]),
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
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              await ref
                  .read(mihomoApiProvider)
                  .setRoutingMode(newMode);
            } catch (_) {}
          }
        },
      ),
    );
  }
}

// ── Proxy Group Card ──────────────────────────────────────────────────────────

class _ProxyGroupCard extends ConsumerWidget {
  final ProxyGroup group;
  const _ProxyGroupCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final delays = ref.watch(delayResultsProvider);
    final testing = ref.watch(delayTestingProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF2C2C2E)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Group header ───────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Icon(_groupIcon(group.name),
                    size: 14,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(group.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                _TypeChip(type: group.type),
                const SizedBox(width: 4),
                Text(
                  group.now,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const Spacer(),
                // Test all button
                InkWell(
                  onTap: testing.isNotEmpty
                      ? null
                      : () => ref
                          .read(delayTestProvider)
                          .testGroup(group.name, group.all),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: testing.isNotEmpty
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bolt_rounded, size: 13),
                              const SizedBox(width: 2),
                              Text(s.testAll,
                                  style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),

          // ── Node grid ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossCount =
                    max(2, (constraints.maxWidth / 130).floor());
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 2.4,
                  ),
                  itemCount: group.all.length,
                  itemBuilder: (context, index) {
                    final name = group.all[index];
                    return _NodeCard(
                      name: name,
                      isSelected: name == group.now,
                      delay: delays[name],
                      isTesting: testing.contains(name),
                      onSelect: () => ref
                          .read(proxyGroupsProvider.notifier)
                          .changeProxy(group.name, name),
                      onTest: () => ref
                          .read(delayTestProvider)
                          .testDelay(name),
                    );
                  },
                );
              },
            ),
          ),

          // Node count row
          Padding(
            padding:
                const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              s.nodesCount(group.all.length, group.all.length),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
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
    if (n.contains('ai') || n.contains('openai') || n.contains('claude')) {
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
    if (n.contains('游戏') || n.contains('game') || n.contains('steam')) {
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

// ── Node Card ─────────────────────────────────────────────────────────────────

class _NodeCard extends StatelessWidget {
  final String name;
  final bool isSelected;
  final int? delay;
  final bool isTesting;
  final VoidCallback onSelect;
  final VoidCallback onTest;

  const _NodeCard({
    required this.name,
    required this.isSelected,
    required this.delay,
    required this.isTesting,
    required this.onSelect,
    required this.onTest,
  });

  Color _delayColor(int d) {
    if (d <= 0) return Colors.red;
    if (d < 100) return const Color(0xFF34C759);
    if (d < 300) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.07)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.grey.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: isSelected
                ? primary.withValues(alpha: 0.65)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.08)),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Node name
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? primary
                    : Theme.of(context).colorScheme.onSurface,
                height: 1.3,
              ),
            ),

            // Delay
            GestureDetector(
              onTap: onTest,
              child: isTesting
                  ? const SizedBox(
                      width: 10,
                      height: 10,
                      child:
                          CircularProgressIndicator(strokeWidth: 1.5))
                  : delay != null
                      ? Text(
                          delay! <= 0 ? 'timeout' : '${delay}ms',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _delayColor(delay!),
                          ),
                        )
                      : Icon(Icons.speed_outlined,
                          size: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.5)),
            ),
          ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _typeColor(type).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        _typeLabel(type, s),
        style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: _typeColor(type)),
      ),
    );
  }

  String _typeLabel(String type, S s) {
    switch (type) {
      case 'Selector':
        return s.typeManual;
      case 'URLTest':
        return s.typeAuto;
      case 'Fallback':
        return s.typeFallback;
      case 'LoadBalance':
        return s.typeLoadBalance;
      default:
        return type;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'Selector':
        return Colors.blue;
      case 'URLTest':
        return Colors.green;
      case 'Fallback':
        return Colors.orange;
      case 'LoadBalance':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
