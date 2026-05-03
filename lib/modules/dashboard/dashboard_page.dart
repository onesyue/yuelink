import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/settings_service.dart';
import '../../i18n/app_strings.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../core/providers/core_provider.dart';
import 'providers/traffic_providers.dart';
import '../profiles/providers/profiles_providers.dart';
import '../../shared/app_notifier.dart';
import '../../core/kernel/core_manager.dart';
import '../../infrastructure/repositories/profile_repository.dart';
import '../../theme.dart';
import '../announcements/providers/announcements_providers.dart';
import '../mine/providers/account_providers.dart';
import 'widgets/live_status_card.dart';
import 'widgets/metrics_row.dart';
import 'widgets/carrier_card.dart';
import '../checkin/presentation/checkin_card.dart';
import '../checkin/presentation/calendar_entry_card.dart';
import '../checkin/providers/checkin_provider.dart';
import 'widgets/hero_card.dart';
import 'widgets/quick_actions.dart';
import '../mine/widgets/notices_card.dart';
import 'widgets/emby_preview_row.dart';
import 'widgets/renewal_reminder_banner.dart';
import 'widgets/stale_subscription_banner.dart';
import '../../domain/emby/emby_info_entity.dart';
import '../../app/main_shell.dart';
import '../../shared/nps_service.dart';
import '../../shared/widgets/nps_sheet.dart';
import '../../shared/widgets/yl_scaffold.dart';
import '../../widgets/loading_overlay.dart';
import '../emby/emby_providers.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _busy = false;
  bool _npsChecked = false;
  bool _embyActivationChecked = false;
  ProviderSubscription? _embyActivationSub;

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

    // First-time Emby activation prompt. Fires once per device when
    // the embyProvider first reports `hasNativeAccess == true` AND the
    // user hasn't seen the prompt before. Goal: surface the Emby
    // perk to subscribers who don't realise their plan includes it.
    // Listener self-disarms after the first eligible event so we
    // don't fire repeatedly while embyProvider rebuilds.
    _embyActivationSub = ref.listenManual<AsyncValue<EmbyInfo?>>(embyProvider, (
      prev,
      next,
    ) {
      if (_embyActivationChecked) return;
      final info = next.value;
      if (info == null || !info.hasNativeAccess) return;
      _embyActivationChecked = true;
      // 2 s delay so the prompt doesn't race the rest of the
      // first-paint sequence (NPS at 5 s, hero animations).
      Future<void>.delayed(const Duration(seconds: 2), () async {
        if (!mounted) return;
        final seen =
            await SettingsService.get<bool>('hasSeenEmbyActivation') ?? false;
        if (seen || !mounted) return;
        await _showEmbyActivationSheet();
        await SettingsService.set('hasSeenEmbyActivation', true);
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _embyActivationSub?.close();
    super.dispose();
  }

  Future<void> _showEmbyActivationSheet() async {
    if (!mounted) return;
    final isEn = S.of(context).isEn;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: YLColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(YLRadius.lg),
                    ),
                    child: const Icon(
                      Icons.movie_rounded,
                      color: YLColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEn ? 'Emby is unlocked' : '悦视频已解锁',
                      style: YLText.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : YLColors.zinc900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isEn
                    ? 'Your subscription includes access to Emby. Watch '
                          'licensed movies and TV shows directly inside the app.'
                    : '你的订阅已包含悦视频权益，无需额外付费即可在 app '
                          '内观看正版电影与剧集。',
                style: YLText.body.copyWith(
                  color: isDark ? YLColors.zinc300 : YLColors.zinc600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(isEn ? 'Later' : '稍后再看'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (mounted) {
                          MainShell.switchToTab(context, MainShell.tabEmby);
                        }
                      },
                      child: Text(isEn ? 'Open Emby' : '立即打开'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // UI reads the derived display status so a manual-stop that races a
    // resume recovery cannot leave HeroCard showing "connected" for one
    // frame. Internals (lifecycle, heartbeat, tray) keep using
    // `coreStatusProvider` for ground truth.
    final status = ref.watch(displayCoreStatusProvider);
    final isRunning = status == CoreStatus.running;

    // Activate background streams that the dashboard chart / hero card
    // depends on. `connectionsStreamProvider` is intentionally NOT
    // activated here — it powers MetricsRow inside the collapsed
    // data-monitor section, which activates it on demand. Keeping that
    // websocket paused while the section is closed cuts a 1-Hz main-isolate
    // wakeup that has no visible consumer on the home screen.
    // coreHeartbeatProvider is watched globally in _YueLinkAppState.
    if (isRunning) {
      ref.listen(trafficStreamProvider, (_, _) {});
      ref.listen(memoryStreamProvider, (_, _) {});
    }

    return YLLargeTitleScaffold(
      title: s.navHome,
      bottomSafe: false,
      maxContentWidth: 768,
      showTitleBar: false,
      onRefresh: () async {
        await ref.read(authProvider.notifier).refreshUserInfo();
        ref.invalidate(dashboardNoticesProvider);
        ref.invalidate(announcementsProvider);
        ref.read(checkinProvider.notifier).refresh();
      },
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ── 0. Guest mode CTA — only shown to users
              //     who skipped login (or finished onboarding
              //     without one). Hidden once they sign in.
              if (ref.watch(authProvider.select((a) => a.isGuest)))
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: RepaintBoundary(child: _GuestLoginBanner()),
                ),

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

              // ── 1.5 订阅过期提示 ─────────────────────────
              const _StaggeredIn(
                index: 1,
                child: RepaintBoundary(child: RenewalReminderBanner()),
              ),

              const SizedBox(height: 12),

              // ── 1.6 订阅配置陈旧提示 ─────────────────────
              const _StaggeredIn(
                index: 2,
                child: RepaintBoundary(child: StaleSubscriptionBanner()),
              ),

              const SizedBox(height: 12),

              // ── 2. 快捷操作 ───────────────────────────────
              const _StaggeredIn(
                index: 3,
                child: RepaintBoundary(child: QuickActions()),
              ),

              const SizedBox(height: 12),

              // ── 3. 公告（服务通知优先）──────────────────
              const _StaggeredIn(
                index: 4,
                child: RepaintBoundary(child: NoticesCard()),
              ),

              const SizedBox(height: 12),

              // ── 4. 悦视频推荐条 ───────────────────────────
              const _StaggeredIn(
                index: 5,
                child: RepaintBoundary(child: EmbyPreviewRow()),
              ),

              const SizedBox(height: 12),

              // ── 5. 签到 ─────────────────────────────────
              const _StaggeredIn(
                index: 6,
                child: RepaintBoundary(child: CheckinCard()),
              ),

              const SizedBox(height: 12),

              // ── 5.5 签到日历入口（与签到/Emby 平级） ──────
              const _StaggeredIn(
                index: 7,
                child: RepaintBoundary(child: CheckinCalendarEntryCard()),
              ),

              const SizedBox(height: 12),

              // ── 6. 数据监控（折叠）───────────────────────
              const _StaggeredIn(
                index: 8,
                child: RepaintBoundary(child: _TrafficSection()),
              ),

              const SizedBox(height: 16),
            ]),
          ),
        ),
      ],
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
        // Guest users have no way to sync the YueLink subscription —
        // toasting "no subscription" lands them in a dead end. Show a
        // login CTA dialog instead. Users with the official app account
        // (loggedIn but no profile yet — e.g. fresh-install + sync hasn't
        // run) keep the original toast since their fix is on the
        // Profiles tab, not the login page.
        if (ref.read(authProvider).isGuest && context.mounted) {
          await _showGuestConnectPrompt(context, ref, s);
          return;
        }
        AppNotifier.warning(s.snackNoProfile);
        return;
      }

      final config = await ref
          .read(profileRepositoryProvider)
          .loadConfig(activeId);
      if (config == null) {
        AppNotifier.warning(s.snackConfigMissing);
        return;
      }

      // First-time VPN permission explanation (mobile only).
      // Shows a friendly explainer BEFORE the system VPN permission popup,
      // so users understand why the permission is needed and (on iOS)
      // exactly which native dialog they're about to see.
      if (Platform.isAndroid || Platform.isIOS) {
        final seen = await SettingsService.get<bool>('hasSeenVpnHint') ?? false;
        if (!seen) {
          if (!context.mounted) return;
          final proceed = await _showVpnRationale(context, s);
          if (proceed != true) return;
          await SettingsService.set('hasSeenVpnHint', true);
        }
      }

      // iOS-only progress overlay. The startIosVpn path can stall for up
      // to 20 s on first connect (provisioning prompt + Go core init in
      // the PacketTunnel extension). Pre-fix this was a silent black-
      // looking screen — users assumed the app was hung and tapped
      // Connect again. The overlay turns the wait into a visible
      // "starting tunnel" state without altering the underlying flow.
      // Other platforms have their own progress affordances (Android's
      // system VPN dialog, desktop's near-instant start) so we skip it
      // there to avoid double-loaders.
      final bool ok;
      if (Platform.isIOS && context.mounted) {
        ok = await LoadingOverlay.run<bool>(
          context,
          message: s.isEn
              ? 'Starting secure tunnel… (first launch can take ~30 s)'
              : '正在建立安全隧道…首次启动可能需要 30 秒',
          action: () => actions.start(config),
        );
      } else {
        ok = await actions.start(config);
      }
      if (!ok && mounted) {
        AppNotifier.error(s.snackStartFailed);
        final lastGood = await CoreManager.instance.loadLastWorkingConfig();
        if (lastGood != null && lastGood != config && mounted) {
          _showRollbackDialog(s, lastGood);
        }
      } else if (ok && mounted) {
        // Desktop systemProxy mode used to be silent on success — users
        // tapped Connect, the button flipped to "Connected", but nothing
        // told them their HTTP/HTTPS/SOCKS proxy was being rewritten on
        // every network service. Surface a one-shot info toast so the
        // change is visible. Skipped on TUN (the active-tunnel UX is
        // self-evident) and on mobile (VPN sheet is OS-driven).
        final isDesktop =
            Platform.isMacOS || Platform.isWindows || Platform.isLinux;
        if (isDesktop &&
            ref.read(connectionModeProvider) == 'systemProxy' &&
            ref.read(systemProxyOnConnectProvider)) {
          AppNotifier.info(
            s.isEn
                ? 'System proxy enabled — all traffic now routes through YueLink'
                : '系统代理已启用 — 所有流量将通过 YueLink 路由',
          );
        }
        // Fire-and-forget connectivity self-test prompt. First-connect
        // only — flag persisted so subsequent connects don't ask again.
        // The probe itself waits 2 s so the toast above lands first.
        unawaited(_maybeOfferConnectivityTest());
      }
    } finally {
      _busy = false;
    }
  }

  /// First-connect connectivity self-test prompt. Fires once per
  /// device after a successful connect. Goal: confirm the tunnel
  /// actually works before the user wanders off and discovers a
  /// browser failure half an hour later.
  ///
  /// The flag is set BEFORE the user confirms the test so that even
  /// dismissing the prompt counts as "asked once" — never nag again.
  Future<void> _maybeOfferConnectivityTest() async {
    final seen =
        await SettingsService.get<bool>('hasSeenConnectivityTest') ?? false;
    if (seen || !mounted) return;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final s = S.of(context);
    final isEn = s.isEn;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'Verify the tunnel?' : '验证连通性?'),
        content: Text(
          isEn
              ? 'Send a tiny probe to gstatic.com through the tunnel to '
                    'confirm everything is routed correctly. Takes about 3 s.'
              : '通过当前节点向 gstatic.com 发一个轻量探针，确认隧道工作正常。'
                    '大约 3 秒完成。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isEn ? 'Skip' : '跳过'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEn ? 'Run test' : '开始测试'),
          ),
        ],
      ),
    );
    // Mark seen regardless — never re-prompt on subsequent connects.
    await SettingsService.set('hasSeenConnectivityTest', true);
    if (proceed != true || !mounted) return;
    await _runConnectivityTest();
  }

  /// Send a probe to `https://www.gstatic.com/generate_204` through
  /// mihomo's mixed-port and show a green-or-red result dialog.
  /// Bypasses the local proxy if mock mode is active (no real tunnel).
  Future<void> _runConnectivityTest() async {
    if (!mounted) return;
    final isEn = S.of(context).isEn;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(YLRadius.lg),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(isEn ? 'Probing…' : '正在探测…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    var success = false;
    var detail = '';
    final stopwatch = Stopwatch()..start();
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      // Cascade-bug-aware: set findProxy as a separate statement, NOT
      // chained via `..`. The Dart parser misattributes the function
      // type if you do `..findProxy = ... ..connectionTimeout = ...`.
      final port = CoreManager.instance.mixedPort;
      if (port > 0 && !CoreManager.instance.isMockMode) {
        client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
      }
      final request = await client.getUrl(
        Uri.parse('https://www.gstatic.com/generate_204'),
      );
      request.headers.set('User-Agent', 'YueLink/connectivity-test');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      await response.drain<void>();
      stopwatch.stop();
      success = response.statusCode == 204 || response.statusCode == 200;
      detail = isEn
          ? 'HTTP ${response.statusCode} · ${stopwatch.elapsedMilliseconds} ms'
          : 'HTTP ${response.statusCode}·${stopwatch.elapsedMilliseconds} ms';
    } catch (e) {
      stopwatch.stop();
      detail = e.toString().split('\n').first;
      if (detail.startsWith('Exception: ')) detail = detail.substring(11);
      if (detail.length > 100) detail = '${detail.substring(0, 100)}…';
    } finally {
      client?.close(force: true);
    }

    if (!mounted) return;
    Navigator.pop(context); // close spinner

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          success ? Icons.check_circle_rounded : Icons.error_rounded,
          size: 48,
          color: success ? Colors.green : Colors.red,
        ),
        title: Text(
          success
              ? (isEn ? 'Connection works' : '连接正常')
              : (isEn ? 'Connection failed' : '连接失败'),
        ),
        content: Text(detail, textAlign: TextAlign.center),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Guest user tapped Connect with no active profile. Pop a small
  /// dialog that explains the dead end and offers a one-tap path to
  /// the login page (via authProvider.logout(), which the root
  /// _AuthGate routes to YueAuthPage). Cancel returns to the
  /// dashboard so the user can keep browsing in guest mode.
  Future<void> _showGuestConnectPrompt(
    BuildContext context,
    WidgetRef ref,
    S s,
  ) async {
    final isEn = s.isEn;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'Sign in to use nodes' : '登录后开始使用'),
        content: Text(
          isEn
              ? 'Guest mode lets you explore the app, but connecting to '
                    'YueLink nodes requires an account. Sign in to sync '
                    'your subscription, or stay in guest mode and import '
                    'a third-party subscription manually.'
              : '游客模式可以浏览 app，但连接悦通节点需要登录账号。'
                    '登录后会自动同步官方订阅；也可以保持游客模式，'
                    '手动导入第三方机场订阅。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEn ? 'Sign in' : '立即登录'),
          ),
        ],
      ),
    );
    if (result == true && context.mounted) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  /// First-connect VPN-permission explainer.
  ///
  /// Android: keeps the legacy compact AlertDialog — the OS prompt that
  /// follows is itself short and self-explanatory ("YueLink wants to set
  /// up a VPN connection. Allow / Deny"). One screen of context is enough.
  ///
  /// iOS: bottom sheet with a 3-step preview of what the user will see,
  /// because Apple's "YueLink Would Like to Add VPN Configurations"
  /// dialog is more alarming than Android's and follow-up prompts may
  /// ask for passcode / Face ID. Walking the user through the steps
  /// up-front meaningfully cuts the bounce rate at first connect.
  ///
  /// Returns `true` if the user agreed to continue, `false` (or null) on
  /// cancel — caller treats anything-not-true as "abort connect".
  Future<bool?> _showVpnRationale(BuildContext context, S s) {
    if (Platform.isIOS) {
      return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => _IosVpnRationaleSheet(s: s),
      );
    }
    return showDialog<bool>(
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
  }
}

/// iOS-specific VPN-permission explainer. Renders as a tall bottom sheet
/// (≈70 % screen height) with a 3-step preview of the system dialog the
/// user is about to see. Kept private to dashboard_page.dart since it has
/// no other call sites and no reusable surface.
class _IosVpnRationaleSheet extends StatelessWidget {
  const _IosVpnRationaleSheet({required this.s});

  final S s;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : YLColors.zinc900;
    final mutedColor = isDark ? YLColors.zinc400 : YLColors.zinc600;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (isDark ? YLColors.zinc700 : YLColors.zinc100),
                    borderRadius: BorderRadius.circular(YLRadius.md),
                  ),
                  child: Icon(Icons.shield_rounded, size: 22, color: textColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.vpnPermIosTitle,
                    style: YLText.titleMedium.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              s.vpnPermIosIntro,
              style: YLText.body.copyWith(color: mutedColor, height: 1.5),
            ),
            const SizedBox(height: 20),
            _Step(index: 1, text: s.vpnPermIosStep1, isDark: isDark),
            const SizedBox(height: 12),
            _Step(index: 2, text: s.vpnPermIosStep2, isDark: isDark),
            const SizedBox(height: 12),
            _Step(index: 3, text: s.vpnPermIosStep3, isDark: isDark),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(s.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(s.vpnPermIosContinue),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text, required this.isDark});

  final int index;
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accentBg = isDark ? YLColors.zinc700 : YLColors.zinc200;
    final accentFg = isDark ? Colors.white : YLColors.zinc900;
    final bodyFg = isDark ? YLColors.zinc200 : YLColors.zinc800;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accentBg,
            borderRadius: BorderRadius.circular(YLRadius.lg),
          ),
          child: Text(
            '$index',
            style: YLText.label.copyWith(
              color: accentFg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: YLText.body.copyWith(color: bodyFg, height: 1.4),
            ),
          ),
        ),
      ],
    );
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
        ref.watch(displayCoreStatusProvider) == CoreStatus.running;

    final headerColor = isDark ? YLColors.zinc200 : YLColors.zinc700;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      style: YLText.caption.copyWith(color: YLColors.zinc400),
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

/// "Login to unlock the full app" banner shown on the dashboard when
/// the user is in guest mode (skipped login from the auth page or from
/// onboarding's value-first default path).
///
/// Tap → calls `authProvider.logout()` which flips state to
/// `loggedOut`. The root `_AuthGate` reacts by routing to YueAuthPage,
/// which is the canonical login surface. Using `logout()` (vs a
/// dedicated `goToLogin()` method) is intentional: settings already
/// uses the same indirection for `_GuestLoginCard`, so behaviour stays
/// consistent across the two entry points.
class _GuestLoginBanner extends ConsumerWidget {
  const _GuestLoginBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEn = S.of(context).isEn;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isDark
              ? [
                  YLColors.primary.withValues(alpha: 0.18),
                  YLColors.primary.withValues(alpha: 0.06),
                ]
              : [
                  YLColors.primaryLight,
                  YLColors.primaryLight.withValues(alpha: 0.45),
                ],
        ),
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? YLColors.primary.withValues(alpha: 0.30)
              : YLColors.primary.withValues(alpha: 0.20),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark
                  ? YLColors.primary.withValues(alpha: 0.25)
                  : Colors.white,
              borderRadius: BorderRadius.circular(YLRadius.md),
            ),
            child: Icon(
              Icons.lock_open_rounded,
              size: 18,
              color: isDark ? Colors.white : YLColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEn ? 'Browsing as guest' : '当前为游客模式',
                  style: YLText.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : YLColors.zinc900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isEn
                      ? 'Sign in to sync subscriptions, unlock Emby, and more.'
                      : '登录以同步订阅、解锁悦视频与更多功能',
                  style: YLText.caption.copyWith(
                    color: isDark ? YLColors.zinc300 : YLColors.zinc600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => ref.read(authProvider.notifier).logout(),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white : YLColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              isEn ? 'Sign in' : '立即登录',
              style: YLText.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
