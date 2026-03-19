import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants.dart';
import 'web_page.dart';
import '../../l10n/app_strings.dart';
import '../../modules/profiles/profiles_page.dart';
import 'sub/general_settings_page.dart';
import '../../modules/store/store_page.dart';
import '../../modules/store/order_history_page.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../core/storage/auth_token_service.dart';
import '../../infrastructure/datasources/xboard_api.dart';
import '../../shared/formatters/subscription_parser.dart' show formatBytes;
import '../../providers/core_provider.dart';
import '../../shared/app_notifier.dart';
import '../../core/kernel/geodata_service.dart';
import '../../core/storage/settings_service.dart';
import '../../modules/nodes/providers/nodes_providers.dart';
import '../../services/update_checker.dart';
import '../../theme.dart';
import '../mine/widgets/account_card.dart';
import '../mine/widgets/traffic_usage_card.dart';

// ── Settings-level providers ─────────────────────────────────────────────────

final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final languageProvider = StateProvider<String>((ref) => 'zh');

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
    'a': LogicalKeyboardKey.keyA, 'b': LogicalKeyboardKey.keyB,
    'c': LogicalKeyboardKey.keyC, 'd': LogicalKeyboardKey.keyD,
    'e': LogicalKeyboardKey.keyE, 'f': LogicalKeyboardKey.keyF,
    'g': LogicalKeyboardKey.keyG, 'h': LogicalKeyboardKey.keyH,
    'i': LogicalKeyboardKey.keyI, 'j': LogicalKeyboardKey.keyJ,
    'k': LogicalKeyboardKey.keyK, 'l': LogicalKeyboardKey.keyL,
    'm': LogicalKeyboardKey.keyM, 'n': LogicalKeyboardKey.keyN,
    'o': LogicalKeyboardKey.keyO, 'p': LogicalKeyboardKey.keyP,
    'q': LogicalKeyboardKey.keyQ, 'r': LogicalKeyboardKey.keyR,
    's': LogicalKeyboardKey.keyS, 't': LogicalKeyboardKey.keyT,
    'u': LogicalKeyboardKey.keyU, 'v': LogicalKeyboardKey.keyV,
    'w': LogicalKeyboardKey.keyW, 'x': LogicalKeyboardKey.keyX,
    'y': LogicalKeyboardKey.keyY, 'z': LogicalKeyboardKey.keyZ,
    '0': LogicalKeyboardKey.digit0, '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2, '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4, '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6, '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8, '9': LogicalKeyboardKey.digit9,
  };
  return map[label.toLowerCase()] ?? LogicalKeyboardKey.keyC;
}

// ─────────────────────────────────────────────────────────────────────────────

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  UpdateInfo? _pendingUpdate;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateChecker.instance.check();
    if (mounted && info != null) {
      setState(() => _pendingUpdate = info);
    }
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
                        child: Text(
                          info.releaseNotes,
                          style: YLText.body.copyWith(color: YLColors.zinc500),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (downloading) ...[
                    LinearProgressIndicator(value: progress > 0 ? progress : null),
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
                            final path = await UpdateChecker.download(
                              info.downloadUrl!,
                              onProgress: (received, total) {
                                if (total > 0) {
                                  setDialog(() =>
                                      progress = received / total);
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
      } else if (Platform.isMacOS || Platform.isWindows) {
        // Open DMG/EXE via system default handler
        final uri = Uri.file(path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          // Fallback: use Process to open
          if (Platform.isMacOS) {
            await Process.run('open', [path]);
          } else {
            await Process.run('cmd', ['/c', 'start', '', path]);
          }
        }
      }
      AppNotifier.success(s.updateInstalling);
    } catch (e) {
      AppNotifier.error('${s.updateDownloadFailed}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final status = ref.watch(coreStatusProvider);
    final isGuest = ref.watch(authProvider).isGuest;

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
            padding: EdgeInsets.fromLTRB(32, MediaQuery.of(context).padding.top + 16, 32, 20),
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

              // ══ 0. Account card (top) ═════════════════════════════
              if (isGuest) ...[
                _GuestLoginCard(isDark: isDark),
              ] else ...[
                const AccountCard(),
                const SizedBox(height: 12),
                if (status == CoreStatus.running) ...[
                  const TrafficUsageCard(),
                ],
              ],

              // ══ 1. Service (订阅相关) ══════════════════════════════
              _SectionTitle(s.sectionService),
              _SettingsCard(
                child: Column(
                  children: [
                    YLInfoRow(
                      label: s.mineSubscriptionManage,
                      trailing: const Icon(Icons.chevron_right,
                          size: 18, color: YLColors.zinc400),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfilePage()),
                      ),
                    ),
                    if (!isGuest) ...[
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLInfoRow(
                        label: s.mineRenew,
                        trailing: const Icon(Icons.chevron_right,
                            size: 18, color: YLColors.zinc400),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const StorePage()),
                        ),
                      ),
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLInfoRow(
                        label: s.storeOrderHistory,
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

              // ══ 2. 通用 ══════════════════════════════════════════
              _SectionTitle(s.sectionSettings),
              _SettingsCard(
                child: Column(
                  children: [
                    YLInfoRow(
                      label: s.preferencesLabel,
                      trailing: const Icon(Icons.chevron_right,
                          size: 18, color: YLColors.zinc400),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const GeneralSettingsPage()),
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
                    YLInfoRow(
                      label: s.checkUpdate,
                      value: AppConstants.appVersion,
                      trailing: _checkingUpdate
                          ? const SizedBox(
                              width: 14, height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : _pendingUpdate != null
                              ? YLChip(
                                  s.updateAvailableV(
                                      _pendingUpdate!.latestVersion),
                                  color: isDark ? Colors.white : YLColors.primary)
                              : const Icon(Icons.chevron_right,
                                  size: 18, color: YLColors.zinc400),
                      onTap: _checkingUpdate
                          ? null
                          : _pendingUpdate != null
                              ? () => _showUpdateDialog(context, _pendingUpdate!)
                              : () async {
                                  setState(() => _checkingUpdate = true);
                                  final info =
                                      await UpdateChecker.instance.check();
                                  if (mounted) {
                                    setState(() {
                                      _pendingUpdate = info;
                                      _checkingUpdate = false;
                                    });
                                    if (info == null) {
                                      AppNotifier.info(s.alreadyLatest);
                                    } else {
                                      _showUpdateDialog(context, info);
                                    }
                                  }
                                },
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.mineTelegramGroup,
                      trailing: const Icon(Icons.chevron_right,
                          size: 18, color: YLColors.zinc400),
                      onTap: () async {
                        final tgUri = Uri.parse('tg://resolve?domain=yue_to');
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
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.minePrivacyPolicy,
                      trailing: const Icon(Icons.chevron_right,
                          size: 18, color: YLColors.zinc400),
                      onTap: () async {
                        const tosUrl = 'https://yue.to/tos.html';
                        if (Platform.isAndroid || Platform.isIOS) {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => InAppWebPage(
                              title: s.minePrivacyPolicy,
                              url: tosUrl,
                            ),
                          ));
                        } else {
                          final uri = Uri.parse(tosUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        }
                      },
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.openSourceLicense,
                      trailing: const Icon(Icons.chevron_right,
                          size: 18, color: YLColors.zinc400),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: AppConstants.appName,
                        applicationVersion: AppConstants.appVersion,
                      ),
                    ),
                  ],
                ),
              ),
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

  void _showChangePasswordDialog(BuildContext context, S s) {
    final oldPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.mineChangePassword),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPwCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: s.oldPassword),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPwCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: s.newPassword),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final oldPw = oldPwCtrl.text.trim();
              final newPw = newPwCtrl.text.trim();
              if (oldPw.isEmpty || newPw.isEmpty) return;
              Navigator.pop(ctx);
              await _doChangePassword(oldPw, newPw);
            },
            child: Text(s.confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _doChangePassword(String oldPassword, String newPassword) async {
    final s = S.current;
    final token = ref.read(authProvider).token;
    if (token == null) return;
    try {
      final host = await AuthTokenService.instance.getApiHost() ??
          'https://d7ccm19ki90mg.cloudfront.net';
      final api = XBoardApi(baseUrl: host);
      await api.changePassword(
        token: token,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      AppNotifier.success(s.passwordChangedSuccess);
    } on XBoardApiException catch (e) {
      final msg = e.message;
      AppNotifier.error(
        msg.isNotEmpty && msg.length < 80 && !msg.startsWith('{')
            ? msg
            : s.passwordChangeFailed,
      );
    } catch (_) {
      AppNotifier.error(s.passwordChangeFailed);
    }
  }

  void _confirmLogout(BuildContext context, S s, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.authLogout),
        content: Text(s.authLogoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: YLColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            child: Text(s.authLogout),
          ),
        ],
      ),
    );
  }
}

// ── Account section (superseded by AccountCard; retained for reference) ────────

// ignore: unused_element
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authProvider);
    final profile = authState.userProfile;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    if (!authState.isLoggedIn) {
      return _SettingsCard(
        child: YLInfoRow(
          label: s.authLogin,
          trailing: const Icon(Icons.chevron_right,
              size: 18, color: YLColors.zinc400),
          onTap: () => ref.read(authProvider.notifier).logout(),
        ),
      );
    }

    return _SettingsCard(
      child: Column(
        children: [
          // Email
          YLInfoRow(
            label: s.authEmail,
            value: profile?.email ?? '—',
          ),
          Divider(height: 1, thickness: 0.5, color: dividerColor),
          // Plan
          if (profile?.planName != null) ...[
            YLInfoRow(
              label: s.authPlan,
              value: profile!.planName!,
            ),
            Divider(height: 1, thickness: 0.5, color: dividerColor),
          ],
          // Traffic
          if (profile?.transferEnable != null) ...[
            YLInfoRow(
              label: s.authTraffic,
              value: '${formatBytes(profile!.remaining ?? 0)} / ${formatBytes(profile.transferEnable!)}',
            ),
            Divider(height: 1, thickness: 0.5, color: dividerColor),
          ],
          // Expiry
          if (profile != null) ...[
            YLInfoRow(
              label: s.authExpiry,
              value: profile.isExpired
                  ? s.authExpired
                  : profile.daysRemaining != null
                      ? s.authDaysRemaining(profile.daysRemaining!)
                      : '—',
            ),
            Divider(height: 1, thickness: 0.5, color: dividerColor),
          ],
          // Refresh
          YLInfoRow(
            label: s.authRefreshInfo,
            trailing: const Icon(Icons.refresh, size: 18, color: YLColors.zinc400),
            onTap: () => ref.read(authProvider.notifier).refreshUserInfo(),
          ),
          Divider(height: 1, thickness: 0.5, color: dividerColor),
          // Sync subscription
          YLInfoRow(
            label: s.authSyncingSubscription.replaceAll('...', '').replaceAll('正在', ''),
            trailing: const Icon(Icons.sync, size: 18, color: YLColors.zinc400),
            onTap: () => ref.read(authProvider.notifier).syncSubscription(),
          ),
          Divider(height: 1, thickness: 0.5, color: dividerColor),
          // Logout
          YLInfoRow(
            label: s.authLogout,
            trailing: const Icon(Icons.logout, size: 18, color: YLColors.error),
            onTap: () => _confirmLogout(context, ref, s),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref, S s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.authLogout),
        content: Text(s.authLogoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            style: FilledButton.styleFrom(
              backgroundColor: YLColors.error,
            ),
            child: Text(s.authLogout),
          ),
        ],
      ),
    );
  }
}

/// Guest mode login prompt card for the Mine page.
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
            Icon(Icons.account_circle_outlined,
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
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
          color: YLColors.zinc400,
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
  final VoidCallback? onTap;
  final bool enabled;
  final TextStyle? labelStyle;

  const YLInfoRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
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
          Expanded(
            child: Text(label, style: labelStyle ?? YLText.body.copyWith(color: labelColor)),
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

// ── Close behavior row (desktop) ─────────────────────────────────────────────

class _CloseBehaviorRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final behavior = ref.watch(closeBehaviorProvider);
    return YLInfoRow(
      label: s.closeWindowBehavior,
      trailing: SizedBox(
        width: 260,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 12),
          ),
          segments: [
            ButtonSegment(value: 'tray', label: Text(s.closeBehaviorTray)),
            ButtonSegment(value: 'exit', label: Text(s.closeBehaviorExit)),
          ],
          selected: {behavior},
          onSelectionChanged: (v) async {
            final val = v.first;
            ref.read(closeBehaviorProvider.notifier).state = val;
            await SettingsService.setCloseBehavior(val);
          },
        ),
      ),
    );
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
                  child: Text(s.hotkeyEdit,
                      style: const TextStyle(fontSize: 12)),
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
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(s.cancel)),
        ],
      ),
    ).whenComplete(focusNode.dispose);
  }
}

// ── GeoData row ───────────────────────────────────────────────────────────────

// ── Linux proxy notice row ────────────────────────────────────────────────────

class _LinuxProxyNoticeRow extends StatelessWidget {
  const _LinuxProxyNoticeRow();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: YLColors.zinc400),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.linuxProxyNotice,
                    style: YLText.body.copyWith(
                        color: isDark ? YLColors.zinc200 : YLColors.zinc700)),
                const SizedBox(height: 2),
                Text(s.linuxProxyManual,
                    style: YLText.caption.copyWith(
                        fontFamily: 'monospace', color: YLColors.zinc400)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
    if (mounted) setState(() { _lastUpdated = dt; _loaded = true; });
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
      subtitle = s.geoLastUpdated(
          '${d.year}-${d.month.toString().padLeft(2, '0')}-'
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
              child: Text(s.geoUpdateNow,
                  style: const TextStyle(fontSize: 12)),
            ),
    );
  }
}

// ── Test URL row (hidden for 悦通 client; retained for future use) ─────────────

// ignore: unused_element
class _TestUrlRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = ref.watch(testUrlProvider);
    const defaultUrl = 'https://www.gstatic.com/generate_204';

    // Shorten the URL for display: strip https:// and truncate if long
    final display = url
        .replaceFirst('https://', '')
        .replaceFirst('http://', '');
    final truncated =
        display.length > 32 ? '${display.substring(0, 30)}…' : display;

    return InkWell(
      onTap: () => _showEditDialog(context, ref, s, url, defaultUrl),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(s.testUrlSettings,
                  style: YLText.body.copyWith(
                      color: isDark ? YLColors.zinc200 : YLColors.zinc700)),
            ),
            Text(
              truncated,
              style: YLText.body.copyWith(
                  color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                  fontFamily: 'monospace',
                  fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined, size: 14, color: YLColors.zinc400),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref, S s,
      String currentUrl, String defaultUrl) async {
    final ctrl = TextEditingController(text: currentUrl);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: Text(s.testUrlDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  hintText: defaultUrl,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  ctrl.text = defaultUrl;
                  setModal(() {});
                },
                icon: const Icon(Icons.restore, size: 14),
                label: Text(s.resetDefault,
                    style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.cancel)),
            FilledButton(
              onPressed: () async {
                final url = ctrl.text.trim();
                if (url.isEmpty) return;
                Navigator.pop(ctx);
                ref.read(testUrlProvider.notifier).state = url;
                await SettingsService.setTestUrl(url);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }
}

/// A settings row with a title, optional description, and a trailing widget.
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

// ── Upstream Proxy Row ────────────────────────────────────────────────────────

class _UpstreamProxyRow extends StatefulWidget {
  const _UpstreamProxyRow();

  @override
  State<_UpstreamProxyRow> createState() => _UpstreamProxyRowState();
}

class _UpstreamProxyRowState extends State<_UpstreamProxyRow> {
  bool _enabled = false;
  String _type = 'socks5';
  String _server = '';
  int _port = 1080;
  bool _detecting = false;
  String? _detectedInfo; // e.g. "192.168.1.1:7890"

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await SettingsService.load();
    final raw = settings['upstreamProxy'];
    if (raw is Map) {
      final enabled = raw['enabled'] == true;
      final server = raw['server'] as String? ?? '';
      final port = (raw['port'] as int?) ?? 1080;
      final type = raw['type'] as String? ?? 'socks5';
      setState(() {
        _enabled = enabled;
        _server = server;
        _port = port;
        _type = type;
        if (enabled && server.isNotEmpty) {
          _detectedInfo = '$server:$port';
        }
      });
    }
  }

  Future<String?> _detectGatewayIp() async {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final parts = addr.address.split('.');
        if (parts.length == 4) {
          return '${parts[0]}.${parts[1]}.${parts[2]}.1';
        }
      }
    }
    return null;
  }

  /// Returns (port, type) or null if nothing found.
  Future<({int port, String type})?> _detectProxy(String host) async {
    for (final port in [7890, 1080, 7891, 10809, 1081, 8080]) {
      try {
        final s = await Socket.connect(host, port,
            timeout: const Duration(milliseconds: 500));
        // Probe SOCKS5: send greeting [0x05, 0x01, 0x00]
        // A SOCKS5 server replies with [0x05, 0x??]
        final type = await _probeType(s);
        s.destroy();
        return (port: port, type: type);
      } catch (_) {}
    }
    return null;
  }

  /// Sends a SOCKS5 greeting; returns 'socks5' if server responds with 0x05,
  /// otherwise falls back to 'http'.
  Future<String> _probeType(Socket s) async {
    final completer = Completer<String>();
    s.add([0x05, 0x01, 0x00]); // SOCKS5 handshake
    late StreamSubscription sub;
    sub = s.listen(
      (data) {
        sub.cancel();
        if (!completer.isCompleted) {
          completer.complete(data.isNotEmpty && data[0] == 0x05 ? 'socks5' : 'http');
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete('http');
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete('http');
      },
    );
    return completer.future.timeout(const Duration(milliseconds: 400),
        onTimeout: () {
      sub.cancel();
      return 'socks5'; // assume socks5 if no response (common with mihomo)
    });
  }

  Future<void> _autoDetect() async {
    setState(() => _detecting = true);
    try {
      final gateway = await _detectGatewayIp();
      if (gateway == null) {
        if (mounted) AppNotifier.error(S.of(context).upstreamProxyNotFound);
        setState(() {
          _enabled = false;
          _detecting = false;
        });
        return;
      }
      final result = await _detectProxy(gateway);
      if (result == null) {
        if (mounted) AppNotifier.error(S.of(context).upstreamProxyNotFound);
        setState(() {
          _enabled = false;
          _detecting = false;
        });
        return;
      }
      _server = gateway;
      _port = result.port;
      _type = result.type;
      await SettingsService.setUpstreamProxy(
        enabled: true,
        type: _type,
        server: _server,
        port: _port,
      );
      if (mounted) {
        setState(() {
          _detectedInfo = '$gateway:${result.port}';
          _detecting = false;
        });
        AppNotifier.success(S.of(context).upstreamProxySaved);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _enabled = false;
          _detecting = false;
        });
      }
    }
  }

  Future<void> _disable() async {
    await SettingsService.setUpstreamProxy(
      enabled: false,
      type: _type,
      server: _server,
      port: _port,
    );
    setState(() {
      _enabled = false;
      _detectedInfo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final subtitle = _enabled && _detectedInfo != null
        ? '$_type  $_detectedInfo'
        : s.upstreamProxySub;

    return YLSettingsRow(
      title: s.upstreamProxy,
      description: subtitle,
      trailing: _detecting
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : CupertinoSwitch(
              value: _enabled,
              activeTrackColor: YLColors.connected,
              onChanged: (v) {
                if (v) {
                  setState(() => _enabled = true);
                  _autoDetect();
                } else {
                  _disable();
                }
              },
            ),
    );
  }
}

// ── Export Logs Sheet (hidden for 悦通 client; retained for future use) ────────

// ignore: unused_element
class _ExportLogsSheet {
  // ignore: unused_element
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ExportLogsContent(),
    );
  }
}

class _ExportLogsContent extends StatefulWidget {
  const _ExportLogsContent();

  @override
  State<_ExportLogsContent> createState() => _ExportLogsContentState();
}

class _ExportLogsContentState extends State<_ExportLogsContent>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String? _crashLog;
  String? _coreLog;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadLogs();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final crashFile = File('${dir.path}/crash.log');
      final coreFile = File('${dir.path}/core.log');
      setState(() {
        _crashLog =
            crashFile.existsSync() ? crashFile.readAsStringSync() : null;
        _coreLog = coreFile.existsSync() ? coreFile.readAsStringSync() : null;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _copy(String? text) {
    if (text == null || text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    AppNotifier.success(S.of(context).exportLogsCopied);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? YLColors.zinc800 : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(YLRadius.xl)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: YLColors.zinc300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(s.exportLogs, style: YLText.titleMedium),
                  const Spacer(),
                  TabBar(
                    controller: _tab,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelStyle: YLText.caption
                        .copyWith(fontWeight: FontWeight.w600),
                    unselectedLabelStyle: YLText.caption,
                    indicatorColor: YLColors.connected,
                    labelColor: YLColors.connected,
                    unselectedLabelColor: YLColors.zinc500,
                    tabs: [
                      Tab(text: s.exportLogsCrash),
                      Tab(text: s.exportLogsCore),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : TabBarView(
                      controller: _tab,
                      children: [
                        _LogPane(
                          content: _crashLog,
                          onCopy: () => _copy(_crashLog),
                        ),
                        _LogPane(
                          content: _coreLog,
                          onCopy: () => _copy(_coreLog),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogPane extends StatelessWidget {
  final String? content;
  final VoidCallback onCopy;

  const _LogPane({required this.content, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasContent = content != null && content!.isNotEmpty;

    return Column(
      children: [
        if (hasContent)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 14),
                  label: Text(s.copiedToClipboard.replaceFirst('已', '复制')),
                  style: TextButton.styleFrom(
                    foregroundColor: YLColors.connected,
                    textStyle: YLText.caption,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: hasContent
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    content!,
                    style: YLText.caption.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                    ),
                  ),
                )
              : Center(
                  child: Text(
                    s.exportLogsEmpty,
                    style: YLText.body.copyWith(color: YLColors.zinc400),
                  ),
                ),
        ),
      ],
    );
  }
}
