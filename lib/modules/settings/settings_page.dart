import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants.dart';
import 'web_page.dart';
import '../../i18n/app_strings.dart';
import '../../modules/profiles/profiles_page.dart';
import 'sub/general_settings_page.dart';
import 'sub/overwrite_page.dart';
import '../../modules/store/store_page.dart';
import '../../modules/store/order_history_page.dart';
import 'connection_repair_page.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../shared/formatters/subscription_parser.dart' show formatBytes;
import '../../shared/app_notifier.dart';
import '../../core/kernel/geodata_service.dart';
import '../../core/storage/settings_service.dart';
import '../../core/env_config.dart';
import '../updater/update_checker.dart';
import '../../shared/rich_content.dart';
import '../../shared/widgets/setting_icon.dart';
import '../../theme.dart';
import '../../domain/account/account_overview.dart';
import '../mine/providers/account_providers.dart';
import '../surge_modules/pages/modules_page.dart';
import '../surge_modules/providers/module_provider.dart';

// ── Settings-level providers ─────────────────────────────────────────────────

final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final languageProvider = StateProvider<String>((ref) => 'zh');

/// Accent color stored as hex string (without '#'), e.g. '3B82F6'.
final accentColorProvider = StateProvider<String>((ref) => '3B82F6');

/// Subscription sync interval in hours (0 = disabled).
final subSyncIntervalProvider = StateProvider<int>((ref) => 6);

/// QUIC reject policy: off | googlevideo | all.
final quicPolicyProvider =
    StateProvider<String>((ref) => SettingsService.defaultQuicPolicy);

/// Desktop: close window behavior. Values: 'tray' (default) | 'exit'.
final closeBehaviorProvider = StateProvider<String>((ref) => 'tray');

/// Desktop: toggle connection hotkey stored as "ctrl+alt+c" lowercase.
final toggleHotkeyProvider = StateProvider<String>((ref) => 'ctrl+alt+c');

// ── Hotkey utilities ──────────────────────────────────────────────────────────

/// Parse stored hotkey string to a [HotKey].
HotKey parseStoredHotkey(String stored) {
  final parts = stored.toLowerCase().split('+');
  final modifiers = <HotKeyModifier>[];
  LogicalKeyboardKey key = LogicalKeyboardKey.keyC;
  for (final p in parts) {
    switch (p) {
      case 'ctrl':
      case 'control':
        modifiers.add(HotKeyModifier.control);
      case 'shift':
        modifiers.add(HotKeyModifier.shift);
      case 'alt':
        modifiers.add(HotKeyModifier.alt);
      case 'meta':
      case 'cmd':
      case 'win':
        modifiers.add(HotKeyModifier.meta);
      default:
        key = _logicalKeyFromLabel(p);
    }
  }
  return HotKey(key: key, modifiers: modifiers, scope: HotKeyScope.system);
}

/// Format stored hotkey string to display label, e.g. "ctrl+alt+c" → "Ctrl+Alt+C".
String displayHotkey(String stored) {
  return stored.split('+').map((p) {
    switch (p.toLowerCase()) {
      case 'ctrl':
      case 'control':
        return 'Ctrl';
      case 'shift':
        return 'Shift';
      case 'alt':
        return 'Alt';
      case 'meta':
      case 'cmd':
      case 'win':
        return Platform.isMacOS ? '⌘' : 'Win';
      default:
        return p.toUpperCase();
    }
  }).join('+');
}

bool _isModifierKey(LogicalKeyboardKey key) {
  final modifiers = {
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  };
  return modifiers.contains(key);
}

LogicalKeyboardKey _logicalKeyFromLabel(String label) {
  const map = {
    'a': LogicalKeyboardKey.keyA,
    'b': LogicalKeyboardKey.keyB,
    'c': LogicalKeyboardKey.keyC,
    'd': LogicalKeyboardKey.keyD,
    'e': LogicalKeyboardKey.keyE,
    'f': LogicalKeyboardKey.keyF,
    'g': LogicalKeyboardKey.keyG,
    'h': LogicalKeyboardKey.keyH,
    'i': LogicalKeyboardKey.keyI,
    'j': LogicalKeyboardKey.keyJ,
    'k': LogicalKeyboardKey.keyK,
    'l': LogicalKeyboardKey.keyL,
    'm': LogicalKeyboardKey.keyM,
    'n': LogicalKeyboardKey.keyN,
    'o': LogicalKeyboardKey.keyO,
    'p': LogicalKeyboardKey.keyP,
    'q': LogicalKeyboardKey.keyQ,
    'r': LogicalKeyboardKey.keyR,
    's': LogicalKeyboardKey.keyS,
    't': LogicalKeyboardKey.keyT,
    'u': LogicalKeyboardKey.keyU,
    'v': LogicalKeyboardKey.keyV,
    'w': LogicalKeyboardKey.keyW,
    'x': LogicalKeyboardKey.keyX,
    'y': LogicalKeyboardKey.keyY,
    'z': LogicalKeyboardKey.keyZ,
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
  };
  return map[label.toLowerCase()] ?? LogicalKeyboardKey.keyC;
}

// ─────────────────────────────────────────────────────────────────────────────

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  UpdateInfo? _pendingUpdate;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkForUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh account overview shown on this page (我的 card).
      // Do NOT invalidate dashboardNoticesProvider here — NoticesCard on
      // Dashboard uses when(loading: () => SizedBox.shrink()), causing it to
      // flash empty on every background→foreground cycle. Notices are
      // refreshed via dashboard pull-to-refresh instead.
      ref.invalidate(accountOverviewProvider);
    }
  }

  Future<void> _checkForUpdate() async {
    // auto: true → respects the user's auto-check toggle (skip if disabled).
    final info = await UpdateChecker.instance.check(auto: true);
    if (!mounted) return;
    setState(() {
      if (info != null) _pendingUpdate = info;
    });
  }

  void _showUpdateDialog(BuildContext context, UpdateInfo info) {
    final s = S.of(context);
    var downloading = false;
    double progress = 0;
    String? error;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          return AlertDialog(
            title: Text('${s.updateAvailable} v${info.latestVersion}'),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (info.releaseNotes.isNotEmpty) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(
                        child: RichContent(
                          content: info.releaseNotes,
                          textStyle:
                              YLText.body.copyWith(color: YLColors.zinc500),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (downloading) ...[
                    LinearProgressIndicator(
                        value: progress > 0 ? progress : null),
                    const SizedBox(height: 8),
                    Text(
                      progress > 0
                          ? '${(progress * 100).toStringAsFixed(0)}%'
                          : s.updateDownloading,
                      style: YLText.caption.copyWith(color: YLColors.zinc500),
                    ),
                  ],
                  if (error != null) ...[
                    Text(error!,
                        style: YLText.caption.copyWith(color: YLColors.error)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: downloading ? null : () => Navigator.pop(ctx),
                child: Text(s.cancel),
              ),
              if (info.downloadUrl != null)
                FilledButton(
                  onPressed: downloading
                      ? null
                      : () async {
                          setDialog(() {
                            downloading = true;
                            error = null;
                            progress = 0;
                          });
                          try {
                            // Pass the manifest's sha256 so the downloaded
                            // file is verified against tampering. If the
                            // hash mismatches, download() throws and the
                            // partial file is deleted.
                            final path = await UpdateChecker.download(
                              info.downloadUrl!,
                              expectedSha256: info.sha256,
                              onProgress: (received, total) {
                                if (total > 0) {
                                  setDialog(() => progress = received / total);
                                }
                              },
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _openDownloadedFile(path);
                          } catch (e) {
                            if (ctx.mounted) {
                              setDialog(() {
                                downloading = false;
                                error = '${s.updateDownloadFailed}: $e';
                              });
                            }
                          }
                        },
                  child: Text(s.updateDownload),
                )
              else
                // Fallback: open GitHub release page if no asset found
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final uri = Uri.parse(info.releaseUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                  child: Text(s.updateDownload),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openDownloadedFile(String path) async {
    final s = S.of(context);
    try {
      if (Platform.isAndroid) {
        // Use platform channel to install APK
        const channel = MethodChannel('com.yueto.yuelink/vpn');
        await channel.invokeMethod('installApk', {'path': path});
        AppNotifier.success(s.updateInstalling);
        return;
      }
      if (Platform.isMacOS || Platform.isWindows) {
        // Open DMG/EXE via system default handler
        final uri = Uri.file(path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else if (Platform.isMacOS) {
          await Process.run('open', [path]);
        } else {
          await Process.run('cmd', ['/c', 'start', '', path]);
        }
        AppNotifier.success(s.updateInstalling);
        return;
      }
      if (Platform.isLinux) {
        // .deb / .rpm / .AppImage — let the desktop environment pick the
        // right tool (gdebi / gnome-software / dnfdragora / file manager).
        // xdg-open is the universal entry point on Linux desktops.
        final result = await Process.run('xdg-open', [path]);
        if (result.exitCode != 0) {
          throw ProcessException('xdg-open', [path],
              result.stderr.toString().trim(), result.exitCode);
        }
        AppNotifier.success(s.updateInstalling);
        return;
      }
      if (Platform.isIOS) {
        // iOS can't sideload .ipa files from inside another app — App Store
        // and TrollStore are the only install paths. Open the GitHub release
        // page in the user's browser so they can do it manually.
        final pending = _pendingUpdate;
        if (pending != null && pending.releaseUrl.isNotEmpty) {
          await launchUrl(
            Uri.parse(pending.releaseUrl),
            mode: LaunchMode.externalApplication,
          );
          AppNotifier.info(S.current.installIpaHint);
          return;
        }
        AppNotifier.error(S.current.installIosManual);
        return;
      }
      AppNotifier.error(S.current.installUnsupported);
    } catch (e) {
      AppNotifier.error('${s.updateDownloadFailed}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final authState = ref.watch(authProvider);
    final isGuest = authState.isGuest;
    // loggedOut 状态同样不展示账户中心卡（避免显示"数据暂时无法获取"）
    final isLoggedOut = !authState.isLoggedIn && !isGuest;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top bar ──────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                32, MediaQuery.of(context).padding.top + 16, 32, 20),
            child: Text(
              s.navMine,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          Container(
            height: 0.5,
            color: dividerColor,
          ),

          // ── Content ──────────────────────────────────────────────
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [
                    // ══ 0. Profile ═══════════════════════════════════════════
                    if (isGuest || isLoggedOut) ...[
                      _GuestLoginCard(isDark: isDark),
                    ] else ...[
                      // ── Profile row + 流量（合并为账户簇）──
                      _ProfileRow(isDark: isDark),
                      const SizedBox(height: 8),
                      _MineTrafficSection(isDark: isDark),
                    ],

                    // ══ 1. Service (订阅相关) ══════════════════════════════
                    _SectionTitle(s.sectionService),
                    _SettingsCard(
                      child: Column(
                        children: [
                          YLInfoRow(
                            label: s.mineSubscriptionManage,
                            leading: const YLSettingIcon(
                                icon: Icons.cloud_outlined, color: Colors.blue),
                            trailing: const Icon(Icons.chevron_right,
                                size: 18, color: YLColors.zinc400),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ProfilePage()),
                            ),
                          ),
                          if (!isGuest) ...[
                            Divider(
                                height: 1, thickness: 0.5, color: dividerColor),
                            YLInfoRow(
                              label: s.mineRenew,
                              leading: const YLSettingIcon(
                                  icon: Icons.shopping_bag_outlined,
                                  color: Colors.pink),
                              trailing: const Icon(Icons.chevron_right,
                                  size: 18, color: YLColors.zinc400),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const StorePage()),
                              ),
                            ),
                            Divider(
                                height: 1, thickness: 0.5, color: dividerColor),
                            YLInfoRow(
                              label: s.storeOrderHistory,
                              leading: const YLSettingIcon(
                                  icon: Icons.receipt_long_outlined,
                                  color: Colors.orange),
                              trailing: const Icon(Icons.chevron_right,
                                  size: 18, color: YLColors.zinc400),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const OrderHistoryPage()),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // ══ 2. 设置（偏好 / 覆写 / 修复 / 模块）═══════════════
                    _SectionTitle(s.sectionSettings),
                    _SettingsCard(
                      child: Column(
                        children: [
                          YLInfoRow(
                            label: s.preferencesLabel,
                            leading: const YLSettingIcon(
                                icon: Icons.settings_outlined,
                                color: Colors.grey),
                            trailing: const Icon(Icons.chevron_right,
                                size: 18, color: YLColors.zinc400),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const GeneralSettingsPage()),
                            ),
                          ),
                          Divider(
                              height: 1, thickness: 0.5, color: dividerColor),
                          YLInfoRow(
                            label: s.overwriteTitle,
                            leading: const YLSettingIcon(
                                icon: Icons.code, color: Colors.grey),
                            trailing: const Icon(Icons.chevron_right,
                                size: 18, color: YLColors.zinc400),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const OverwritePage()),
                            ),
                          ),
                          Divider(
                              height: 1, thickness: 0.5, color: dividerColor),
                          YLInfoRow(
                            label: S.current.repairTitle,
                            leading: const YLSettingIcon(
                                icon: Icons.build_outlined, color: Colors.red),
                            trailing: const Icon(Icons.chevron_right,
                                size: 18, color: YLColors.zinc400),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ConnectionRepairPage()),
                            ),
                          ),
                          Divider(
                              height: 1, thickness: 0.5, color: dividerColor),
                          YLInfoRow(
                            label: s.modulesLabel,
                            leading: const YLSettingIcon(
                                icon: Icons.extension_outlined,
                                color: Colors.deepPurple),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Consumer(builder: (ctx, ref, _) {
                                  final state = ref.watch(moduleProvider);
                                  final count = state.modules
                                      .where((m) => m.enabled)
                                      .length;
                                  if (count == 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (isDark
                                              ? YLColors.primaryDark
                                              : YLColors.primary)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: YLText.caption.copyWith(
                                          color: isDark
                                              ? YLColors.primaryDark
                                              : YLColors.primary),
                                    ),
                                  );
                                }),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right,
                                    size: 18, color: YLColors.zinc400),
                              ],
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ModulesPage()),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ══ 关于 ═════════════════════════════════════════════
                    _SectionTitle(s.sectionAbout),
                    _SettingsCard(
                      child: Column(
                        children: [
                          // "Check for updates" — hidden in store builds to pass
                          // App Store / Google Play review (self-update is prohibited).
                          if (EnvConfig.isStandalone) ...[
                            YLInfoRow(
                              label: s.checkUpdate,
                              leading: const YLSettingIcon(
                                  icon: Icons.system_update,
                                  color: Colors.teal),
                              value:
                                  ref.watch(appVersionProvider).valueOrNull ??
                                      '',
                              trailing: _checkingUpdate
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : _pendingUpdate != null
                                      ? YLChip(
                                          s.updateAvailableV(
                                              _pendingUpdate!.latestVersion),
                                          color: isDark
                                              ? Colors.white
                                              : YLColors.primary)
                                      : const Icon(Icons.chevron_right,
                                          size: 18, color: YLColors.zinc400),
                              onTap: _checkingUpdate
                                  ? null
                                  : _pendingUpdate != null
                                      ? () => _showUpdateDialog(
                                          context, _pendingUpdate!)
                                      : () async {
                                          setState(
                                              () => _checkingUpdate = true);
                                          // Manual check ignores skipped versions
                                          final info = await UpdateChecker
                                              .instance
                                              .check(ignoreSkipped: true);
                                          if (!mounted) return;
                                          setState(() {
                                            _pendingUpdate = info;
                                            _checkingUpdate = false;
                                          });
                                          if (info == null) {
                                            AppNotifier.info(s.alreadyLatest);
                                          } else if (mounted) {
                                            // ignore: use_build_context_synchronously
                                            _showUpdateDialog(context, info);
                                          }
                                        },
                            ),
                            Divider(
                                height: 1, thickness: 0.5, color: dividerColor),
                          ],
                          YLInfoRow(
                            label: s.mineTelegramGroup,
                            leading: const YLSettingIcon(
                                icon: Icons.send, color: Color(0xFF229ED9)),
                            trailing: const Icon(Icons.chevron_right,
                                size: 18, color: YLColors.zinc400),
                            onTap: () async {
                              final tgUri =
                                  Uri.parse('tg://resolve?domain=yue_to');
                              if (await canLaunchUrl(tgUri)) {
                                await launchUrl(tgUri);
                              } else {
                                await launchUrl(
                                  Uri.parse('https://t.me/yue_to'),
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                          ),
                          Divider(
                              height: 1, thickness: 0.5, color: dividerColor),
                          YLInfoRow(
                            label: s.minePrivacyPolicy,
                            leading: const YLSettingIcon(
                                icon: Icons.lock_outline, color: Colors.green),
                            trailing: const Icon(Icons.chevron_right,
                                size: 18, color: YLColors.zinc400),
                            onTap: () {
                              const tosUrl = 'https://yue.to/tos.html';
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => InAppWebPage(
                                  title: s.minePrivacyPolicy,
                                  url: tosUrl,
                                ),
                              ));
                            },
                          ),
                          Divider(
                              height: 1, thickness: 0.5, color: dividerColor),
                          YLInfoRow(
                            label: s.openSourceLicense,
                            leading: const YLSettingIcon(
                                icon: Icons.info_outline, color: Colors.blue),
                            trailing: const Icon(Icons.chevron_right,
                                size: 18, color: YLColors.zinc400),
                            onTap: () => showLicensePage(
                              context: context,
                              applicationName: AppConstants.appName,
                              applicationVersion:
                                  ref.watch(appVersionProvider).valueOrNull ??
                                      '',
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 退出登录已移到 Profile 头像卡右上角
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Apple Settings 风格 profile row — 头像+邮箱+套餐标签。精简，不含按钮。
class _ProfileRow extends ConsumerWidget {
  final bool isDark;
  const _ProfileRow({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(accountOverviewProvider);
    final overview = overviewAsync.valueOrNull;

    // 始终显示，loading/error 时用占位数据
    final email = overview?.email ?? S.current.loading;
    final plan = overview?.planName ?? '--';

    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? YLColors.zinc700 : YLColors.zinc200,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      email.isNotEmpty && email != S.current.loading
                          ? email[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? YLColors.zinc300 : YLColors.zinc600),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(email,
                          style: YLText.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : YLColors.zinc900),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? YLColors.zinc700 : YLColors.zinc100,
                          borderRadius: BorderRadius.circular(YLRadius.sm),
                        ),
                        child: Text(plan,
                            style: YLText.caption.copyWith(
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? YLColors.zinc300
                                    : YLColors.zinc600)),
                      ),
                    ],
                  ),
                ),
                // 改密码 + 退出登录 小图标
                IconButton(
                  icon: Icon(Icons.lock_outline_rounded,
                      size: 18,
                      color: isDark ? YLColors.zinc400 : YLColors.zinc500),
                  tooltip: S.current.mineChangePassword,
                  onPressed: () {
                    final s = S.of(context);
                    final oldPwCtrl = TextEditingController();
                    final newPwCtrl = TextEditingController();
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(s.mineChangePassword),
                        content:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(
                              controller: oldPwCtrl,
                              obscureText: true,
                              decoration:
                                  InputDecoration(labelText: s.oldPassword)),
                          const SizedBox(height: 12),
                          TextField(
                              controller: newPwCtrl,
                              obscureText: true,
                              decoration:
                                  InputDecoration(labelText: s.newPassword)),
                        ]),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(s.cancel)),
                          FilledButton(
                            onPressed: () async {
                              final oldPw = oldPwCtrl.text.trim();
                              final newPw = newPwCtrl.text.trim();
                              if (oldPw.isEmpty || newPw.isEmpty) return;
                              Navigator.pop(ctx);
                              final token = ref.read(authProvider).token;
                              if (token == null) return;
                              try {
                                await ref
                                    .read(businessXboardApiProvider)
                                    .changePassword(
                                        token: token,
                                        oldPassword: oldPw,
                                        newPassword: newPw);
                                AppNotifier.success(s.passwordChangedSuccess);
                              } catch (_) {
                                AppNotifier.error(s.passwordChangeFailed);
                              }
                            },
                            child: Text(s.confirm),
                          ),
                        ],
                      ),
                    ).whenComplete(() {
                      oldPwCtrl.dispose();
                      newPwCtrl.dispose();
                    });
                  },
                ),
                IconButton(
                  icon: Icon(Icons.logout_rounded,
                      size: 18, color: YLColors.error.withValues(alpha: 0.7)),
                  tooltip: S.current.authLogout,
                  onPressed: () {
                    final s = S.of(context);
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(s.authLogout),
                        content: Text(s.authLogoutConfirm),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(s.cancel)),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              ref.read(authProvider.notifier).logout();
                            },
                            style: FilledButton.styleFrom(
                                backgroundColor: YLColors.error),
                            child: Text(s.authLogout),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MineTrafficSection extends ConsumerWidget {
  final bool isDark;
  const _MineTrafficSection({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(accountOverviewProvider);
    final overview = overviewAsync.valueOrNull;

    final usageRatio = overview?.usageRatio ?? 0.0;
    final usedStr = overview != null && overview.transferTotalBytes > 0
        ? formatBytes(overview.transferUsedBytes)
        : '--';
    final totalStr = overview != null && overview.transferTotalBytes > 0
        ? formatBytes(overview.transferTotalBytes)
        : '--';
    final remainStr = overview != null && overview.transferTotalBytes > 0
        ? formatBytes(overview.transferRemainingBytes)
        : '--';
    final expiryStr = overview == null
        ? '--'
        : overview.expireAt == null
            ? '永久有效'
            : overview.daysRemaining == null || overview.daysRemaining! < 0
                ? '已过期'
                : overview.daysRemaining == 0
                    ? '今日到期'
                    : '${overview.daysRemaining} 天后到期';

    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        child: Column(
          children: [
            Row(
              children: [
                Text(S.current.trafficUsedTotal,
                    style: YLText.caption.copyWith(color: YLColors.zinc500)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$usedStr / $totalStr',
                      style: YLText.label.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : YLColors.zinc900),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: usageRatio,
                minHeight: 5,
                backgroundColor: isDark ? YLColors.zinc700 : YLColors.zinc200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  usageRatio < 0.6
                      ? const Color(0xFF22C55E)
                      : usageRatio < 0.85
                          ? Colors.orange
                          : Colors.red,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('${S.current.trafficRemaining} $remainStr',
                      style: YLText.caption.copyWith(color: YLColors.zinc500),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(expiryStr,
                      style: YLText.caption.copyWith(
                        color: overview != null &&
                                (overview.daysRemaining ?? 999) <= 7
                            ? Colors.orange
                            : YLColors.zinc500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end),
                ),
              ],
            ),
            // Device-online row — only shown when we have live data from
            // the Checkin API. overview.onlineCount falls back to null
            // before the first successful fetch, in which case we hide
            // the row to avoid stale "0 / —" flashing.
            if (overview != null &&
                (overview.onlineCount != null ||
                    overview.deviceLimit != null)) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _deviceRowText(overview),
                      style: YLText.caption.copyWith(
                        color: _deviceRowColor(overview),
                        fontFeatures: YLText.tabularNums,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _deviceRowText(AccountOverview o) {
    final online = o.onlineCount ?? 0;
    final limit = o.deviceLimit ?? 0;
    final label = S.current.mineDevices;
    if (limit > 0) return '$label $online / $limit';
    return '$label $online';
  }

  Color _deviceRowColor(AccountOverview o) {
    final online = o.onlineCount ?? 0;
    final limit = o.deviceLimit ?? 0;
    if (limit > 0 && online >= limit) return Colors.orange;
    return YLColors.zinc500;
  }
}

class _GuestLoginCard extends ConsumerWidget {
  final bool isDark;
  const _GuestLoginCard({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEn = S.of(context).isEn;
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            const Icon(Icons.account_circle_outlined,
                size: 48, color: YLColors.zinc400),
            const SizedBox(height: 12),
            Text(
              isEn ? 'Not logged in' : '未登录',
              style: YLText.label.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : YLColors.zinc900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isEn ? 'Login to access all features' : '登录以使用全部功能',
              style: YLText.caption.copyWith(color: YLColors.zinc500),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => ref.read(authProvider.notifier).logout(),
                child: Text(isEn ? 'Go to Login' : '前往登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Settings page helper widgets ─────────────────────────────────────────────

/// Section title — matches the dashboard top bar label style.
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: YLColors.zinc500,
          letterSpacing: -0.08,
        ),
      ),
    );
  }
}

/// Card container matching the dashboard card style.
class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.hardEdge,
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
      child: child,
    );
  }
}

// ── Split Tunnel Section (Android) ────────────────────────────────────────────

/// A single settings row with a label on the left and a value or trailing widget on the right.
class YLInfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool enabled;
  final TextStyle? labelStyle;

  const YLInfoRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
    this.leading,
    this.onTap,
    this.enabled = true,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = enabled
        ? (isDark ? YLColors.zinc200 : YLColors.zinc700)
        : YLColors.zinc400;
    final valueColor = enabled
        ? (isDark ? YLColors.zinc400 : YLColors.zinc500)
        : YLColors.zinc300;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(label,
                style: labelStyle ?? YLText.body.copyWith(color: labelColor)),
          ),
          if (value != null)
            Text(value!, style: YLText.body.copyWith(color: valueColor)),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap != null && enabled) {
      return InkWell(onTap: onTap, child: content);
    }
    return Opacity(opacity: enabled ? 1.0 : 0.5, child: content);
  }
}

// ── Hotkey row (desktop) ──────────────────────────────────────────────────────

class _HotkeyRow extends ConsumerStatefulWidget {
  @override
  ConsumerState<_HotkeyRow> createState() => _HotkeyRowState();
}

class _HotkeyRowState extends ConsumerState<_HotkeyRow> {
  bool _registering = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stored = ref.watch(toggleHotkeyProvider);
    final display = displayHotkey(stored);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.toggleConnectionHotkey,
                    style: YLText.body.copyWith(
                        color: isDark ? YLColors.zinc200 : YLColors.zinc700)),
              ),
              Text(
                display,
                style: YLText.body.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                ),
              ),
              const SizedBox(width: 8),
              if (_registering)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton(
                  onPressed: _editHotkey,
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child:
                      Text(s.hotkeyEdit, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (Platform.isLinux)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                s.hotkeyLinuxNotice,
                style: YLText.caption.copyWith(color: YLColors.zinc400),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editHotkey() async {
    final s = S.of(context);
    final newKey = await _showHotkeyDialog(context, s);
    if (newKey == null || !mounted) return;
    setState(() => _registering = true);
    try {
      ref.read(toggleHotkeyProvider.notifier).state = newKey;
      await SettingsService.setToggleHotkey(newKey);
      // Re-registration is handled by ref.listen in _YueLinkAppState
      AppNotifier.success(s.hotkeySaved);
    } catch (_) {
      AppNotifier.error(s.hotkeyFailed);
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<String?> _showHotkeyDialog(BuildContext context, S s) {
    final focusNode = FocusNode();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.toggleConnectionHotkey),
        content: KeyboardListener(
          focusNode: focusNode,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent) return;
            if (_isModifierKey(event.logicalKey)) return;
            final parts = <String>[];
            if (HardwareKeyboard.instance.isControlPressed) {
              parts.add('ctrl');
            }
            if (HardwareKeyboard.instance.isShiftPressed) parts.add('shift');
            if (HardwareKeyboard.instance.isAltPressed) parts.add('alt');
            if (HardwareKeyboard.instance.isMetaPressed) parts.add('meta');
            final label = event.logicalKey.keyLabel.toLowerCase();
            if (label.isNotEmpty) parts.add(label);
            if (parts.length >= 2) Navigator.pop(ctx, parts.join('+'));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              s.hotkeyListening,
              textAlign: TextAlign.center,
              style: YLText.body.copyWith(color: YLColors.zinc400),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null), child: Text(s.cancel)),
        ],
      ),
    ).whenComplete(focusNode.dispose);
  }
}

// ── GeoData row ───────────────────────────────────────────────────────────────

// ── GeoData row ───────────────────────────────────────────────────────────────

class _GeoDataRow extends StatefulWidget {
  @override
  State<_GeoDataRow> createState() => _GeoDataRowState();
}

class _GeoDataRowState extends State<_GeoDataRow> {
  DateTime? _lastUpdated;
  bool _loading = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadLastUpdated();
  }

  Future<void> _loadLastUpdated() async {
    final dt = await GeoDataService.lastUpdated();
    if (mounted) {
      setState(() {
        _lastUpdated = dt;
        _loaded = true;
      });
    }
  }

  Future<void> _update() async {
    if (_loading) return;
    final s = S.of(context);
    setState(() => _loading = true);
    try {
      final ok = await GeoDataService.forceUpdate();
      if (!mounted) return;
      if (ok) {
        await _loadLastUpdated();
        AppNotifier.success(s.geoUpdated);
      } else {
        AppNotifier.error(s.geoUpdateFailed);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    String subtitle;
    if (!_loaded) {
      subtitle = '...';
    } else if (_lastUpdated != null) {
      final d = _lastUpdated!;
      subtitle =
          s.geoLastUpdated('${d.year}-${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}');
    } else {
      subtitle = s.noData;
    }
    return YLSettingsRow(
      title: s.geoDatabase,
      description: subtitle,
      trailing: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(
              onPressed: _update,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(s.geoUpdateNow, style: const TextStyle(fontSize: 12)),
            ),
    );
  }
}

class YLSettingsRow extends StatelessWidget {
  final String title;
  final String? description;
  final Widget trailing;

  const YLSettingsRow({
    super.key,
    required this.title,
    this.description,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? YLColors.zinc200 : YLColors.zinc700;
    final descColor = isDark ? YLColors.zinc500 : YLColors.zinc400;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: YLText.body.copyWith(color: titleColor)),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description!,
                      style: YLText.caption.copyWith(color: descColor)),
                ],
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}


