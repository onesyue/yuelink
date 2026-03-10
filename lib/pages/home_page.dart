import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
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

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mock banner
          if (isMock)
            Container(
              color: Colors.amber.withValues(alpha: 0.12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: Row(
                children: [
                  Icon(Icons.science_outlined,
                      size: 13, color: Colors.amber.shade700),
                  const SizedBox(width: 6),
                  Text(s.mockModeBanner,
                      style: TextStyle(
                          fontSize: 12, color: Colors.amber.shade700)),
                ],
              ),
            ),

          // ── Top bar ──────────────────────────────────────────────
          _TopBar(
            status: status,
            uptimeText: _uptimeText,
            isTransitioning: isTransitioning,
            onToggle: () => _toggle(context, ref),
          ),

          // Divider
          Container(
            height: 0.5,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),

          // ── Main content ─────────────────────────────────────────
          Expanded(
            child: isTransitioning
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Connection card
                            _ConnectionCard(
                              status: status,
                              uptimeText: _uptimeText,
                              onToggle: () => _toggle(context, ref),
                            ),
                            const SizedBox(height: 16),

                            // Traffic card (only when connected)
                            if (isRunning) ...[
                              const _TrafficMetricCard(),
                              const SizedBox(height: 16),
                            ],

                            // Stat cards row
                            if (isRunning) ...[
                              _StatsRow(),
                              const SizedBox(height: 16),
                            ],

                            // Chart card
                            if (isRunning)
                              const _ChartCard(),
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

// ── Top Bar ──────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  final CoreStatus status;
  final String uptimeText;
  final bool isTransitioning;
  final VoidCallback onToggle;

  const _TopBar({
    required this.status,
    required this.uptimeText,
    required this.isTransitioning,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRunning = status == CoreStatus.running;

    // Get delay for badge
    final groups = ref.watch(proxyGroupsProvider);
    final delays = ref.watch(delayResultsProvider);
    final mainGroup = groups.isEmpty
        ? null
        : groups.firstWhere(
            (g) => g.name == '节点选择' || g.type == 'Selector',
            orElse: () => groups.first,
          );
    final currentDelay = mainGroup != null ? delays[mainGroup.now] : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Left: label + title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.dashboardLabel,
                style: YLText.caption.copyWith(
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.w600,
                  color: YLColors.zinc400,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                s.dashboardTitle,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Right: status badge + switch node
          if (isRunning) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF34C759).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF34C759).withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF34C759),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${s.statusConnected}${currentDelay != null && currentDelay > 0 ? ' · ${currentDelay}ms' : ''}',
                    style: YLText.label.copyWith(
                      color: const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => MainShell.switchToTab(context, MainShell.tabNodes),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.10),
                    width: 0.5,
                  ),
                ),
                child: Text(s.switchNode, style: YLText.label),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Connection Card ──────────────────────────────────────────────────────────

class _ConnectionCard extends ConsumerWidget {
  final CoreStatus status;
  final String uptimeText;
  final VoidCallback onToggle;

  const _ConnectionCard({
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

    // Profile name
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final isMock = ref.watch(isMockModeProvider);
    final routingMode = ref.watch(routingModeProvider);
    final systemProxy = ref.watch(systemProxyOnConnectProvider);

    String? profileName;
    if (isMock) {
      profileName = s.mockModeLabel;
    } else {
      profileName = profiles.whenOrNull(
        data: (list) =>
            list.where((p) => p.id == activeId).firstOrNull?.name,
      );
    }

    final routeLabel = routingMode == 'rule'
        ? '${s.routeModeRule} Mode'
        : routingMode == 'global'
            ? '${s.routeModeGlobal} Mode'
            : '${s.routeModeDirect} Mode';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status label
                    Row(
                      children: [
                        Container(
                          width: 7, height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isRunning
                                ? const Color(0xFF34C759)
                                : (isTransitioning
                                    ? YLColors.connecting
                                    : YLColors.zinc400),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isRunning ? s.liveConnection : s.dashDisconnectedTitle,
                          style: YLText.label.copyWith(
                            color: YLColors.zinc500,
                          ),
                        ),
                        if (isRunning && uptimeText.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            uptimeText,
                            style: YLText.caption.copyWith(
                              color: YLColors.zinc400,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Big status text
                    Text(
                      isRunning ? s.statusConnected : s.statusDisconnected,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Description
                    Text(
                      isRunning ? s.dashConnectedDesc : s.dashDisconnectedDesc,
                      style: YLText.body.copyWith(
                        color: YLColors.zinc500,
                        height: 1.5,
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Toggle button
              if (isTransitioning)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                GestureDetector(
                  onTap: onToggle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: isRunning
                          ? (isDark ? Colors.white : YLColors.zinc900)
                          : YLColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isRunning ? s.btnDisconnect : s.btnConnect,
                      style: YLText.label.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // Pills
          if (isRunning) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Pill(routeLabel),
                _Pill(systemProxy ? s.systemProxyOn : s.systemProxyOff),
                if (profileName != null) _Pill(profileName),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  const _Pill(this.label);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.10),
          width: 0.5,
        ),
      ),
      child: Text(label,
          style: YLText.label.copyWith(
            color: isDark ? YLColors.zinc400 : YLColors.zinc600,
          )),
    );
  }
}

// ── Traffic Metric Card ──────────────────────────────────────────────────────

class _TrafficMetricCard extends ConsumerWidget {
  const _TrafficMetricCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final traffic = ref.watch(trafficProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.realtimeTraffic,
              style: YLText.label.copyWith(color: YLColors.zinc500)),
          const SizedBox(height: 16),
          Row(
            children: [
              _BigMetric(
                label: s.trafficDownload,
                value: traffic.downFormatted,
                color: const Color(0xFF34C759),
              ),
              const SizedBox(width: 48),
              _BigMetric(
                label: s.trafficUpload,
                value: traffic.upFormatted,
                color: YLColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BigMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: YLText.label.copyWith(color: YLColors.zinc500)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Stats Row ────────────────────────────────────────────────────────────────

class _StatsRow extends ConsumerStatefulWidget {
  @override
  ConsumerState<_StatsRow> createState() => _StatsRowState();
}

class _StatsRowState extends ConsumerState<_StatsRow> {
  String? _ip;
  String? _country;
  bool _ipLoading = false;
  bool _ipQueried = false;

  Future<void> _queryIp() async {
    if (_ipLoading) return;
    setState(() {
      _ipLoading = true;
      _ip = null;
      _country = null;
    });
    try {
      final client = http.Client();
      try {
        final resp = await client
            .get(Uri.parse('http://ip-api.com/json/?fields=query,country'))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final body = resp.body;
          final qm = RegExp(r'"query"\s*:\s*"([^"]+)"').firstMatch(body);
          final cm =
              RegExp(r'"country"\s*:\s*"([^"]+)"').firstMatch(body);
          if (mounted) {
            setState(() {
              _ip = qm?.group(1);
              _country = cm?.group(1);
              _ipLoading = false;
              _ipQueried = true;
            });
          }
          return;
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    if (mounted) setState(() { _ipLoading = false; _ipQueried = true; });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groups = ref.watch(proxyGroupsProvider);
    final delays = ref.watch(delayResultsProvider);
    final mainGroup = groups.isEmpty
        ? null
        : groups.firstWhere(
            (g) => g.name == '节点选择' || g.type == 'Selector',
            orElse: () => groups.first,
          );
    final routingMode = ref.watch(routingModeProvider);
    final systemProxy = ref.watch(systemProxyOnConnectProvider);

    final routeLabel = routingMode == 'rule'
        ? '${s.routeModeRule} Mode'
        : routingMode == 'global'
            ? '${s.routeModeGlobal} Mode'
            : '${s.routeModeDirect} Mode';

    final nodeValue = mainGroup?.now ?? '—';
    final nodeDelay = mainGroup != null ? delays[mainGroup.now] : null;
    final nodeMeta = nodeDelay != null && nodeDelay > 0
        ? '${nodeDelay}ms · Healthy'
        : 'Unknown delay';

    final ipValue = _ipLoading
        ? s.exitIpQuerying
        : _ipQueried && _ip != null
            ? _ip!
            : _ipQueried
                ? s.exitIpFailed
                : s.exitIpTapToQuery;
    final ipMeta = _country ?? '';

    return Row(
      children: [
        Expanded(
          child: _StatCardCompact(
            title: s.nodeLabel,
            value: nodeValue,
            meta: nodeMeta,
            icon: Icons.public_rounded,
            onTap: () => MainShell.switchToTab(context, MainShell.tabNodes),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCardCompact(
            title: s.exitIpLabel,
            value: ipValue,
            meta: ipMeta,
            icon: Icons.shield_outlined,
            onTap: _queryIp,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCardCompact(
            title: s.routingLabel,
            value: routeLabel,
            meta: systemProxy ? s.systemProxyOn : s.systemProxyOff,
            icon: Icons.alt_route_rounded,
            onTap: () async {
              const modes = ['rule', 'global', 'direct'];
              final next = modes[(modes.indexOf(routingMode) + 1) % modes.length];
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

class _StatCardCompact extends StatelessWidget {
  final String title;
  final String value;
  final String meta;
  final IconData icon;
  final VoidCallback? onTap;

  const _StatCardCompact({
    required this.title,
    required this.value,
    required this.meta,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(YLRadius.xl),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc800 : Colors.white,
          borderRadius: BorderRadius.circular(YLRadius.xl),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: YLText.label.copyWith(color: YLColors.zinc500)),
                Icon(icon, size: 16, color: YLColors.zinc400),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: YLText.titleMedium,
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(meta,
                  style: YLText.caption.copyWith(color: YLColors.zinc400)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Chart Card ───────────────────────────────────────────────────────────────

class _ChartCard extends ConsumerWidget {
  const _ChartCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = ref.watch(trafficHistoryProvider);
    final downHistory = history.downHistory;
    final upHistory = history.upHistory;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.last60s,
                      style: YLText.label.copyWith(color: YLColors.zinc500)),
                  const SizedBox(height: 2),
                  Text(s.trafficActivity,
                      style: YLText.titleMedium),
                ],
              ),
              Row(
                children: [
                  _LegendDot(
                      color: YLColors.primary, label: s.trafficDownload),
                  const SizedBox(width: 16),
                  _LegendDot(
                      color: const Color(0xFF34C759), label: s.trafficUpload),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Chart
          SizedBox(
            height: 200,
            child: downHistory.isEmpty
                ? Center(
                    child: Text('—',
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
            color: Theme.of(context)
                .dividerColor
                .withValues(alpha: 0.3),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  _formatSpeed(value),
                  style: YLText.caption.copyWith(
                    fontSize: 9,
                    color: YLColors.zinc400,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          _buildLine(toSpots(downHistory), YLColors.primary),
          _buildLine(toSpots(upHistory), const Color(0xFF34C759)),
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
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.0),
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
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: YLText.caption.copyWith(color: YLColors.zinc400)),
      ],
    );
  }
}
