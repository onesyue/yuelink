import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../core/platform/vpn_service.dart';
import '../../../core/service/service_manager.dart';
import '../../../core/service/service_models.dart';
import '../../../core/service/service_mode_provider.dart';
import '../../../core/storage/settings_service.dart';
import '../../../core/env_config.dart';
import '../../../i18n/app_strings.dart';
import '../../../core/providers/core_provider.dart';
import '../../updater/update_checker.dart';
import '../providers/split_tunnel_provider.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';
import '../settings_page.dart';

/// Standalone settings sub-page — displays all general settings
/// (theme, language, auto-connect, routing, connection mode, etc.)
/// as a secondary page with an AppBar, consistent with other sub-pages.
class GeneralSettingsPage extends ConsumerStatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  ConsumerState<GeneralSettingsPage> createState() =>
      _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends ConsumerState<GeneralSettingsPage> {
  bool _launchAtStartup = false;
  bool _serviceBusy = false;
  String _updateChannel = 'stable';
  bool _autoCheckUpdates = true;
  DateTime? _lastUpdateCheck;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final startup = await SettingsService.getLaunchAtStartup();
    final channel = await UpdateChecker.getChannel();
    final autoCheck = await UpdateChecker.getAutoCheck();
    final lastCheck = await UpdateChecker.getLastCheck();
    if (mounted) {
      setState(() {
        _launchAtStartup = startup;
        _updateChannel = channel;
        _autoCheckUpdates = autoCheck;
        _lastUpdateCheck = lastCheck;
      });
    }
  }

  String _formatLastChecked(DateTime? dt, {required bool isEn}) {
    if (dt == null) return isEn ? 'Never checked' : '从未检查';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return isEn ? 'Just now' : '刚刚';
    if (diff.inMinutes < 60) {
      return isEn ? '${diff.inMinutes} min ago' : '${diff.inMinutes} 分钟前';
    }
    if (diff.inHours < 24) {
      return isEn ? '${diff.inHours} h ago' : '${diff.inHours} 小时前';
    }
    if (diff.inDays < 30) {
      return isEn ? '${diff.inDays} d ago' : '${diff.inDays} 天前';
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _refreshDesktopService() async {
    ref.read(desktopServiceRefreshProvider.notifier).state++;
  }

  Future<void> _installDesktopService() async {
    if (_serviceBusy) return;
    final s = S.of(context);
    setState(() => _serviceBusy = true);
    try {
      await ServiceManager.install();
      await _refreshDesktopService();
      if (!mounted) return;
      AppNotifier.success(s.serviceModeInstallOk);
    } catch (e) {
      if (!mounted) return;
      AppNotifier.error(
        s.serviceModeInstallFailed(e.toString().split('\n').first),
      );
    } finally {
      if (mounted) setState(() => _serviceBusy = false);
    }
  }

  Future<void> _uninstallDesktopService(CoreStatus status) async {
    if (_serviceBusy) return;
    final s = S.of(context);
    setState(() => _serviceBusy = true);
    try {
      if (status == CoreStatus.running) {
        await ref.read(coreActionsProvider).stop();
      }
      await ServiceManager.uninstall();
      await _refreshDesktopService();
      if (!mounted) return;
      AppNotifier.success(s.serviceModeUninstallOk);
    } catch (e) {
      if (!mounted) return;
      AppNotifier.error(
        s.serviceModeUninstallFailed(e.toString().split('\n').first),
      );
    } finally {
      if (mounted) setState(() => _serviceBusy = false);
    }
  }

  Future<void> _updateDesktopService() async {
    if (_serviceBusy) return;
    final s = S.of(context);
    setState(() => _serviceBusy = true);
    try {
      await ServiceManager.update();
      await _refreshDesktopService();
      if (!mounted) return;
      AppNotifier.success(s.serviceModeUpdateOk);
    } catch (e) {
      if (!mounted) return;
      AppNotifier.error(
        s.serviceModeUpdateFailed(e.toString().split('\n').first),
      );
    } finally {
      if (mounted) setState(() => _serviceBusy = false);
    }
  }

  String _serviceDescription(
    S s,
    AsyncValue<DesktopServiceInfo> serviceInfo,
  ) {
    final info = serviceInfo.valueOrNull;
    if (serviceInfo.isLoading && info == null) {
      return '...';
    }
    if (info == null || info.installed == false) {
      return s.serviceModeNotInstalled;
    }
    if (!info.reachable) {
      return info.detail?.isNotEmpty == true
          ? '${s.serviceModeUnreachable} · ${info.detail}'
          : s.serviceModeUnreachable;
    }
    if (info.needsReinstall) {
      return s.serviceModeNeedsUpdate(info.serviceVersion ?? '?');
    }
    if (info.mihomoRunning) {
      return s.serviceModeRunning(info.pid ?? 0);
    }
    return s.serviceModeIdle;
  }

  Future<void> _showTunBypassEditor(BuildContext context) async {
    final s = S.of(context);
    final addrs = await SettingsService.getTunBypassAddresses();
    final procs = await SettingsService.getTunBypassProcesses();
    final addrCtrl = TextEditingController(text: addrs.join('\n'));
    final procCtrl = TextEditingController(text: procs.join('\n'));

    // Use context.mounted (not just State.mounted) to guarantee the
    // captured BuildContext itself is still valid after the awaits — the
    // State.mounted check is unrelated to the specific context tree this
    // function received.
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.tunBypassLabel),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.tunBypassAddrHint,
                    style: YLText.caption.copyWith(color: YLColors.zinc500)),
                const SizedBox(height: 4),
                TextField(
                  controller: addrCtrl,
                  maxLines: 5,
                  style: YLText.body,
                  decoration: InputDecoration(
                    hintText: '192.168.0.0/16\n10.0.0.0/8',
                    hintStyle: YLText.body.copyWith(color: YLColors.zinc400),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                Text(s.tunBypassProcHint,
                    style: YLText.caption.copyWith(color: YLColors.zinc500)),
                const SizedBox(height: 4),
                TextField(
                  controller: procCtrl,
                  maxLines: 5,
                  style: YLText.body,
                  decoration: InputDecoration(
                    hintText: 'ssh\nParallels Desktop',
                    hintStyle: YLText.body.copyWith(color: YLColors.zinc400),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final newAddrs = addrCtrl.text
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .toList();
              final newProcs = procCtrl.text
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .toList();
              await SettingsService.setTunBypassAddresses(newAddrs);
              await SettingsService.setTunBypassProcesses(newProcs);
              if (ctx.mounted) Navigator.pop(ctx);
              AppNotifier.success(s.tunBypassSaved);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
    addrCtrl.dispose();
    procCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final theme = ref.watch(themeProvider);
    final accentHex = ref.watch(accentColorProvider);
    final subSyncInterval = ref.watch(subSyncIntervalProvider);
    final language = ref.watch(languageProvider);
    final autoConnect = ref.watch(autoConnectProvider);
    final connectionMode = ref.watch(connectionModeProvider);
    final desktopTunStack = ref.watch(desktopTunStackProvider);
    final systemProxyOnConnect = ref.watch(systemProxyOnConnectProvider);
    final status = ref.watch(coreStatusProvider);
    final serviceInfo = ref.watch(desktopServiceInfoProvider);
    final routingMode = ref.watch(routingModeProvider);
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(s.preferencesLabel),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              _Card(
                child: Column(
                  children: [
                    // Theme
                    YLInfoRow(
                      label: s.themeLabel,
                      trailing: SizedBox(
                        width: 240,
                        child: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          segments: [
                            ButtonSegment(
                                value: ThemeMode.system,
                                label: Text(s.themeSystem)),
                            ButtonSegment(
                                value: ThemeMode.light,
                                label: Text(s.themeLight)),
                            ButtonSegment(
                                value: ThemeMode.dark,
                                label: Text(s.themeDark)),
                          ],
                          selected: {theme},
                          onSelectionChanged: (v) {
                            ref.read(themeProvider.notifier).state = v.first;
                            SettingsService.setThemeMode(v.first);
                          },
                        ),
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Accent color
                    _AccentColorRow(
                      currentHex: accentHex,
                      onChanged: (hex) {
                        ref.read(accentColorProvider.notifier).state = hex;
                        SettingsService.setAccentColor(hex);
                      },
                      isEn: isEn,
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Language
                    YLInfoRow(
                      label: s.sectionLanguage,
                      trailing: SizedBox(
                        width: 160,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          segments: [
                            ButtonSegment(
                                value: 'zh', label: Text(s.languageChinese)),
                            ButtonSegment(
                                value: 'en', label: Text(s.languageEnglish)),
                          ],
                          selected: {language},
                          onSelectionChanged: (v) async {
                            ref.read(languageProvider.notifier).state = v.first;
                            await SettingsService.setLanguage(v.first);
                          },
                        ),
                      ),
                    ),
                    if (EnvConfig.isStandalone) ...[
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLInfoRow(
                        label: isEn ? 'Last checked' : '上次检查',
                        value: _formatLastChecked(
                          _lastUpdateCheck,
                          isEn: isEn,
                        ),
                        trailing: const SizedBox.shrink(),
                      ),
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLSettingsRow(
                        title: isEn
                            ? 'Auto-check updates on startup'
                            : '启动时自动检查更新',
                        trailing: CupertinoSwitch(
                          value: _autoCheckUpdates,
                          activeTrackColor: YLColors.connected,
                          onChanged: (v) async {
                            await UpdateChecker.setAutoCheck(v);
                            if (mounted) setState(() => _autoCheckUpdates = v);
                          },
                        ),
                      ),
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLInfoRow(
                        label: isEn ? 'Update channel' : '更新通道',
                        value: _updateChannel == 'pre'
                            ? (isEn ? 'Pre-release' : '预发布')
                            : (isEn ? 'Stable' : '稳定版'),
                        trailing: const Icon(Icons.chevron_right,
                            size: 18, color: YLColors.zinc400),
                        onTap: () async {
                          final picked = await showModalBottomSheet<String>(
                            context: context,
                            builder: (ctx) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    title: Text(
                                      isEn ? 'Stable (stable)' : '稳定版 (stable)',
                                    ),
                                    subtitle: Text(
                                      isEn
                                          ? 'Only receive formal v* releases'
                                          : '只接收正式 v* 版本，更稳定',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: _updateChannel == 'stable'
                                        ? const Icon(Icons.check,
                                            color: YLColors.primary)
                                        : null,
                                    onTap: () => Navigator.pop(ctx, 'stable'),
                                  ),
                                  ListTile(
                                    title: Text(
                                      isEn
                                          ? 'Pre-release (pre-release)'
                                          : '预发布 (pre-release)',
                                    ),
                                    subtitle: Text(
                                      isEn
                                          ? 'Get new builds early, may be unstable'
                                          : '抢先体验新功能，可能有问题',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: _updateChannel == 'pre'
                                        ? const Icon(Icons.check,
                                            color: YLColors.primary)
                                        : null,
                                    onTap: () => Navigator.pop(ctx, 'pre'),
                                  ),
                                ],
                              ),
                            ),
                          );
                          if (picked != null && picked != _updateChannel) {
                            await UpdateChecker.setChannel(picked);
                            if (mounted) setState(() => _updateChannel = picked);
                          }
                        },
                      ),
                    ],
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Auto connect
                    YLSettingsRow(
                      title: s.autoConnect,
                      trailing: CupertinoSwitch(
                        value: autoConnect,
                        activeTrackColor: YLColors.connected,
                        onChanged: (v) async {
                          ref.read(autoConnectProvider.notifier).state = v;
                          await SettingsService.setAutoConnect(v);
                        },
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Subscription sync interval
                    YLInfoRow(
                      label: isEn ? 'Subscription update' : '订阅更新频率',
                      trailing: DropdownButton<int>(
                        value: subSyncInterval,
                        underline: const SizedBox.shrink(),
                        style: YLText.body.copyWith(
                          color: isDark ? YLColors.zinc200 : YLColors.zinc700,
                        ),
                        dropdownColor: isDark ? YLColors.zinc800 : Colors.white,
                        items: [
                          DropdownMenuItem(value: 0, child: Text(isEn ? 'Manual' : '手动')),
                          DropdownMenuItem(value: 1, child: Text(isEn ? 'Every hour' : '每小时')),
                          DropdownMenuItem(value: 6, child: Text(isEn ? 'Every 6 hours' : '每6小时')),
                          DropdownMenuItem(value: 12, child: Text(isEn ? 'Every 12 hours' : '每12小时')),
                          DropdownMenuItem(value: 24, child: Text(isEn ? 'Every day' : '每天')),
                          DropdownMenuItem(value: 48, child: Text(isEn ? 'Every 2 days' : '每2天')),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          ref.read(subSyncIntervalProvider.notifier).state = v;
                          await SettingsService.setSubSyncInterval(v);
                        },
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Routing mode
                    YLInfoRow(
                      label: s.routingModeSetting,
                      trailing: SizedBox(
                        width: 200,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          segments: [
                            ButtonSegment(
                                value: 'rule', label: Text(s.routeModeRule)),
                            ButtonSegment(
                                value: 'global',
                                label: Text(s.routeModeGlobal)),
                            ButtonSegment(
                                value: 'direct',
                                label: Text(s.routeModeDirect)),
                          ],
                          selected: {routingMode},
                          onSelectionChanged: (v) async {
                            final mode = v.first;
                            ref.read(routingModeProvider.notifier).state = mode;
                            await SettingsService.setRoutingMode(mode);
                            if (status == CoreStatus.running) {
                              try {
                                await CoreManager.instance.api
                                    .setRoutingMode(mode);
                              } catch (_) {}
                            }
                          },
                        ),
                      ),
                    ),
                    // Connection mode & system proxy: desktop only
                    if (Platform.isMacOS ||
                        Platform.isWindows ||
                        Platform.isLinux) ...[
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLInfoRow(
                        label: s.connectionMode,
                        trailing: DropdownButton<String>(
                          value: connectionMode,
                          underline: const SizedBox.shrink(),
                          style: YLText.body.copyWith(
                            color: isDark ? YLColors.zinc200 : YLColors.zinc700,
                          ),
                          dropdownColor:
                              isDark ? YLColors.zinc800 : Colors.white,
                          items: [
                            DropdownMenuItem(
                                value: 'tun', child: Text(s.modeTun)),
                            DropdownMenuItem(
                                value: 'systemProxy',
                                child: Text(s.modeSystemProxy)),
                          ],
                          onChanged: (v) async {
                            if (v == null || v == connectionMode) return;
                            ref.read(connectionModeProvider.notifier).state = v;
                            await SettingsService.setConnectionMode(v);

                            // Hot-switch: if core is running, apply mode
                            // change without stop+start
                            final status = ref.read(coreStatusProvider);
                            if (status == CoreStatus.running) {
                              final actions = ref.read(coreActionsProvider);
                              await actions.hotSwitchConnectionMode(v);
                            }
                          },
                        ),
                      ),
                      if (connectionMode == 'tun') ...[
                        Divider(height: 1, thickness: 0.5, color: dividerColor),
                        YLSettingsRow(
                          title: s.serviceModeLabel,
                          description: _serviceDescription(s, serviceInfo),
                          trailing: _serviceBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: _refreshDesktopService,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      child: Text(
                                        s.serviceModeRefresh,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    if (serviceInfo.valueOrNull?.installed ==
                                        true) ...[
                                      if (serviceInfo
                                              .valueOrNull?.needsReinstall ==
                                          true)
                                        FilledButton(
                                          onPressed: _updateDesktopService,
                                          style: FilledButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                          child: Text(
                                            s.serviceModeUpdate,
                                            style:
                                                const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      TextButton(
                                        onPressed: () =>
                                            _uninstallDesktopService(status),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                        ),
                                        child: Text(
                                          s.serviceModeUninstall,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ] else
                                      FilledButton(
                                        onPressed: _installDesktopService,
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                        child: Text(
                                          s.serviceModeInstall,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                        Divider(height: 1, thickness: 0.5, color: dividerColor),
                        YLInfoRow(
                          label: s.tunStackLabel,
                          trailing: DropdownButton<String>(
                            value: desktopTunStack,
                            underline: const SizedBox.shrink(),
                            style: YLText.body.copyWith(
                              color:
                                  isDark ? YLColors.zinc200 : YLColors.zinc700,
                            ),
                            dropdownColor:
                                isDark ? YLColors.zinc800 : Colors.white,
                            items: [
                              DropdownMenuItem(
                                value: 'mixed',
                                child: Text(s.tunStackMixed),
                              ),
                              DropdownMenuItem(
                                value: 'system',
                                child: Text(s.tunStackSystem),
                              ),
                              DropdownMenuItem(
                                value: 'gvisor',
                                child: Text(s.tunStackGvisor),
                              ),
                            ],
                            onChanged: (v) async {
                              if (v == null) return;
                              ref.read(desktopTunStackProvider.notifier).state =
                                  v;
                              await SettingsService.setDesktopTunStack(v);
                            },
                          ),
                        ),
                        Divider(height: 1, thickness: 0.5, color: dividerColor),
                        GestureDetector(
                          onTap: () => _showTunBypassEditor(context),
                          behavior: HitTestBehavior.opaque,
                          child: YLSettingsRow(
                            title: s.tunBypassLabel,
                            description: s.tunBypassSub,
                            trailing: Icon(
                              Icons.chevron_right,
                              color:
                                  isDark ? YLColors.zinc400 : YLColors.zinc500,
                            ),
                          ),
                        ),
                      ],
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLSettingsRow(
                        title: s.setSystemProxyOnConnect,
                        description: s.setSystemProxyOnConnectSub,
                        trailing: CupertinoSwitch(
                          value: systemProxyOnConnect,
                          activeTrackColor: YLColors.connected,
                          onChanged: (v) async {
                            ref
                                .read(systemProxyOnConnectProvider.notifier)
                                .state = v;
                            await SettingsService.setSystemProxyOnConnect(v);
                          },
                        ),
                      ),
                    ],
                    if (isDesktop) ...[
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLSettingsRow(
                        title: s.launchAtStartupLabel,
                        description: s.launchAtStartupSub,
                        trailing: CupertinoSwitch(
                          value: _launchAtStartup,
                          activeTrackColor: YLColors.connected,
                          onChanged: (v) async {
                            setState(() => _launchAtStartup = v);
                            await SettingsService.setLaunchAtStartup(v);
                            if (v) {
                              await launchAtStartup.enable();
                            } else {
                              await launchAtStartup.disable();
                            }
                          },
                        ),
                      ),
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      if (!Platform.isLinux) ...[
                        _CloseBehaviorRow(),
                        Divider(height: 1, thickness: 0.5, color: dividerColor),
                      ],
                      _HotkeyRow(),
                    ],
                  ],
                ),
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 16),
                const _SplitTunnelSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

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
                  color: isDark ? YLColors.zinc300 : YLColors.zinc600,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _registering ? null : () => _startRecording(s),
                child: Text(_registering ? s.hotkeyListening : s.hotkeyEdit),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _startRecording(S s) {
    setState(() => _registering = true);
    final focusNode = FocusNode();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(s.hotkeyListening),
        content: KeyboardListener(
          focusNode: focusNode..requestFocus(),
          autofocus: true,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent) return;
            if (_isModifierOnly(event.logicalKey)) return;

            final parts = <String>[];
            if (HardwareKeyboard.instance.isControlPressed) parts.add('ctrl');
            if (HardwareKeyboard.instance.isAltPressed) parts.add('alt');
            if (HardwareKeyboard.instance.isShiftPressed) parts.add('shift');
            if (HardwareKeyboard.instance.isMetaPressed) parts.add('meta');

            final label = event.logicalKey.keyLabel.toLowerCase();
            if (label.isNotEmpty && !parts.contains(label)) parts.add(label);

            if (parts.length >= 2) {
              final combo = parts.join('+');
              ref.read(toggleHotkeyProvider.notifier).state = combo;
              SettingsService.setToggleHotkey(combo);
              Navigator.pop(ctx);
            }
          },
          child: SizedBox(
            height: 60,
            child: Center(
              child: Text(
                s.isEn ? 'Press your shortcut...' : '请按下快捷键...',
                style: YLText.body.copyWith(color: YLColors.zinc500),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
        ],
      ),
    ).whenComplete(() {
      setState(() => _registering = false);
      focusNode.dispose();
    });
  }

  bool _isModifierOnly(LogicalKeyboardKey key) {
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
}

// ── Split Tunnel (Android only) ──────────────────────────────────────────────

class _SplitTunnelSection extends ConsumerStatefulWidget {
  const _SplitTunnelSection();

  @override
  ConsumerState<_SplitTunnelSection> createState() =>
      _SplitTunnelSectionState();
}

class _SplitTunnelSectionState extends ConsumerState<_SplitTunnelSection> {
  List<Map<String, String>>? _apps;
  String _search = '';
  bool _loading = false;
  String? _loadError;

  Future<void> _loadApps() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final apps = await VpnService.getInstalledApps(showSystem: true);
      if (mounted) {
        setState(() {
          _apps = apps;
          _loading = false;
          if (apps.isEmpty) {
            _loadError = S.of(context).isEn
                ? 'No apps found. Your device may restrict app visibility.'
                : '未获取到应用列表，可能受系统权限限制。';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _apps = [];
          _loading = false;
          _loadError =
              S.of(context).isEn ? 'Failed to load apps: $e' : '加载应用列表失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode = ref.watch(splitTunnelModeProvider);
    final selectedPkgs = ref.watch(splitTunnelAppsProvider);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return _Card(
      child: Column(
        children: [
          // Mode selector
          YLInfoRow(
            label: s.splitTunnelMode,
            trailing: DropdownButton<SplitTunnelMode>(
              value: mode,
              underline: const SizedBox.shrink(),
              style: YLText.body.copyWith(
                color: isDark ? YLColors.zinc200 : YLColors.zinc700,
              ),
              dropdownColor: isDark ? YLColors.zinc800 : Colors.white,
              items: [
                DropdownMenuItem(
                    value: SplitTunnelMode.all,
                    child: Text(s.splitTunnelModeAll)),
                DropdownMenuItem(
                    value: SplitTunnelMode.whitelist,
                    child: Text(s.splitTunnelModeWhitelist)),
                DropdownMenuItem(
                    value: SplitTunnelMode.blacklist,
                    child: Text(s.splitTunnelModeBlacklist)),
              ],
              onChanged: (v) {
                if (v != null) {
                  ref.read(splitTunnelModeProvider.notifier).set(v);
                }
              },
            ),
          ),
          if (mode != SplitTunnelMode.all) ...[
            Divider(height: 1, thickness: 0.5, color: dividerColor),
            YLSettingsRow(
              title: s.splitTunnelApps,
              description: s.splitTunnelEffectHint,
              trailing: TextButton.icon(
                icon: const Icon(Icons.apps, size: 14),
                label: Text(s.splitTunnelManage),
                onPressed: () async {
                  if (_apps == null) await _loadApps();
                  if (!context.mounted) return;
                  _showAppPicker(context, selectedPkgs);
                },
              ),
            ),
            if (selectedPkgs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: selectedPkgs
                      .map((pkg) => Chip(
                            label:
                                Text(pkg, style: const TextStyle(fontSize: 11)),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () => ref
                                .read(splitTunnelAppsProvider.notifier)
                                .remove(pkg),
                          ))
                      .toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _showAppPicker(BuildContext context, List<String> initialSelected) {
    final s = S.of(context);
    final localSelected = Set<String>.from(initialSelected);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final apps = _apps ?? [];
          final filtered = _search.isEmpty
              ? List<Map<String, String>>.from(apps)
              : apps
                  .where((a) =>
                      (a['appName'] ?? '').toLowerCase().contains(_search) ||
                      (a['packageName'] ?? '').toLowerCase().contains(_search))
                  .toList();
          filtered.sort((a, b) {
            final aSelected = localSelected.contains(a['packageName']);
            final bSelected = localSelected.contains(b['packageName']);
            if (aSelected != bSelected) return aSelected ? -1 : 1;
            return (a['appName'] ?? '').compareTo(b['appName'] ?? '');
          });

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            expand: false,
            builder: (_, sc) => Column(
              children: [
                const SizedBox(height: 8),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: s.splitTunnelSearchHint,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setModal(() => _search = v.toLowerCase()),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.apps_outlined,
                                        size: 40, color: YLColors.zinc400),
                                    const SizedBox(height: 12),
                                    Text(
                                      _loadError ??
                                          (_search.isNotEmpty
                                              ? (S.of(context).isEn
                                                  ? 'No matching apps'
                                                  : '未找到匹配应用')
                                              : (S.of(context).isEn
                                                  ? 'No apps found'
                                                  : '未获取到应用')),
                                      textAlign: TextAlign.center,
                                      style: YLText.body
                                          .copyWith(color: YLColors.zinc500),
                                    ),
                                    if (_loadError != null) ...[
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: () {
                                          _loadApps()
                                              .then((_) => setModal(() {}));
                                        },
                                        child: Text(S.of(context).isEn
                                            ? 'Retry'
                                            : '重试'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: sc,
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final app = filtered[i];
                                final pkg = app['packageName'] ?? '';
                                final isSelected = localSelected.contains(pkg);
                                return CheckboxListTile(
                                  dense: true,
                                  title: Text(app['appName'] ?? pkg),
                                  subtitle: Text(pkg,
                                      style: const TextStyle(fontSize: 11)),
                                  value: isSelected,
                                  onChanged: (_) {
                                    setModal(() {
                                      if (localSelected.contains(pkg)) {
                                        localSelected.remove(pkg);
                                      } else {
                                        localSelected.add(pkg);
                                      }
                                    });
                                    ref
                                        .read(splitTunnelAppsProvider.notifier)
                                        .toggle(pkg);
                                  },
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Accent Color Picker ─────────────────────────────────────────────────────

class _AccentColorRow extends StatelessWidget {
  final String currentHex;
  final ValueChanged<String> onChanged;
  final bool isEn;

  const _AccentColorRow({
    required this.currentHex,
    required this.onChanged,
    required this.isEn,
  });

  static const _presets = <String, String>{
    '3B82F6': 'Blue',
    '10B981': 'Green',
    '8B5CF6': 'Purple',
    'F97316': 'Orange',
    'EF4444': 'Red',
    'EC4899': 'Pink',
    '14B8A6': 'Teal',
    '6366F1': 'Indigo',
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isEn ? 'Accent color' : '强调色',
              style: YLText.body.copyWith(
                color: isDark ? YLColors.zinc200 : YLColors.zinc700,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: _presets.entries.map((e) {
              final color = Color(int.parse('FF${e.key}', radix: 16));
              final isSelected = currentHex.toUpperCase() == e.key;
              return GestureDetector(
                onTap: () => onChanged(e.key),
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: isSelected
                        ? Border.all(
                            color: isDark ? Colors.white : Colors.black,
                            width: 2,
                          )
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
