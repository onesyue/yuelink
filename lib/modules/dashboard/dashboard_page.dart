import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../providers/connection_provider.dart';
import '../../providers/core_provider.dart';
import '../../providers/profile_provider.dart';
import '../../shared/app_notifier.dart';
import '../../core/kernel/core_manager.dart';
import '../../services/profile_service.dart';
import '../../theme.dart';
import '../announcements/providers/announcements_providers.dart';
import 'widgets/announcement_banner.dart';
import 'widgets/chart_card.dart';
import 'widgets/exit_ip_card.dart';
import 'widgets/hero_card.dart';
import 'widgets/stats_card.dart';
import 'widgets/subscription_card.dart';

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
        _uptimeNotifier.value = '${h}h ${m}m';
      } else if (m > 0) {
        _uptimeNotifier.value = '${m}m';
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

    // coreHeartbeatProvider is watched globally in _YueLinkAppState so it
    // stays active on all tabs. Traffic/connection streams only needed here.
    if (isRunning) {
      ref.watch(trafficStreamProvider);
      ref.watch(memoryStreamProvider);
      ref.watch(connectionsStreamProvider);
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
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 560;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Mock mode banner ──────────────────────────────────
                if (isMock)
                  Container(
                    color: Colors.amber.withValues(alpha: 0.12),
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
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

                // ── Scrollable content ────────────────────────────────
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await ref
                          .read(authProvider.notifier)
                          .refreshUserInfo();
                      ref.invalidate(announcementsProvider);
                    },
                    child: ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth > 720 + 48
                          ? (constraints.maxWidth - 720) / 2
                          : 24.0,
                      vertical: 24,
                    ),
                    children: [
                      // ── User greeting header ─────────────────────────
                      _DashboardHeader(),

                      const SizedBox(height: 16),

                      // ── Hero card: connect/status ────────────────────
                      HeroCard(
                        status: status,
                        uptimeNotifier: _uptimeNotifier,
                        onToggle: () => _toggle(context, ref),
                      ),

                      // ── Latest announcement (always visible) ────────
                      const SizedBox(height: 12),
                      const AnnouncementBanner(),

                      // ── Running: exit IP, chart, stats ──────────────
                      if (isRunning) ...[
                        const SizedBox(height: 16),
                        if (isWide)
                          SizedBox(
                            height: 190,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: const [
                                Expanded(flex: 1, child: ExitIpCard()),
                                SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child:
                                      RepaintBoundary(child: ChartCard()),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          const ExitIpCard(),
                          const SizedBox(height: 12),
                          const RepaintBoundary(child: ChartCard()),
                        ],
                        const SizedBox(height: 12),
                        const StatsCard(),
                      ],

                      // ── Subscription info ───────────────────────────
                      const SizedBox(height: 16),
                      const SubscriptionCard(),

                      const SizedBox(height: 8),
                    ],
                  ),
                  ),
                ),
              ],
            );
          },
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

// ── Dashboard header: greeting + user email ─────────────────────────────────

class _DashboardHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.watch(userProfileProvider);
    final email = profile?.email;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Brand mark
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isDark ? YLColors.zinc700 : YLColors.zinc100,
            borderRadius: BorderRadius.circular(YLRadius.md),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
          child: Icon(
            Icons.link_rounded,
            size: 16,
            color: isDark ? Colors.white70 : YLColors.zinc700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                email != null ? s.dashGreetingReturning : s.dashGreeting,
                style: YLText.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : YLColors.zinc900,
                ),
              ),
              if (email != null)
                Text(
                  email,
                  style: YLText.caption.copyWith(color: YLColors.zinc400),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
