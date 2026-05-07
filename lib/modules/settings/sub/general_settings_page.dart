import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../core/storage/settings_service.dart';
import '../../../i18n/app_strings.dart';
import '../../../i18n/strings_g.dart';
import '../../../core/providers/core_provider.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/diagnostic_report.dart';
import '../../../shared/log_export_service.dart';
import '../../../shared/telemetry.dart';
import '../../../shared/windows_diagnostic_script.dart';
import '../../../shared/widgets/yl_scaffold.dart';
import '../../../theme.dart';
import '../providers/settings_providers.dart';
import '../widgets/primitives.dart';
import 'widgets/appearance_section.dart';
import 'widgets/close_behavior_row.dart';
import 'widgets/hotkey_row.dart';
import 'widgets/privacy_section.dart';
import 'widgets/service_mode_row.dart';
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

  String _quicPolicyTitle(Translations strings, String policy) {
    switch (policy) {
      case SettingsService.quicPolicyOff:
        return strings.quicPolicyCompatibility;
      case SettingsService.quicPolicyAll:
        return strings.quicPolicyForceFallback;
      case SettingsService.quicPolicyGooglevideo:
      default:
        return strings.quicPolicyStandard;
    }
  }

  String _connectionModeTitle(S s, String mode) {
    return mode == 'tun' ? s.modeTun : s.modeSystemProxy;
  }

  String _tunStackTitle(S s, String stack) {
    switch (stack) {
      case 'system':
        return s.tunStackSystem;
      case 'gvisor':
        return s.tunStackGvisor;
      case 'mixed':
      default:
        return s.tunStackMixed;
    }
  }

  String _subSyncIntervalTitle({required bool isEn, required int hours}) {
    switch (hours) {
      case 0:
        return isEn ? 'Manual' : '手动';
      case 1:
        return isEn ? 'Every hour' : '每小时';
      case 6:
        return isEn ? 'Every 6 hours' : '每 6 小时';
      case 12:
        return isEn ? 'Every 12 hours' : '每 12 小时';
      case 24:
        return isEn ? 'Every day' : '每天';
      case 48:
        return isEn ? 'Every 2 days' : '每 2 天';
      default:
        return isEn ? 'Every $hours hours' : '每 $hours 小时';
    }
  }

  Future<void> _pickQuicPolicy(
    BuildContext context,
    String currentPolicy,
  ) async {
    final strings = Translations.of(context);
    final picked = await showYLSettingsOptionPicker<String>(
      context: context,
      title: strings.quicPolicyLabel,
      selectedValue: currentPolicy,
      options: [
        YLSettingsOption(
          value: SettingsService.quicPolicyGooglevideo,
          title: strings.quicPolicyStandard,
          subtitle: strings.quicPolicyStandardDesc,
        ),
        YLSettingsOption(
          value: SettingsService.quicPolicyOff,
          title: strings.quicPolicyCompatibility,
          subtitle: strings.quicPolicyCompatibilityDesc,
        ),
        YLSettingsOption(
          value: SettingsService.quicPolicyAll,
          title: strings.quicPolicyForceFallback,
          subtitle: strings.quicPolicyForceFallbackDesc,
        ),
      ],
    );
    if (picked == null || picked == currentPolicy) return;
    ref.read(quicPolicyProvider.notifier).set(picked);
    await SettingsService.setQuicPolicy(picked);
  }

  Future<void> _pickConnectionMode(
    BuildContext context,
    String currentMode,
  ) async {
    final s = S.of(context);
    final picked = await showYLSettingsOptionPicker<String>(
      context: context,
      title: s.connectionMode,
      selectedValue: currentMode,
      options: [
        YLSettingsOption(value: 'tun', title: s.modeTun),
        YLSettingsOption(value: 'systemProxy', title: s.modeSystemProxy),
      ],
    );
    if (picked == null || picked == currentMode) return;
    await _applyConnectionMode(picked, previous: currentMode);
  }

  Future<void> _applyConnectionMode(
    String mode, {
    required String previous,
  }) async {
    ref.read(connectionModeProvider.notifier).set(mode);
    await SettingsService.setConnectionMode(mode);
    Telemetry.event(
      TelemetryEvents.connectionModeChange,
      props: {'mode': mode},
    );

    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.running) {
      final actions = ref.read(coreActionsProvider);
      final ok = await actions.hotSwitchConnectionMode(
        mode,
        fallbackMode: previous,
      );
      if (!ok) {
        ref.read(connectionModeProvider.notifier).set(previous);
        await SettingsService.setConnectionMode(previous);
      }
    }
  }

  Future<void> _pickTunStack(BuildContext context, String currentStack) async {
    final s = S.of(context);
    final picked = await showYLSettingsOptionPicker<String>(
      context: context,
      title: s.tunStackLabel,
      selectedValue: currentStack,
      options: [
        YLSettingsOption(value: 'mixed', title: s.tunStackMixed),
        YLSettingsOption(value: 'system', title: s.tunStackSystem),
        YLSettingsOption(value: 'gvisor', title: s.tunStackGvisor),
      ],
    );
    if (picked == null || picked == currentStack) return;
    ref.read(desktopTunStackProvider.notifier).set(picked);
    await SettingsService.setDesktopTunStack(picked);
  }

  Future<void> _pickSubSyncInterval(
    BuildContext context,
    int currentHours,
  ) async {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final picked = await showYLSettingsOptionPicker<int>(
      context: context,
      title: isEn ? 'Subscription update' : '订阅更新频率',
      selectedValue: currentHours,
      options: [
        for (final hours in const [0, 1, 6, 12, 24, 48])
          YLSettingsOption(
            value: hours,
            title: _subSyncIntervalTitle(isEn: isEn, hours: hours),
          ),
      ],
    );
    if (picked == null || picked == currentHours) return;
    ref.read(subSyncIntervalProvider.notifier).set(picked);
    await SettingsService.setSubSyncInterval(picked);
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
                Text(
                  s.tunBypassAddrHint,
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
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
                Text(
                  s.tunBypassProcHint,
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
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
    final winLanCompat = ref.watch(windowsLanCompatibilityModeProvider);
    final lightWeightMin = ref.watch(autoLightWeightAfterMinutesProvider);
    final status = ref.watch(coreStatusProvider);
    final routingMode = ref.watch(routingModeProvider);
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return YLLargeTitleScaffold(
      title: s.preferencesLabel,
      maxContentWidth: kYLSecondaryContentWidth,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, YLSpacing.xxl),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
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
                          ref.read(autoConnectProvider.notifier).set(v);
                          await SettingsService.setAutoConnect(v);
                        },
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.routingModeSetting,
                      trailing: YLAdaptiveSegmentedControl<String>(
                        semanticLabel: s.routingModeSetting,
                        selectedValue: routingMode,
                        segments: [
                          YLAdaptiveSegment(
                            value: 'rule',
                            label: s.routeModeRule,
                          ),
                          YLAdaptiveSegment(
                            value: 'global',
                            label: s.routeModeGlobal,
                          ),
                          YLAdaptiveSegment(
                            value: 'direct',
                            label: s.routeModeDirect,
                          ),
                        ],
                        onChanged: (mode) async {
                          if (mode == routingMode) return;
                          ref.read(routingModeProvider.notifier).set(mode);
                          await SettingsService.setRoutingMode(mode);
                          Telemetry.event(
                            TelemetryEvents.routingModeChange,
                            props: {'mode': mode},
                          );
                          if (status == CoreStatus.running) {
                            try {
                              await CoreManager.instance.api.setRoutingMode(
                                mode,
                              );
                            } catch (_) {}
                          }
                        },
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLSettingsRow(
                      title: strings.quicPolicyLabel,
                      description: _quicPolicyDescription(strings, quicPolicy),
                      trailing: YLSettingsValueButton(
                        label: _quicPolicyTitle(strings, quicPolicy),
                      ),
                      onTap: () => _pickQuicPolicy(context, quicPolicy),
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
                            ref.read(tileShowNodeInfoProvider.notifier).set(v);
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
                        trailing: YLSettingsValueButton(
                          label: _connectionModeTitle(s, connectionMode),
                        ),
                        onTap: () =>
                            _pickConnectionMode(context, connectionMode),
                      ),
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLSettingsRow(
                        title: isEn
                            ? 'Export diagnostic report'
                            : '导出诊断报告',
                        description: isEn
                            ? 'Read-only markdown bundle: connection mode, '
                                  'ports, startup steps, system proxy, '
                                  'Service Mode, Private DNS, bypass list. '
                                  'Safe to share — no tokens / nodes / IPs.'
                            : '只读 markdown 报告:连接模式 / 端口 / 启动步骤 / '
                                  '系统代理 / Service Mode / Private DNS / '
                                  'bypass 列表。可放心上报 —— 不含 token/节点/IP。',
                        trailing: YLSettingsValueButton(
                          label: isEn ? 'Export' : '导出',
                        ),
                        onTap: () async {
                          final report = await DiagnosticReport.build(ref);
                          final ts = DateTime.now()
                              .toIso8601String()
                              .replaceAll(':', '-')
                              .split('.')
                              .first;
                          final result = await LogExportService.saveText(
                            fileName: 'yuelink-diagnostic-$ts.md',
                            content: report,
                          );
                          if (!context.mounted) return;
                          if (result.saved) {
                            AppNotifier.success(
                              isEn ? 'Saved' : '已导出',
                            );
                          } else if (!result.cancelled) {
                            AppNotifier.error(
                              result.error ??
                                  (isEn ? 'Export failed' : '导出失败'),
                            );
                          }
                        },
                      ),
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      const ServiceModeRow(),
                      if (connectionMode == 'tun') ...[
                        Divider(height: 1, thickness: 0.5, color: dividerColor),
                        YLInfoRow(
                          label: s.tunStackLabel,
                          trailing: YLSettingsValueButton(
                            label: _tunStackTitle(s, desktopTunStack),
                          ),
                          onTap: () => _pickTunStack(context, desktopTunStack),
                        ),
                        Divider(height: 1, thickness: 0.5, color: dividerColor),
                        YLSettingsRow(
                          title: s.tunBypassLabel,
                          description: s.tunBypassSub,
                          trailing: YLSettingsValueButton(
                            label: isEn ? 'Edit' : '编辑',
                          ),
                          onTap: () => _showTunBypassEditor(context),
                        ),
                        if (Platform.isWindows) ...[
                          Divider(height: 1, thickness: 0.5, color: dividerColor),
                          YLSettingsRow(
                            title: isEn
                                ? 'Copy Windows diagnostic script'
                                : '复制 Windows 诊断脚本',
                            description: isEn
                                ? 'Read-only PowerShell. Paste into Win + R '
                                      '→ powershell to generate a markdown '
                                      'report (Wintun / NIC / routes / DNS / '
                                      'firewall / proxy / service / API).'
                                : '只读 PowerShell 脚本。粘贴到 Win+R → '
                                      'powershell 执行,生成 markdown 报告 '
                                      '(Wintun / 网卡 / 路由 / DNS / 防火墙 / '
                                      '系统代理 / Service / API)。',
                            trailing: YLSettingsValueButton(
                              label: isEn ? 'Copy' : '复制',
                            ),
                            onTap: () async {
                              // Live runtime ports if core is up; defaults
                              // otherwise. Both ports flow into the script's
                              // `127.0.0.1:<port>/configs` reachability check
                              // — pass apiPort too because port-conflict
                              // remapping at startup may have moved it off
                              // the 9090 default.
                              final script = WindowsDiagnosticScript.generate(
                                mixedPort: CoreManager.instance.mixedPort,
                                apiPort: CoreManager.instance.apiPort,
                              );
                              await Clipboard.setData(
                                ClipboardData(text: script),
                              );
                              if (!context.mounted) return;
                              AppNotifier.success(
                                isEn
                                    ? 'Diagnostic script copied to clipboard'
                                    : '诊断脚本已复制到剪贴板',
                              );
                            },
                          ),
                          Divider(height: 1, thickness: 0.5, color: dividerColor),
                          YLSettingsRow(
                            title: isEn
                                ? 'LAN compatibility mode'
                                : '局域网兼容模式',
                            description: isEn
                                ? 'Disables strict-route on Windows TUN. '
                                      'Enable to reach SMB shares, network '
                                      'printers, remote-desktop to intranet, '
                                      'or NAS web UIs while connected. '
                                      'Slightly relaxes the leak-tightness '
                                      'guarantee. Restart to apply.'
                                : '关闭 Windows TUN 的 strict-route。开启后可访问 '
                                      '内网共享 / 网络打印机 / 远程桌面 / NAS '
                                      '管理页;会略微放松防泄漏严格度,需重连生效。',
                            trailing: CupertinoSwitch(
                              value: winLanCompat,
                              activeTrackColor: YLColors.connected,
                              onChanged: (v) async {
                                ref
                                    .read(windowsLanCompatibilityModeProvider
                                        .notifier)
                                    .set(v);
                                await SettingsService
                                    .setWindowsLanCompatibilityMode(v);
                              },
                            ),
                          ),
                        ],
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
                                .set(v);
                            await SettingsService.setSystemProxyOnConnect(v);
                          },
                        ),
                      ),
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLSettingsRow(
                        title: isEn
                            ? 'Tray idle flag (experimental)'
                            : '托盘空闲标志（实验性）',
                        description: isEn
                            ? 'Sets a Riverpod flag (lightWeightModeProvider) '
                                  '10 minutes after the window is hidden into '
                                  'tray. Currently no widget consumes the '
                                  'flag — it is wiring only, ready for future '
                                  'opt-in resource releases. Tray + mihomo '
                                  'always keep running regardless.'
                            : '窗口隐藏托盘 10 分钟后将 Riverpod '
                                  'lightWeightModeProvider 设为 true。'
                                  '当前**无**消费者实际释放资源 —— 仅作为'
                                  'opt-in 接线点供未来按页接入。无论开关与否,'
                                  '托盘 + mihomo 始终正常运行。',
                        trailing: CupertinoSwitch(
                          value: lightWeightMin > 0,
                          activeTrackColor: YLColors.connected,
                          onChanged: (v) async {
                            final next = v ? 10 : 0;
                            ref
                                .read(autoLightWeightAfterMinutesProvider
                                    .notifier)
                                .set(next);
                            await SettingsService
                                .setAutoLightWeightAfterMinutes(next);
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
                      trailing: YLSettingsValueButton(
                        label: _subSyncIntervalTitle(
                          isEn: isEn,
                          hours: subSyncInterval,
                        ),
                      ),
                      onTap: () =>
                          _pickSubSyncInterval(context, subSyncInterval),
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
            ]),
          ),
        ),
      ],
    );
  }
}
