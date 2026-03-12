import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../main.dart';
import '../../providers/connection_provider.dart';
import '../../providers/core_provider.dart';
import '../../providers/profile_provider.dart';
import '../../shared/app_notifier.dart';
import '../../core/kernel/core_manager.dart';
import '../../services/profile_service.dart';
import 'providers/dashboard_providers.dart';
import 'widgets/chart_card.dart';
import 'widgets/exit_ip_card.dart';
import 'widgets/hero_card.dart';
import 'widgets/overview_card.dart';
import 'widgets/stats_card.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  DateTime? _connectedSince;
  Timer? _uptimeTimer;
  final _uptimeNotifier = ValueNotifier<String>('');
  bool _busy = false;

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    _uptimeNotifier.dispose();
    super.dispose();
  }

  void _startUptimeTimer() {
    _connectedSince = DateTime.now();
    _uptimeNotifier.value = '';
    _uptimeTimer?.cancel();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedSince == null) return;
      final diff = DateTime.now().difference(_connectedSince!);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      final sec = diff.inSeconds % 60;
      if (h > 0) {
        _uptimeNotifier.value = '${h}h ${m}m ${sec}s';
      } else if (m > 0) {
        _uptimeNotifier.value = '${m}m ${sec}s';
      } else {
        _uptimeNotifier.value = '${sec}s';
      }
    });
  }

  void _stopUptimeTimer() {
    _uptimeTimer?.cancel();
    _uptimeTimer = null;
    _connectedSince = null;
    _uptimeNotifier.value = '';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final status = ref.watch(coreStatusProvider);
    final isMock = ref.watch(isMockModeProvider);
    final isRunning = status == CoreStatus.running;

    if (isRunning) {
      ref.watch(trafficStreamProvider);
      ref.watch(memoryStreamProvider);
      ref.watch(coreHeartbeatProvider);
      ref.watch(connectionsStreamProvider);
    }

    ref.listen(coreStatusProvider, (prev, next) {
      if (next == CoreStatus.running) {
        _startUptimeTimer();
        // Reset then auto-query exit IP; isLoading guard in query() prevents duplicates
        ref.read(exitIpProvider.notifier).reset();
        ref.read(exitIpProvider.notifier).query();
      } else if (next == CoreStatus.stopped) {
        _stopUptimeTimer();
        // Keep last IP visible after disconnect — user can see where they were connected
      }
    });

    final isWide = MediaQuery.sizeOf(context).width > 640;

    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mock banner
          if (isMock)
            Container(
              color: Colors.amber.withValues(alpha: 0.12),
              padding: EdgeInsets.fromLTRB(16, topPadding + 5, 16, 5),
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
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, isMock ? 24 : topPadding + 24, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Layer 1: Hero Card ──────────────
                      HeroCard(
                        status: status,
                        uptimeNotifier: _uptimeNotifier,
                        onToggle: () => _toggle(context, ref),
                      ),

                      // ── Layer 2: IP + Chart (running only) ──
                      if (isRunning) ...[
                        const SizedBox(height: 16),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Flexible(
                                flex: 1,
                                child: ExitIpCard(),
                              ),
                              const SizedBox(width: 12),
                              const Flexible(flex: 2, child: RepaintBoundary(child: ChartCard())),
                            ],
                          )
                        else ...[
                          const ExitIpCard(),
                          const SizedBox(height: 12),
                          const RepaintBoundary(child: ChartCard()),
                        ],
                        // ── Layer 3: Today stats ──────────
                        const SizedBox(height: 12),
                        const StatsCard(),
                      ],

                      // ── Layer 4: Overview (always visible) ──
                      // Shows active profile, auto-connect status, readiness.
                      // Visible in both connected and disconnected states.
                      const SizedBox(height: 16),
                      const OverviewCard(),
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
