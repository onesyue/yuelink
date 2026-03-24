import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../providers/core_provider.dart';
import '../../providers/profile_provider.dart';
import '../../shared/app_notifier.dart';
import '../../core/kernel/core_manager.dart';
import '../../infrastructure/repositories/profile_repository.dart';
import '../../providers/connection_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../theme.dart';
import '../announcements/providers/announcements_providers.dart';
import 'widgets/announcement_banner.dart';
import 'widgets/live_status_card.dart';
import 'widgets/metrics_row.dart';
import 'widgets/hero_card.dart';
import 'widgets/carrier_card.dart';
import 'widgets/subscription_card.dart';
import '../checkin/presentation/checkin_card.dart';
import '../checkin/providers/checkin_provider.dart';
import 'widgets/emby_banner_card.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(coreStatusProvider);
    final isRunning = status == CoreStatus.running;

    // Activate stream providers without triggering Dashboard rebuilds.
    // These are Provider<void> — they only need to be "kept alive" while
    // the core is running. Using ref.listen (not ref.watch) ensures the
    // streams run but don't cause this widget to rebuild every second.
    // coreHeartbeatProvider is watched globally in _YueLinkAppState.
    if (isRunning) {
      ref.listen(trafficStreamProvider, (_, __) {});
      ref.listen(memoryStreamProvider, (_, __) {});
      ref.listen(connectionsStreamProvider, (_, __) {});
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mock mode banner removed — not shown in production/screenshots

                // ── Scrollable content ────────────────────────────────
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await ref
                          .read(authProvider.notifier)
                          .refreshUserInfo();
                      ref.invalidate(announcementsProvider);
                      ref.read(checkinProvider.notifier).refresh();
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

                      // ── Offline banner ─────────────────────────────
                      const _OfflineBanner(),

                      const SizedBox(height: 16),

                      // ── Hero card: connect/status ────────────────────
                      RepaintBoundary(
                        child: HeroCard(
                          status: status,
                          onToggle: () => _toggle(context, ref),
                        ),
                      ),

                      // ── Running: carrier, live status, metrics ───────
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: AnimatedOpacity(
                          opacity: isRunning ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: isRunning
                              ? const Column(
                                  children: [
                                    SizedBox(height: 12),
                                    RepaintBoundary(child: CarrierCard()),
                                    SizedBox(height: 12),
                                    RepaintBoundary(child: LiveStatusCard()),
                                    SizedBox(height: 12),
                                    RepaintBoundary(child: MetricsRow()),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),

                      // ── Announcement ─────────────────────────────────
                      const SizedBox(height: 12),
                      const RepaintBoundary(child: AnnouncementBanner()),

                      // ── 悦视频（有权限时显示）─────────────────────────
                      const SizedBox(height: 12),
                      const RepaintBoundary(child: EmbyBannerCard()),

                      // ── Subscription info ───────────────────────────
                      const SizedBox(height: 12),
                      const RepaintBoundary(child: SubscriptionCard()),

                      // ── Daily check-in ────────────────────────────
                      const SizedBox(height: 12),
                      const RepaintBoundary(child: CheckinCard()),

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

      final config = await ref.read(profileRepositoryProvider).loadConfig(activeId);
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
    final email = ref.watch(userProfileProvider.select((p) => p?.email));

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

// ── Offline banner ──────────────────────────────────────────────────────────

class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);
    if (connectivity != ConnectivityStatus.offline) {
      return const SizedBox.shrink();
    }

    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.orange.withValues(alpha: 0.15)
              : Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(YLRadius.md),
          border: Border.all(
            color: Colors.orange.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 16,
              color: isDark ? Colors.orange[300] : Colors.orange[800],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.noNetworkConnection,
                style: YLText.caption.copyWith(
                  color: isDark ? Colors.orange[300] : Colors.orange[800],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
