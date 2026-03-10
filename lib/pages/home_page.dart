import 'dart:async';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_strings.dart';
import '../main.dart';
import '../providers/core_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/proxy_provider.dart';
import '../services/app_notifier.dart';
import '../services/core_manager.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';

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
    if (_connectedSince == null) return '00:00';
    final diff = DateTime.now().difference(_connectedSince!);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final status = ref.watch(coreStatusProvider);
    final isMock = ref.watch(isMockModeProvider);
    final isRunning = status == CoreStatus.running;
    final isTransitioning =
        status == CoreStatus.starting || status == CoreStatus.stopping;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // Mock banner
          if (isMock)
            SliverToBoxAdapter(
              child: Container(
                color: YLColors.connecting.withOpacity(0.08),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.science_outlined,
                        size: 13, color: YLColors.connecting),
                    const SizedBox(width: 6),
                    Text(s.mockModeBanner,
                        style: YLText.caption.copyWith(
                          color: YLColors.connecting,
                          fontWeight: FontWeight.w500,
                        )),
                  ],
                ),
              ),
            ),

          // Content
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 80),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Hero Section ───────────────────────────────
                      _HeroSection(
                        status: status,
                        uptimeText: _uptimeText,
                        onToggle: () => _toggle(context, ref),
                      ),
                      const SizedBox(height: 24),

                      // ── Quick Info Row ─────────────────────────────
                      if (isRunning) ...[
                        _QuickInfoRow(),
                        const SizedBox(height: 16),
                      ],

                      // ── Traffic Cards ──────────────────────────────
                      if (isRunning) ...[
                        const _TrafficCards(),
                        const SizedBox(height: 16),
                      ],

                      // ── Chart ──────────────────────────────────────
                      if (isRunning) const _ChartCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
              final ok =
                  await ref.read(coreActionsProvider).start(lastGoodConfig);
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
        final lastGood = await CoreManager.instance.loadLastWorkingConfig();
        if (lastGood != null && lastGood != config && mounted) {
          _showRollbackDialog(s, lastGood);
        }
      }
    } finally {
      _busy = false;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Hero Section — Large power button + status
// ══════════════════════════════════════════════════════════════════════════════

class _HeroSection extends ConsumerWidget {
  final CoreStatus status;
  final String uptimeText;
  final VoidCallback onToggle;

  const _HeroSection({
    required this.status,
    required this.uptimeText,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRunning = status == CoreStatus.running;
    final isTransitioning =
        status == CoreStatus.starting || status == CoreStatus.stopping;

    // Profile info
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final isMock = ref.watch(isMockModeProvider);
    String? profileName;
    if (isMock) {
      profileName = s.mockModeLabel;
    } else {
      profileName = profiles.whenOrNull(
        data: (list) =>
            list.where((p) => p.id == activeId).firstOrNull?.name,
      );
    }

    // Active node
    final groups = ref.watch(proxyGroupsProvider);
    String activeNode = '';
    if (isRunning && groups.isNotEmpty) {
      try {
        final mainGroup = groups.firstWhere(
          (g) => g.type.toLowerCase() == 'selector',
          orElse: () => groups.first,
        );
        activeNode = mainGroup.now;
      } catch (_) {}
    }

    final statusColor = isRunning
        ? YLColors.connected
        : isTransitioning
            ? YLColors.connecting
            : YLColors.zinc400;

    return YLSurface(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          // ── Power Button ───────────────────────────────────────
          GestureDetector(
            onTap: isTransitioning ? null : onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRunning
                    ? YLColors.connected
                    : (isDark ? YLColors.zinc800 : YLColors.zinc100),
                boxShadow: isRunning
                    ? [
                        BoxShadow(
                          color: YLColors.connected.withOpacity(0.35),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              child: Center(
                child: isTransitioning
                    ? const CupertinoActivityIndicator(
                        color: Colors.white, radius: 14)
                    : Icon(
                        Icons.power_settings_new_rounded,
                        size: 36,
                        color: isRunning
                            ? Colors.white
                            : (isDark ? YLColors.zinc500 : YLColors.zinc400),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Status ─────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              YLStatusDot(color: statusColor, glow: isRunning, size: 8),
              const SizedBox(width: 8),
              Text(
                isRunning
                    ? s.statusConnected
                    : isTransitioning
                        ? (status == CoreStatus.starting
                            ? s.statusConnecting
                            : s.statusDisconnecting)
                        : s.statusDisconnected,
                style: YLText.titleMedium.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Timer / Profile ────────────────────────────────────
          if (isRunning) ...[
            Text(
              uptimeText,
              style: YLText.display.copyWith(
                fontSize: 36,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isDark ? Colors.white : YLColors.zinc900,
              ),
            ),
            const SizedBox(height: 8),
            if (activeNode.isNotEmpty)
              Text(
                activeNode,
                style: YLText.body.copyWith(color: YLColors.zinc500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ] else ...[
            Text(
              s.dashDisconnectedDesc,
              style: YLText.body.copyWith(color: YLColors.zinc400),
              textAlign: TextAlign.center,
            ),
          ],

          // ── Profile & Route pills ──────────────────────────────
          if (isRunning) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (profileName != null)
                  _InfoPill(Icons.description_outlined, profileName),
                _InfoPill(Icons.alt_route_rounded,
                    ref.watch(routingModeProvider).toUpperCase()),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YLRadius.pill),
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.04),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: YLColors.zinc400),
          const SizedBox(width: 5),
          Text(label,
              style: YLText.caption.copyWith(
                color: YLColors.zinc500,
                fontWeight: FontWeight.w500,
              )),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Quick Info Row
// ══════════════════════════════════════════════════════════════════════════════

class _QuickInfoRow extends ConsumerStatefulWidget {
  @override
  ConsumerState<_QuickInfoRow> createState() => _QuickInfoRowState();
}

class _QuickInfoRowState extends ConsumerState<_QuickInfoRow> {
  String? _ip;
  bool _ipLoading = false;

  Future<void> _queryIp() async {
    if (_ipLoading) return;
    setState(() => _ipLoading = true);
    try {
      final client = http.Client();
      try {
        final resp = await client
            .get(Uri.parse('http://ip-api.com/json/?fields=query,country'))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final qm = RegExp(r'"query"\s*:\s*"([^"]+)"').firstMatch(resp.body);
          if (mounted) setState(() => _ip = qm?.group(1) ?? '?');
        }
      } finally {
        client.close();
      }
    } catch (_) {
      if (mounted) setState(() => _ip = 'Error');
    }
    if (mounted) setState(() => _ipLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final groups = ref.watch(proxyGroupsProvider);
    final delays = ref.watch(delayResultsProvider);

    int? nodeDelay;
    if (groups.isNotEmpty) {
      try {
        final mainGroup = groups.firstWhere(
          (g) => g.type.toLowerCase() == 'selector',
          orElse: () => groups.first,
        );
        nodeDelay = delays[mainGroup.now];
      } catch (_) {}
    }

    return Row(
      children: [
        Expanded(
          child: _MiniCard(
            icon: Icons.speed_rounded,
            label: s.exitIpLabel,
            value: _ipLoading
                ? '...'
                : _ip ?? s.exitIpTapToQuery,
            onTap: _queryIp,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniCard(
            icon: Icons.timer_outlined,
            label: 'Latency',
            value: nodeDelay != null && nodeDelay > 0
                ? '${nodeDelay}ms'
                : '—',
            onTap: () => MainShell.switchToTab(context, MainShell.tabNodes),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniCard(
            icon: Icons.alt_route_rounded,
            label: 'Mode',
            value: ref.watch(routingModeProvider).toUpperCase(),
            onTap: () async {
              final mode = ref.read(routingModeProvider);
              const modes = ['rule', 'global', 'direct'];
              final next = modes[(modes.indexOf(mode) + 1) % modes.length];
              ref.read(routingModeProvider.notifier).state = next;
              await SettingsService.setRoutingMode(next);
              try {
                await ref.read(mihomoApiProvider).setRoutingMode(next);
              } catch (_) {}
            },
          ),
        ),
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _MiniCard({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return YLSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: YLColors.zinc400),
          const SizedBox(height: 10),
          Text(value,
              style: YLText.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: YLText.caption.copyWith(color: YLColors.zinc400)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Traffic Cards
// ══════════════════════════════════════════════════════════════════════════════

class _TrafficCards extends ConsumerWidget {
  const _TrafficCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final traffic = ref.watch(trafficProvider);

    return Row(
      children: [
        Expanded(
          child: YLSurface(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: YLColors.connected.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_downward_rounded,
                      size: 18, color: YLColors.connected),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.trafficDownload,
                        style: YLText.caption.copyWith(color: YLColors.zinc400)),
                    const SizedBox(height: 2),
                    Text(
                      traffic.downFormatted,
                      style: YLText.titleMedium.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: YLSurface(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: YLColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_upward_rounded,
                      size: 18, color: YLColors.primary),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.trafficUpload,
                        style: YLText.caption.copyWith(color: YLColors.zinc400)),
                    const SizedBox(height: 2),
                    Text(
                      traffic.upFormatted,
                      style: YLText.titleMedium.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Chart Card
// ══════════════════════════════════════════════════════════════════════════════

class _ChartCard extends ConsumerWidget {
  const _ChartCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final history = ref.watch(trafficHistoryProvider);
    final downHistory = history.downHistory;
    final upHistory = history.upHistory;

    return YLSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(s.trafficActivity, style: YLText.titleMedium),
              Row(
                children: [
                  _LegendDot(color: YLColors.primary, label: s.trafficDownload),
                  const SizedBox(width: 14),
                  _LegendDot(
                      color: YLColors.connected, label: s.trafficUpload),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: downHistory.isEmpty
                ? Center(
                    child: Text('Waiting for data...',
                        style: YLText.body.copyWith(color: YLColors.zinc400)),
                  )
                : _buildChart(context, downHistory, upHistory, history.p90),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<double> downHistory,
      List<double> upHistory, double p90) {
    final maxY = p90 > 0 ? p90 * 1.5 : 1024 * 1024.0;

    List<FlSpot> toSpots(List<double> data) => data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 3,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Theme.of(context).dividerColor.withOpacity(0.2),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          show: true,
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  _formatSpeed(value),
                  style: YLText.caption
                      .copyWith(fontSize: 9, color: YLColors.zinc400),
                );
              },
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          _buildLine(toSpots(downHistory), YLColors.primary),
          _buildLine(toSpots(upHistory), YLColors.connected),
        ],
      ),
      duration: const Duration(milliseconds: 100),
    );
  }

  LineChartBarData _buildLine(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.25,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  String _formatSpeed(double bps) {
    if (bps < 1024) return '${bps.toStringAsFixed(0)}B';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(0)}K';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)}M';
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: color,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: YLText.caption.copyWith(color: YLColors.zinc400)),
      ],
    );
  }
}
