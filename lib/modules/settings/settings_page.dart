import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../modules/onboarding/ios_install_guide_page.dart';
import '../../modules/checkin/presentation/calendar_page.dart';
import '../../shared/formatters/subscription_parser.dart' show formatBytes;
import '../../shared/app_notifier.dart';
import '../../core/env_config.dart';
import '../updater/update_checker.dart';
import '../../shared/rich_content.dart';
import '../../shared/widgets/setting_icon.dart';
import '../../theme.dart';
import 'widgets/primitives.dart';
import '../../domain/account/account_overview.dart';
import '../mine/providers/account_providers.dart';
import '../surge_modules/pages/modules_page.dart';
import '../surge_modules/providers/module_provider.dart';

// Settings-level providers live in `providers/settings_providers.dart`;
// hotkey codec (parseStoredHotkey / displayHotkey) lives in `hotkey_codec.dart`.
// This page doesn't itself consume them anymore — consumers import those
// modules directly instead of reaching through the page file.

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
                    SettingsSectionTitle(s.sectionService),
                    SettingsCard(
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
                            Divider(
                                height: 1, thickness: 0.5, color: dividerColor),
                            YLInfoRow(
                              label: s.calendarEntryTitle,
                              leading: const YLSettingIcon(
                                  icon: Icons.calendar_month_outlined,
                                  color: Color(0xFF22C55E)),
                              trailing: const Icon(Icons.chevron_right,
                                  size: 18, color: YLColors.zinc400),
                              onTap: () =>
                                  CheckinCalendarPage.push(context),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // ══ 2. 设置（偏好 / 覆写 / 修复 / 模块）═══════════════
                    SettingsSectionTitle(s.sectionSettings),
                    SettingsCard(
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
                    SettingsSectionTitle(s.sectionAbout),
                    SettingsCard(
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
                                  ref.watch(appVersionProvider).value ??
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
                          if (Platform.isIOS) ...[
                            YLInfoRow(
                              label: s.iosGuideEntry,
                              leading: const YLSettingIcon(
                                  icon: Icons.phone_iphone,
                                  color: Color(0xFF8E8E93)),
                              trailing: const Icon(Icons.chevron_right,
                                  size: 18, color: YLColors.zinc400),
                              onTap: () =>
                                  IOSInstallGuidePage.push(context),
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
                                  ref.watch(appVersionProvider).value ??
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
    final overview = overviewAsync.value;

    // 始终显示，loading/error 时用占位数据
    final email = overview?.email ?? S.current.loading;
    final plan = overview?.planName ?? '--';

    return SettingsCard(
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
    final overview = overviewAsync.value;

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

    return SettingsCard(
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
    return SettingsCard(
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

// Primitive widgets (SettingsSectionTitle / SettingsCard / YLInfoRow /
// YLSettingsRow) live in `widgets/primitives.dart`.


