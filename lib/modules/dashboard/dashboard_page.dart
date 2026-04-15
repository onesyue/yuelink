import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/settings_service.dart';
import '../../i18n/app_strings.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../core/providers/core_provider.dart';
import '../profiles/providers/profiles_providers.dart';
import '../../shared/app_notifier.dart';
import '../../core/kernel/core_manager.dart';
import '../../infrastructure/repositories/profile_repository.dart';
import '../connections/providers/connections_providers.dart';
import '../../theme.dart';
import '../announcements/providers/announcements_providers.dart';
import 'widgets/live_status_card.dart';
import 'widgets/metrics_row.dart';
import 'widgets/carrier_card.dart';
import '../checkin/presentation/checkin_card.dart';
import '../checkin/providers/checkin_provider.dart';
import 'widgets/hero_card.dart';
import 'widgets/quick_actions.dart';
import '../mine/widgets/notices_card.dart';
import 'widgets/emby_preview_row.dart';
import 'widgets/stale_subscription_banner.dart';
import 'widgets/scene_preset_bar.dart';
import '../../shared/nps_service.dart';
import '../../shared/widgets/nps_sheet.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _busy = false;
  bool _npsChecked = false;

  @override
  void initState() {
    super.initState();
    // NPS trigger — delayed so we don't block first-frame paint, and
    // only after the user is idle on the dashboard. Guarded so we ask
    // at most once per launch.
    Future<void>.delayed(const Duration(seconds: 5), () async {
      if (!mounted || _npsChecked) return;
      _npsChecked = true;
      if (await NpsService.shouldShow()) {
        if (!mounted) return;
        // ignore: unawaited_futures
        showNpsSheet(context);
      }
    });
  }

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
                        // ── 1. VPN 连接卡 ─────────────────────────────
                        _StaggeredIn(
                          index: 0,
                          child: RepaintBoundary(
                            child: HeroCard(
                              status: status,
                              onToggle: () => _toggle(context, ref),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ── 1.2 场景预设（feature-flag 保护）──────────
                        const _StaggeredIn(
                          index: 1,
                          child: RepaintBoundary(child: ScenePresetBar()),
                        ),

                        const SizedBox(height: 12),

                        // ── 1.5 订阅过期提示 ─────────────────────────
                        const _StaggeredIn(
                          index: 1,
                          child: RepaintBoundary(
                              child: StaleSubscriptionBanner()),
                        ),

                        const SizedBox(height: 12),

                        // ── 2. 快捷操作 ───────────────────────────────
                        const _StaggeredIn(
                          index: 2,
                          child: RepaintBoundary(child: QuickActions()),
                        ),

                        const SizedBox(height: 12),

                        // ── 3. 公告（服务通知优先）──────────────────
                        const _StaggeredIn(
                          index: 3,
                          child: RepaintBoundary(child: NoticesCard()),
                        ),

                        const SizedBox(height: 12),

                        // ── 4. 悦视频推荐条 ───────────────────────────
                        const _StaggeredIn(
                          index: 4,
                          child: RepaintBoundary(child: EmbyPreviewRow()),
                        ),

                        const SizedBox(height: 12),

                        // ── 5. 签到 ─────────────────────────────────
                        const _StaggeredIn(
                          index: 5,
                          child: RepaintBoundary(child: CheckinCard()),
                        ),

                        const SizedBox(height: 12),

                        // ── 5. 数据监控（折叠）───────────────────────
                        const _StaggeredIn(
                          index: 6,
                          child: RepaintBoundary(child: _TrafficSection()),
                        ),

                        const SizedBox(height: 16),
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

      // First-time VPN permission explanation (mobile only).
      // Shows a friendly dialog BEFORE the system VPN permission popup,
      // so users understand why the permission is needed.
      if (Platform.isAndroid || Platform.isIOS) {
        final seen = await SettingsService.get<bool>('hasSeenVpnHint') ?? false;
        if (!seen) {
          if (!context.mounted) return;
          final proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(s.vpnPermTitle),
              content: Text(s.vpnPermBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(s.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(s.vpnPermContinue),
                ),
              ],
            ),
          );
          if (proceed != true) return;
          await SettingsService.set('hasSeenVpnHint', true);
        }
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

// ── 数据监控折叠区域 ─────────────────────────────────────────────────────────
// 将 CarrierCard / LiveStatusCard / MetricsRow 收纳至可折叠块，默认收起。
// 仅 VPN 运行时显示真实数据；VPN 未运行时块仍存在但内部数据为空。

class _TrafficSection extends ConsumerStatefulWidget {
  const _TrafficSection();

  @override
  ConsumerState<_TrafficSection> createState() => _TrafficSectionState();
}

class _TrafficSectionState extends ConsumerState<_TrafficSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRunning =
        ref.watch(coreStatusProvider) == CoreStatus.running;

    final headerColor = isDark ? YLColors.zinc200 : YLColors.zinc700;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(color: borderColor, width: 0.5),
        boxShadow: YLShadow.card(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header row — always visible, tap to expand/collapse
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.bar_chart_rounded,
                    size: 16,
                    color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.of(context).dataMonitor,
                      style: YLText.label.copyWith(
                        color: headerColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!isRunning)
                    Text(
                      S.of(context).vpnNotRunning,
                      style: YLText.caption
                          .copyWith(color: YLColors.zinc400),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: YLColors.zinc400,
                  ),
                ],
              ),
            ),
          ),

          // Expandable content
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        Divider(height: 1, color: borderColor),
                        const SizedBox(height: 12),
                        const RepaintBoundary(child: CarrierCard()),
                        const SizedBox(height: 12),
                        const RepaintBoundary(child: LiveStatusCard()),
                        const SizedBox(height: 12),
                        const RepaintBoundary(child: MetricsRow()),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ── Staggered entrance animation wrapper ──────────────────────────────────────
// Lightweight fade + slide-up entrance (20px, 400ms) with a short per-index
// delay so dashboard cards cascade in on first paint. Uses TweenAnimationBuilder
// only — no extra packages. Runs exactly once per mount (key-stable index).

class _StaggeredIn extends StatelessWidget {
  final int index;
  final Widget child;

  const _StaggeredIn({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    // Total duration including per-index offset kept under ~600ms.
    final delayMs = (index * 60).clamp(0, 360);
    const animMs = 400;
    final totalMs = delayMs + animMs;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: totalMs),
      curve: _DelayedCurve(
        delay: delayMs / totalMs,
        inner: Curves.easeOutCubic,
      ),
      builder: (context, t, widget) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 20),
            child: widget,
          ),
        );
      },
      child: child,
    );
  }
}

class _DelayedCurve extends Curve {
  final double delay; // 0..1 fraction of total duration
  final Curve inner;
  const _DelayedCurve({required this.delay, required this.inner});

  @override
  double transformInternal(double t) {
    if (t < delay) return 0.0;
    final remapped = (t - delay) / (1.0 - delay);
    return inner.transform(remapped.clamp(0.0, 1.0));
  }
}
