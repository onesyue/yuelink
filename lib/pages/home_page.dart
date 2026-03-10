import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../providers/core_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/proxy_provider.dart';
import '../services/app_notifier.dart';
import '../services/core_manager.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  DateTime? _connectedSince;
  Timer? _uptimeTimer;
  bool _busy = false;

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    super.dispose();
  }

  void _startUptimeTimer() {
    _connectedSince = DateTime.now();
    _uptimeTimer?.cancel();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopUptimeTimer() {
    _uptimeTimer?.cancel();
    _uptimeTimer = null;
    _connectedSince = null;
  }

  String get _uptimeText {
    if (_connectedSince == null) return '';
    final diff = DateTime.now().difference(_connectedSince!);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final status = ref.watch(coreStatusProvider);
    final isMock = ref.watch(isMockModeProvider);
    final isRunning = status == CoreStatus.running;
    final isTransitioning =
        status == CoreStatus.starting || status == CoreStatus.stopping;

    if (isRunning) {
      ref.watch(trafficStreamProvider);
      ref.watch(memoryStreamProvider);
      ref.watch(coreHeartbeatProvider);
    }

    ref.listen(coreStatusProvider, (prev, next) {
      if (next == CoreStatus.running) {
        _startUptimeTimer();
      } else if (next == CoreStatus.stopped) {
        _stopUptimeTimer();
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (isMock)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.science_outlined,
                          size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 6),
                      Text(s.mockModeBanner,
                          style: TextStyle(
                              fontSize: 12, color: Colors.amber.shade700)),
                    ],
                  ),
                ),

              const Spacer(),

              _StatusOrb(
                  isRunning: isRunning, isTransitioning: isTransitioning),
              const SizedBox(height: 24),

              Text(
                isTransitioning
                    ? (status == CoreStatus.starting
                        ? s.statusConnecting
                        : s.statusDisconnecting)
                    : (isRunning ? s.statusConnected : s.statusDisconnected),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isRunning
                          ? Colors.green
                          : Theme.of(context).colorScheme.onSurface,
                    ),
              ),

              if (isRunning && _connectedSince != null) ...[
                const SizedBox(height: 4),
                Text(_uptimeText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant)),
              ],

              const SizedBox(height: 8),

              if (isRunning) ...[
                _ActiveNodeInfo(),
                const SizedBox(height: 6),
                _ActiveProfileName(),
              ],

              if (!isRunning && !isTransitioning) _DisconnectedHint(),

              const SizedBox(height: 16),

              // Routing mode switcher
              _RoutingModeSwitcher(isRunning: isRunning),

              const SizedBox(height: 16),

              if (isRunning) ...[
                const RepaintBoundary(child: _TrafficChart()),
                const SizedBox(height: 8),
                const _TrafficCard(),
                const SizedBox(height: 8),
              ],
              const _DailyTrafficCard(),

              const Spacer(),

              SizedBox(
                width: 200,
                height: 56,
                child: FilledButton(
                  onPressed:
                      isTransitioning ? null : () => _toggle(context, ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: isRunning
                        ? Colors.red.shade400
                        : Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isTransitioning)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                        ),
                      Text(
                        isTransitioning
                            ? (status == CoreStatus.starting
                                ? s.btnConnecting
                                : s.btnDisconnecting)
                            : (isRunning ? s.btnDisconnect : s.btnConnect),
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  void _showRollbackDialog(S s, String lastGoodConfig) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.rollbackTitle),
        content: Text(s.rollbackContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await ref
                  .read(coreActionsProvider)
                  .start(lastGoodConfig);
              if (ok) {
                AppNotifier.success(s.rollbackSuccess);
              } else {
                AppNotifier.error(s.rollbackFailed);
              }
            },
            child: Text(s.rollbackConfirm),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    if (_busy) return;
    _busy = true;

    final s = S.of(context);
    final actions = ref.read(coreActionsProvider);
    final status = ref.read(coreStatusProvider);
    final isMock = ref.read(isMockModeProvider);

    HapticFeedback.mediumImpact();

    try {
      if (status == CoreStatus.running) {
        await actions.stop();
        return;
      }

      if (isMock) {
        await actions.start('');
        return;
      }

      final activeId = ref.read(activeProfileIdProvider);
      if (activeId == null) {
        AppNotifier.warning(s.snackNoProfile);
        return;
      }

      final config = await ProfileService.loadConfig(activeId);
      if (config == null) {
        AppNotifier.warning(s.snackConfigMissing);
        return;
      }

      final ok = await actions.start(config);
      if (!ok && mounted) {
        AppNotifier.error(s.snackStartFailed);
        // Offer rollback to last known-good config
        final lastGood =
            await CoreManager.instance.loadLastWorkingConfig();
        if (lastGood != null && lastGood != config && mounted) {
          _showRollbackDialog(s, lastGood);
        }
      }
    } finally {
      _busy = false;
    }
  }
}

// ── Routing Mode Switcher ─────────────────────────────────────────────────────

class _RoutingModeSwitcher extends ConsumerWidget {
  final bool isRunning;
  const _RoutingModeSwitcher({required this.isRunning});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final mode = ref.watch(routingModeProvider);

    return SegmentedButton<String>(
      segments: [
        ButtonSegment(
            value: 'rule',
            label: Text(s.routeModeRule),
            icon: const Icon(Icons.rule, size: 16)),
        ButtonSegment(
            value: 'global',
            label: Text(s.routeModeGlobal),
            icon: const Icon(Icons.public, size: 16)),
        ButtonSegment(
            value: 'direct',
            label: Text(s.routeModeDirect),
            icon: const Icon(Icons.wifi_tethering, size: 16)),
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
    );
  }
}

// ── Traffic Chart ─────────────────────────────────────────────────────────────

class _TrafficChart extends ConsumerWidget {
  const _TrafficChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(trafficHistoryProvider);
    final downHistory = history.downHistory;
    final upHistory = history.upHistory;

    if (downHistory.isEmpty) return const SizedBox.shrink();

    // Use 90th-percentile as Y-axis ceiling to prevent a single traffic spike
    // from compressing all other data into a flat line.
    final p90 = history.p90;
    final maxY = p90 > 0 ? p90 * 1.5 : 1024 * 1024.0;

    List<FlSpot> toSpots(List<double> data) => data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return SizedBox(
      height: 80,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: toSpots(downHistory),
              isCurved: true,
              color: Colors.green,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.green.withValues(alpha: 0.1),
              ),
            ),
            LineChartBarData(
              spots: toSpots(upHistory),
              isCurved: true,
              color: Colors.blue,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.blue.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 100),
      ),
    );
  }
}

// ── Other widgets ─────────────────────────────────────────────────────────────

class _ActiveNodeInfo extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(proxyGroupsProvider);
    final mainGroup = groups.isEmpty
        ? null
        : groups.firstWhere(
            (g) => g.name == '节点选择' || g.type == 'Selector',
            orElse: () => groups.first,
          );

    if (mainGroup == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.near_me,
              size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(mainGroup.now,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ActiveProfileName extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isMock = ref.watch(isMockModeProvider);
    if (isMock) {
      return Text(s.mockModeLabel,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final name = profiles.whenOrNull(
      data: (list) =>
          list.where((p) => p.id == activeId).firstOrNull?.name,
    );
    if (name == null) return const SizedBox.shrink();
    return Text(name,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}

class _DisconnectedHint extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final isMock = ref.watch(isMockModeProvider);

    if (isMock) {
      return Text(s.mockHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant));
    }

    return profiles.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(s.noProfileHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant)),
          );
        }
        final active =
            list.where((p) => p.id == activeId).firstOrNull ?? list.first;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(active.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant)),
            ],
          ),
        );
      },
    );
  }
}

class _StatusOrb extends StatelessWidget {
  final bool isRunning;
  final bool isTransitioning;

  const _StatusOrb({required this.isRunning, required this.isTransitioning});

  @override
  Widget build(BuildContext context) {
    final color = isTransitioning
        ? Colors.orange
        : isRunning
            ? Colors.green
            : Theme.of(context).colorScheme.outline;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 3),
        boxShadow: isRunning
            ? [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.3),
                  blurRadius: 24,
                  spreadRadius: 4,
                )
              ]
            : null,
      ),
      child: Icon(
        isRunning ? Icons.power_settings_new : Icons.power_off_outlined,
        size: 48,
        color: color,
      ),
    );
  }
}

class _TrafficCard extends ConsumerWidget {
  const _TrafficCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final traffic = ref.watch(trafficProvider);
    final memoryBytes = ref.watch(memoryUsageProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TrafficColumn(
              icon: Icons.arrow_upward,
              iconColor: Colors.blue,
              value: traffic.upFormatted,
              label: s.trafficUpload,
            ),
            const SizedBox(width: 36),
            _TrafficColumn(
              icon: Icons.arrow_downward,
              iconColor: Colors.green,
              value: traffic.downFormatted,
              label: s.trafficDownload,
            ),
            if (memoryBytes > 0) ...[
              const SizedBox(width: 36),
              _TrafficColumn(
                icon: Icons.memory,
                iconColor: Colors.orange,
                value: _formatMemory(memoryBytes),
                label: s.trafficMemory,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatMemory(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _TrafficColumn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _TrafficColumn({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ── Daily traffic summary ─────────────────────────────────────────────────────

class _DailyTrafficCard extends ConsumerWidget {
  const _DailyTrafficCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final (upTotal, downTotal) = ref.watch(dailyTrafficProvider);

    if (upTotal == 0 && downTotal == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            s.todayUsage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          const Icon(Icons.arrow_upward, size: 12, color: Colors.blue),
          const SizedBox(width: 3),
          Text(_fmt(upTotal),
              style: const TextStyle(fontSize: 12, color: Colors.blue)),
          const SizedBox(width: 14),
          const Icon(Icons.arrow_downward, size: 12, color: Colors.green),
          const SizedBox(width: 3),
          Text(_fmt(downTotal),
              style: const TextStyle(fontSize: 12, color: Colors.green)),
        ],
      ),
    );
  }

  String _fmt(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
