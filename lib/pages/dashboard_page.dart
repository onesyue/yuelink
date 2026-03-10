import 'dart:async';

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
import '../theme.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  DateTime? _connectedSince;
  Timer? _uptimeTimer;
  bool _busy = false;

  // IP query state (lifted here so it survives scrolls)
  String? _ip;
  String? _country;
  bool _ipLoading = false;
  bool _ipQueried = false;

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
    final sec = diff.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${sec}s';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }

  Future<void> _queryIp() async {
    if (_ipLoading) return;
    setState(() { _ipLoading = true; _ip = null; _country = null; });
    try {
      final client = http.Client();
      try {
        final resp = await client
            .get(Uri.parse('http://ip-api.com/json/?fields=query,country'))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final body = resp.body;
          final qm = RegExp(r'"query"\s*:\s*"([^"]+)"').firstMatch(body);
          final cm = RegExp(r'"country"\s*:\s*"([^"]+)"').firstMatch(body);
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
        // Reset IP on reconnect
        _ipQueried = false;
        _ip = null;
        _country = null;
      } else if (next == CoreStatus.stopped) {
        _stopUptimeTimer();
      }
    });

    final isWide = MediaQuery.sizeOf(context).width > 640;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mock banner
          if (isMock)
            Container(
              color: Colors.amber.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
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

          // ── Content ───────────────────────────────────────────────
          Expanded(
            child: isTransitioning
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Layer 1: Hero Card ──────────────
                            _HeroCard(
                              status: status,
                              uptimeText: _uptimeText,
                              onToggle: () => _toggle(context, ref),
                            ),

                            // ── Layer 2: Overview (disconnect only) ──
                            if (!isRunning) ...[
                              const SizedBox(height: 16),
                              const _OverviewCard(),
                            ],

                            // ── Layer 3: IP + Chart ───────────
                            if (isRunning) ...[
                              const SizedBox(height: 16),
                              if (isWide)
                                // Desktop: side by side
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Flexible(
                                        flex: 1,
                                        child: _ExitIpCard(
                                          ip: _ip,
                                          country: _country,
                                          isLoading: _ipLoading,
                                          isQueried: _ipQueried,
                                          onQuery: _queryIp,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Flexible(flex: 2, child: _ChartCard()),
                                    ],
                                  ),
                                )
                              else ...[
                                // Mobile: stacked
                                _ExitIpCard(
                                  ip: _ip,
                                  country: _country,
                                  isLoading: _ipLoading,
                                  isQueried: _ipQueried,
                                  onQuery: _queryIp,
                                ),
                                const SizedBox(height: 12),
                                const _ChartCard(),
                              ],
                            ],
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
        MainShell.switchToTab(context, MainShell.tabProfiles);
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

// ═══════════════════════════════════════════════════════════════════════════════
// Layer 1 — Hero Card
// ═══════════════════════════════════════════════════════════════════════════════

class _HeroCard extends ConsumerWidget {
  final CoreStatus status;
  final String uptimeText;
  final VoidCallback onToggle;

  const _HeroCard({
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

    // Active node
    String activeNodeName = s.dashDisconnectedTitle;
    String activeNodeGroup = s.dashDisconnectedDesc;
    if (isRunning) {
      final groups = ref.watch(proxyGroupsProvider);
      if (groups.isNotEmpty) {
        try {
          final mainGroup = groups.firstWhere(
            (g) => g.name == 'PROXIES' || g.name == 'GLOBAL' || g.name == '节点选择' || g.name == 'Proxy',
            orElse: () => groups.firstWhere((g) => g.type == 'Selector', orElse: () => groups.first),
          );
          activeNodeName = mainGroup.now.isNotEmpty ? mainGroup.now : s.directAuto;
          activeNodeGroup = mainGroup.name;
        } catch (_) {
          activeNodeName = s.statusConnected;
          activeNodeGroup = '';
        }
      }
    }

    // Traffic
    final traffic = isRunning ? ref.watch(trafficProvider) : null;

    // Pills data
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final isMock = ref.watch(isMockModeProvider);
    final routingMode = ref.watch(routingModeProvider);

    String? profileName;
    if (isMock) {
      profileName = s.mockModeLabel;
    } else {
      profileName = profiles.whenOrNull(
        data: (list) => list.where((p) => p.id == activeId).firstOrNull?.name,
      );
    }

    final routeLabel = routingMode == 'rule'
        ? s.routeModeRule
        : routingMode == 'global'
            ? s.routeModeGlobal
            : s.routeModeDirect;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isRunning
            ? LinearGradient(
                colors: [
                  YLColors.connected.withValues(alpha: 0.10),
                  YLColors.connected.withValues(alpha: 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isRunning ? null : (isDark ? YLColors.zinc800 : Colors.white),
        borderRadius: BorderRadius.circular(YLRadius.xxl),
        border: Border.all(
          color: isRunning
              ? YLColors.connected.withValues(alpha: 0.25)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08)),
          width: 0.5,
        ),
        boxShadow: YLShadow.hero(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Status + uptime ───────── Power button
          Row(
            children: [
              YLStatusDot(
                color: isRunning
                    ? YLColors.connected
                    : (isTransitioning ? YLColors.connecting : YLColors.zinc400),
                glow: isRunning,
              ),
              const SizedBox(width: 8),
              Text(
                isRunning
                    ? s.statusConnected
                    : (isTransitioning ? s.statusProcessing : s.statusDisconnected),
                style: YLText.label.copyWith(
                  color: isRunning ? YLColors.connected : YLColors.zinc500,
                  fontWeight: FontWeight.w600,
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
              const Spacer(),
              _PowerButton(
                isRunning: isRunning,
                isTransitioning: isTransitioning,
                onTap: onToggle,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Row 2: Node name (tappable → Proxies)
          GestureDetector(
            onTap: isRunning
                ? () => MainShell.switchToTab(context, MainShell.tabProxies)
                : null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    activeNodeName,
                    style: YLText.titleLarge.copyWith(fontSize: 20),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isRunning)
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: YLColors.zinc400),
              ],
            ),
          ),

          // Row 3: Node group
          Text(
            activeNodeGroup,
            style: YLText.caption.copyWith(color: YLColors.zinc500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // Row 4: Inline traffic speed (only when connected)
          if (isRunning && traffic != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.arrow_downward_rounded,
                    size: 13, color: YLColors.connected),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    traffic.downFormatted,
                    style: YLText.mono.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.arrow_upward_rounded,
                    size: 13, color: YLColors.accent),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    traffic.upFormatted,
                    style: YLText.mono.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // Row 5: Pills (routing mode + profile name)
          if (isRunning) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Pill(routeLabel, primary: true),
                if (profileName != null) _Pill(profileName),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  final bool isRunning;
  final bool isTransitioning;
  final VoidCallback onTap;

  const _PowerButton({
    required this.isRunning,
    required this.isTransitioning,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isTransitioning) {
      return const SizedBox(
        width: 44, height: 44,
        child: CupertinoActivityIndicator(radius: 12),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isRunning
              ? YLColors.connected
              : (isDark ? YLColors.zinc700 : YLColors.zinc100),
          border: isRunning
              ? null
              : Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.10),
                  width: 0.5,
                ),
          boxShadow: isRunning
              ? [
                  BoxShadow(
                    color: YLColors.connected.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Icon(
          Icons.power_settings_new_rounded,
          size: 22,
          color: isRunning ? Colors.white : YLColors.zinc400,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool primary;
  const _Pill(this.label, {this.primary = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: primary
            ? (isDark
                ? YLColors.connected.withValues(alpha: 0.12)
                : YLColors.connected.withValues(alpha: 0.08))
            : (isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04)),
      ),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: YLText.caption.copyWith(
            fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
            color: primary
                ? YLColors.connected
                : (isDark ? YLColors.zinc400 : YLColors.zinc600),
          )),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Layer 2 — Overview Card (disconnect state only)
// ═══════════════════════════════════════════════════════════════════════════════

class _OverviewCard extends ConsumerWidget {
  const _OverviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final autoConnect = ref.watch(autoConnectProvider);

    String? profileName;
    String? lastUpdated;
    profiles.whenData((list) {
      final active = list.where((p) => p.id == activeId).firstOrNull;
      if (active != null) {
        profileName = active.name;
        if (active.lastUpdated != null) {
          final dt = active.lastUpdated!;
          lastUpdated = '${dt.month}/${dt.day} '
              '${dt.hour.toString().padLeft(2, '0')}:'
              '${dt.minute.toString().padLeft(2, '0')}';
        }
      }
    });

    final hasProfile = profileName != null;

    return Container(
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
        boxShadow: YLShadow.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile row
          Row(
            children: [
              Icon(
                hasProfile ? Icons.description_outlined : Icons.warning_amber_rounded,
                size: 14,
                color: hasProfile ? YLColors.zinc400 : YLColors.connecting,
              ),
              const SizedBox(width: 6),
              Text(
                s.navProfile,
                style: YLText.caption.copyWith(color: YLColors.zinc500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            profileName ?? s.dashNoProfileHint,
            style: hasProfile
                ? YLText.titleMedium.copyWith(fontSize: 14)
                : YLText.body.copyWith(fontSize: 13, color: YLColors.zinc500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          if (lastUpdated != null) ...[
            const SizedBox(height: 2),
            Text(
              s.updatedAt(lastUpdated!),
              style: YLText.caption.copyWith(color: YLColors.zinc400),
            ),
          ],

          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 12),

          // Status pills
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _OverviewPill(
                icon: Icons.bolt_rounded,
                label: autoConnect ? s.dashAutoConnectOn : s.dashAutoConnectOff,
                isDark: isDark,
              ),
              if (hasProfile)
                _OverviewPill(
                  icon: Icons.check_circle_outline,
                  label: s.dashReadyHint.split('.').first,
                  isDark: isDark,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _OverviewPill({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YLRadius.pill),
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: YLColors.zinc400),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YLText.caption.copyWith(
                  fontSize: 11,
                  color: isDark ? YLColors.zinc400 : YLColors.zinc600,
                )),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Layer 3 — Exit IP + Chart
// ═══════════════════════════════════════════════════════════════════════════════

class _ExitIpCard extends StatelessWidget {
  final String? ip;
  final String? country;
  final bool isLoading;
  final bool isQueried;
  final VoidCallback onQuery;

  const _ExitIpCard({
    required this.ip,
    required this.country,
    required this.isLoading,
    required this.isQueried,
    required this.onQuery,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine display state
    String displayValue;
    String displayMeta = '';
    IconData icon = Icons.shield_outlined;
    Color iconColor = YLColors.zinc400;

    if (isLoading) {
      displayValue = s.exitIpQuerying;
    } else if (isQueried && ip != null) {
      displayValue = ip!;
      displayMeta = country ?? '';
      icon = Icons.shield_rounded;
      iconColor = YLColors.connected;
    } else if (isQueried) {
      displayValue = s.exitIpFailed;
      icon = Icons.shield_outlined;
      iconColor = YLColors.error;
    } else {
      displayValue = s.exitIpTapToQuery;
    }

    return InkWell(
      onTap: isLoading ? null : onQuery,
      borderRadius: BorderRadius.circular(YLRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc800 : Colors.white,
          borderRadius: BorderRadius.circular(YLRadius.lg),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: YLShadow.card(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 6),
                Text(s.exitIpLabel,
                    style: YLText.caption.copyWith(color: YLColors.zinc500)),
              ],
            ),
            const SizedBox(height: 8),
            if (isLoading)
              const SizedBox(
                width: 14, height: 14,
                child: CupertinoActivityIndicator(radius: 7),
              )
            else
              Text(
                displayValue,
                style: YLText.titleMedium.copyWith(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (displayMeta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(displayMeta,
                  style: YLText.caption.copyWith(color: YLColors.zinc400)),
            ],
          ],
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(s.trafficActivity,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YLText.caption.copyWith(color: YLColors.zinc500)),
              ),
              const SizedBox(width: 8),
              _LegendDot(color: YLColors.accent, label: '↓'),
              const SizedBox(width: 10),
              _LegendDot(color: YLColors.connected, label: '↑'),
            ],
          ),
          const SizedBox(height: 12),
          // Chart
          SizedBox(
            height: 120,
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

  Widget _buildChart(BuildContext context, List<double> down,
      List<double> up, double p90) {
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
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  _fmtSpeed(value),
                  style: YLText.caption.copyWith(fontSize: 9, color: YLColors.zinc400),
                );
              },
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          _line(toSpots(down), YLColors.accent),
          _line(toSpots(up), YLColors.connected),
        ],
      ),
      duration: const Duration(milliseconds: 100),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.25,
      color: color,
      barWidth: 1.5,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  static String _fmtSpeed(double bps) {
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
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(label, style: YLText.caption.copyWith(color: YLColors.zinc400)),
      ],
    );
  }
}
