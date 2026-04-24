import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../core/storage/settings_service.dart';
import '../../../i18n/app_strings.dart';
import '../../../i18n/strings_g.dart';
import '../../../core/providers/core_provider.dart';
import '../../../main.dart' show tileShowNodeInfoProvider;
import '../../../shared/app_notifier.dart';
import '../../../shared/telemetry.dart';
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
    final status = ref.watch(coreStatusProvider);
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
                              value: 'rule',
                              label: Text(s.routeModeRule),
                            ),
                            ButtonSegment(
                              value: 'global',
                              label: Text(s.routeModeGlobal),
                            ),
                            ButtonSegment(
                              value: 'direct',
                              label: Text(s.routeModeDirect),
                            ),
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
                                await CoreManager.instance.api.setRoutingMode(
                                  mode,
                                );
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
                          dropdownColor: isDark
                              ? YLColors.zinc800
                              : Colors.white,
                          items: [
                            DropdownMenuItem(
                              value: 'tun',
                              child: Text(s.modeTun),
                            ),
                            DropdownMenuItem(
                              value: 'systemProxy',
                              child: Text(s.modeSystemProxy),
                            ),
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
                        const ServiceModeRow(),
                        Divider(height: 1, thickness: 0.5, color: dividerColor),
                        YLInfoRow(
                          label: s.tunStackLabel,
                          trailing: DropdownButton<String>(
                            value: desktopTunStack,
                            underline: const SizedBox.shrink(),
                            style: YLText.body.copyWith(
                              color: isDark
                                  ? YLColors.zinc200
                                  : YLColors.zinc700,
                            ),
                            dropdownColor: isDark
                                ? YLColors.zinc800
                                : Colors.white,
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
                              color: isDark
                                  ? YLColors.zinc400
                                  : YLColors.zinc500,
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
                                    .state =
                                v;
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
                            value: 0,
                            child: Text(isEn ? 'Manual' : '手动'),
                          ),
                          DropdownMenuItem(
                            value: 1,
                            child: Text(isEn ? 'Every hour' : '每小时'),
                          ),
                          DropdownMenuItem(
                            value: 6,
                            child: Text(isEn ? 'Every 6 hours' : '每6小时'),
                          ),
                          DropdownMenuItem(
                            value: 12,
                            child: Text(isEn ? 'Every 12 hours' : '每12小时'),
                          ),
                          DropdownMenuItem(
                            value: 24,
                            child: Text(isEn ? 'Every day' : '每天'),
                          ),
                          DropdownMenuItem(
                            value: 48,
                            child: Text(isEn ? 'Every 2 days' : '每2天'),
                          ),
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
