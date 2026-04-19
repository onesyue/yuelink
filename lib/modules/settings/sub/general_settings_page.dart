import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import '../../../core/kernel/config_template.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../core/service/service_manager.dart';
import '../../../core/service/service_models.dart';
import '../../../core/service/service_mode_provider.dart';
import '../../../core/storage/settings_service.dart';
import '../../../i18n/app_strings.dart';
import '../../../i18n/strings_g.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/providers/core_provider.dart';
import '../../../main.dart' show tileShowNodeInfoProvider;
import '../../profiles/providers/profiles_providers.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/event_log.dart';
import '../../../shared/telemetry.dart';
import '../../../theme.dart';
import '../providers/settings_providers.dart';
import '../widgets/primitives.dart';
import 'widgets/appearance_section.dart';
import 'widgets/close_behavior_row.dart';
import 'widgets/hotkey_row.dart';
import 'widgets/privacy_section.dart';
import 'widgets/split_tunnel_section.dart';
import 'widgets/updates_section.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final startup = await SettingsService.getLaunchAtStartup();
    if (mounted) {
      setState(() {
        _launchAtStartup = startup;
      });
    }
  }

  String _quicPolicyDescription(Translations strings, String policy) {
    switch (policy) {
      case SettingsService.quicPolicyOff:
        return strings.quicPolicyCompatibilityDesc;
      case SettingsService.quicPolicyAll:
        return strings.quicPolicyForceFallbackDesc;
      case SettingsService.quicPolicyGooglevideo:
      default:
        return strings.quicPolicyStandardDesc;
    }
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
      // Installing the privileged service is an explicit "I want TUN" signal
      // — bring the core up right now so the user doesn't have to bounce
      // back to the dashboard and click connect manually. Covers both
      // paths: running core (restart to pick up service mode) AND stopped
      // core (fresh start). The only skip is when the user has explicitly
      // stopped the VPN in this session, in which case we respect that
      // intent and leave them stopped.
      await _applyServiceModeImmediately();
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

  /// After the service install / update succeeds, put the core into the
  /// right state without forcing the user to go back to the dashboard:
  ///   - running  → restart (so service mode takes effect)
  ///   - stopped  → start (installing the service is an implicit
  ///                       "I want TUN" intent)
  /// Only respected the user's explicit stop (userStoppedProvider) —
  /// if they manually disconnected in this session we leave them off.
  ///
  /// Errors used to be fully swallowed — users saw "install succeeded" but
  /// the core was silently stopped, and they had to click connect on the
  /// dashboard to find out. Windows TUN cold-start in particular (driver
  /// init + AV scan) can push first-connect past the 5 s waitApi window,
  /// even though a retry succeeds immediately. Now we:
  ///   1. grace-pause 1.5 s to let the freshly-installed helper's child
  ///      mihomo binary fully bind its API listener;
  ///   2. retry once on failure (same rationale as heartbeat watchdog);
  ///   3. surface the last error via AppNotifier so the user isn't left
  ///      confused after "刷新一下" is all that fixes it.
  Future<void> _applyServiceModeImmediately() async {
    try {
      final activeId = ref.read(activeProfileIdProvider);
      if (activeId == null) return;
      final initialStatus = ref.read(coreStatusProvider);
      final userStopped = ref.read(userStoppedProvider);
      if (initialStatus == CoreStatus.stopped && userStopped) return;

      final config = await ProfileService.loadConfig(activeId);
      if (config == null) return;

      // Grace: helper just returned from elevation — mihomo child may
      // still be binding 127.0.0.1:9090.
      await Future.delayed(const Duration(milliseconds: 1500));

      final actions = ref.read(coreActionsProvider);
      Future<bool> attempt() {
        final status = ref.read(coreStatusProvider);
        return status == CoreStatus.running
            ? actions.restart(config)
            : actions.start(config);
      }

      bool ok = await attempt();
      if (!ok) {
        EventLog.write(
            '[Service] post-install start failed once, retrying after 2 s');
        await Future.delayed(const Duration(seconds: 2));
        ok = await attempt();
      }
      if (!ok && mounted) {
        AppNotifier.warning(
          '服务已安装，但内核启动失败。请在主页点击"开始连接"重试。',
        );
        EventLog.write('[Service] post-install start failed after retry');
      }
    } catch (e) {
      EventLog.write('[Service] post-install start threw: $e');
      if (mounted) {
        AppNotifier.warning(
          '服务已安装，但内核启动失败：${e.toString().split('\n').first}',
        );
      }
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
      // Same rationale as install — the running core still holds handles
      // from the old helper binary. Restart so the new helper is picked up.
      await _applyServiceModeImmediately();
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
    final strings = Translations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final subSyncInterval = ref.watch(subSyncIntervalProvider);
    final autoConnect = ref.watch(autoConnectProvider);
    final connectionMode = ref.watch(connectionModeProvider);
    final quicPolicy = ref.watch(quicPolicyProvider);
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
              const AppearanceSection(),

              // === 连接 / Connection ===
              GsGeneralSectionTitle(isEn ? 'Connection' : '连接'),
              SettingsCard(
                child: Column(
                  children: [
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
                            if (mode == routingMode) return;
                            ref.read(routingModeProvider.notifier).state = mode;
                            await SettingsService.setRoutingMode(mode);
                            Telemetry.event(
                              TelemetryEvents.routingModeChange,
                              props: {'mode': mode},
                            );
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
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLSettingsRow(
                      title: strings.quicPolicyLabel,
                      description: _quicPolicyDescription(strings, quicPolicy),
                      trailing: DropdownButton<String>(
                        value: quicPolicy,
                        underline: const SizedBox.shrink(),
                        style: YLText.body.copyWith(
                          color: isDark ? YLColors.zinc200 : YLColors.zinc700,
                        ),
                        dropdownColor: isDark ? YLColors.zinc800 : Colors.white,
                        items: [
                          DropdownMenuItem(
                            value: SettingsService.quicPolicyGooglevideo,
                            child: Text(strings.quicPolicyStandard),
                          ),
                          DropdownMenuItem(
                            value: SettingsService.quicPolicyOff,
                            child: Text(strings.quicPolicyCompatibility),
                          ),
                          DropdownMenuItem(
                            value: SettingsService.quicPolicyAll,
                            child: Text(strings.quicPolicyForceFallback),
                          ),
                        ],
                        onChanged: (v) async {
                          if (v == null || v == quicPolicy) return;
                          ref.read(quicPolicyProvider.notifier).state = v;
                          ConfigTemplate.setDefaultQuicRejectPolicy(v);
                          await SettingsService.setQuicPolicy(v);
                        },
                      ),
                    ),
                    if (Platform.isAndroid) ...[
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLSettingsRow(
                        title: isEn
                            ? 'Show node in Quick Settings tile'
                            : '磁贴显示当前节点',
                        description: isEn
                            ? 'Shows the exit region in the tile — visible to anyone who pulls down the shade.'
                            : '磁贴副标题显示当前节点出口地区，拉下通知栏的人都会看到',
                        trailing: CupertinoSwitch(
                          value: ref.watch(tileShowNodeInfoProvider),
                          activeTrackColor: YLColors.connected,
                          onChanged: (v) async {
                            ref.read(tileShowNodeInfoProvider.notifier).state =
                                v;
                            await SettingsService.setTileShowNodeInfo(v);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // === 高级 / Advanced (desktop only) ===
              if (isDesktop) ...[
                GsGeneralSectionTitle(isEn ? 'Advanced' : '高级'),
                SettingsCard(
                  child: Column(
                    children: [
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
                            Telemetry.event(
                              TelemetryEvents.connectionModeChange,
                              props: {'mode': v},
                            );

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
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // === 启动与快捷键 / Startup & Hotkey (desktop only) ===
              if (isDesktop) ...[
                GsGeneralSectionTitle(isEn ? 'Startup & Hotkey' : '启动与快捷键'),
                SettingsCard(
                  child: Column(
                    children: [
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
                      if (!Platform.isLinux) ...[
                        Divider(height: 1, thickness: 0.5, color: dividerColor),
                        const CloseBehaviorRow(),
                      ],
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      const HotkeyRow(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // === 订阅 / Subscription ===
              GsGeneralSectionTitle(isEn ? 'Subscription' : '订阅'),
              SettingsCard(
                child: Column(
                  children: [
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
                          DropdownMenuItem(
                              value: 0, child: Text(isEn ? 'Manual' : '手动')),
                          DropdownMenuItem(
                              value: 1,
                              child: Text(isEn ? 'Every hour' : '每小时')),
                          DropdownMenuItem(
                              value: 6,
                              child: Text(isEn ? 'Every 6 hours' : '每6小时')),
                          DropdownMenuItem(
                              value: 12,
                              child: Text(isEn ? 'Every 12 hours' : '每12小时')),
                          DropdownMenuItem(
                              value: 24,
                              child: Text(isEn ? 'Every day' : '每天')),
                          DropdownMenuItem(
                              value: 48,
                              child: Text(isEn ? 'Every 2 days' : '每2天')),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          ref.read(subSyncIntervalProvider.notifier).state = v;
                          await SettingsService.setSubSyncInterval(v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              const UpdatesSection(),

              // === 分流 / Split Tunnel (Android only) ===
              if (Platform.isAndroid) ...[
                GsGeneralSectionTitle(isEn ? 'Split Tunnel' : '分流'),
                const SplitTunnelSection(),
                const SizedBox(height: 16),
              ],

              const PrivacySection(),
            ],
          ),
        ),
      ),
    );
  }
}


