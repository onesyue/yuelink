import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/kernel/core_manager.dart';
import '../../core/platform/vpn_service.dart';
import '../../core/providers/core_provider.dart';
import '../../core/tun/desktop_tun_diagnostics.dart';
import '../../core/tun/desktop_tun_state.dart';
import '../../core/tun/desktop_tun_telemetry.dart';
import '../../i18n/app_strings.dart';
import '../../shared/app_notifier.dart';
import '../../shared/diagnostic_text.dart';
import '../../shared/log_export_service.dart';
import '../../shared/telemetry.dart';
import '../../shared/widgets/setting_icon.dart';
import '../../shared/widgets/yl_list.dart';
import '../../shared/widgets/yl_scaffold.dart';
import '../../theme.dart';
import '../yue_auth/providers/yue_auth_providers.dart';
import 'connection_repair/connection_diagnostics_service.dart';
import 'connection_repair/connection_repair_actions.dart';
import 'connection_repair/widgets/desktop_tun_layered_status.dart';
import 'connection_repair/widgets/ios_tun_layered_status.dart';
import 'connection_repair/widgets/network_diagnostics.dart';
import 'connection_repair/widgets/status_tile.dart';
import 'startup_report_page.dart';
import 'sub/widgets/service_mode_row.dart';

/// Connection repair tools: rebuild VPN, clear config, re-sync subscription,
/// view diagnostics.
class ConnectionRepairPage extends ConsumerStatefulWidget {
  const ConnectionRepairPage({super.key});

  @override
  ConsumerState<ConnectionRepairPage> createState() =>
      _ConnectionRepairPageState();
}

class _ConnectionRepairPageState extends ConsumerState<ConnectionRepairPage> {
  bool _busy = false;

  Future<void> _exportDiagnosticLogs({String entry = 'reports'}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final appDir = await getApplicationSupportDirectory();
      String? extraSection;
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        extraSection = await _collectDesktopTunDiagnosticsText(ref);
      }
      final bundle = await ConnectionDiagnosticsService.buildLogBundle(
        appDir: appDir,
        extraSection: extraSection,
      );
      if (bundle.filesFound == 0) {
        if (mounted) AppNotifier.warning(S.current.exportLogsEmpty);
        return;
      }
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      final fileName = 'yuelink-diagnostics-$stamp.txt';
      final result = await LogExportService.saveText(
        fileName: fileName,
        content: bundle.content,
        dialogTitle: S.current.exportLogs,
      );
      if (!mounted) return;
      if (result.cancelled) return;
      if (result.saved) {
        Telemetry.event(
          TelemetryEvents.diagnosticExport,
          props: {'entry': entry},
        );
        AppNotifier.success(
          '${S.current.exportLogsSuccess}: ${result.path ?? fileName}',
        );
      } else {
        AppNotifier.error(
          '${S.current.exportLogsFailed}: ${result.error ?? ''}',
        );
      }
    } catch (e) {
      if (mounted) AppNotifier.error('${S.current.exportLogsFailed}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restartCore() async {
    if (_busy) return;
    setState(() => _busy = true);
    Telemetry.event(
      TelemetryEvents.connectionRepairAttempt,
      props: {'action': 'restart_core'},
    );
    try {
      final actions = ref.read(connectionRepairActionsProvider);
      final res = await actions.loadActiveConfig();
      if (res is ActiveConfigMissing) {
        Telemetry.event(
          TelemetryEvents.connectionRepairResult,
          props: {
            'action': 'restart_core',
            'ok': false,
            'reason': res.reason.name,
          },
        );
        if (mounted) AppNotifier.error(_missingConfigMessage(res.reason));
        return;
      }
      final yaml = (res as ActiveConfigLoaded).yaml;
      final ok = await ref.read(coreActionsProvider).restart(yaml);
      Telemetry.event(
        TelemetryEvents.connectionRepairResult,
        props: {'action': 'restart_core', 'ok': ok},
      );
      if (!mounted) return;
      final label = S.current.repairRestartCore;
      if (ok) {
        AppNotifier.success('$label ${S.current.repairActionDone}');
      } else {
        AppNotifier.error('$label ${S.current.repairActionFailed}');
      }
    } catch (e) {
      Telemetry.event(
        TelemetryEvents.connectionRepairResult,
        props: {
          'action': 'restart_core',
          'ok': false,
          'error_type': e.runtimeType.toString(),
        },
      );
      if (mounted) {
        AppNotifier.error(
          '${S.current.repairRestartCore} ${S.current.repairActionFailed}: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _oneClickRepairAndReconnect() async {
    // Do NOT pre-load config here — `syncSubscription` inside the action
    // can rescue an initially-empty config, and a pre-flight check would
    // block that recovery path. The action surfaces a typed Result so we
    // still get the specific MissingConfig reason on genuine failure.
    final result = await ref
        .read(connectionRepairActionsProvider)
        .oneClickRepairAndReconnect();
    switch (result) {
      case RepairReconnectSuccess():
        return true;
      case RepairReconnectFailed():
        return false;
      case RepairReconnectMissingConfig(:final reason):
        if (mounted) AppNotifier.error(_missingConfigMessage(reason));
        return false;
    }
  }

  String _missingConfigMessage(MissingConfigReason reason) {
    final isEn = S.current.isEn;
    switch (reason) {
      case MissingConfigReason.noActiveProfile:
        return isEn ? 'No active subscription selected' : '未选择活动订阅';
      case MissingConfigReason.configEmpty:
        return isEn
            ? 'Active subscription config is empty. Re-sync first.'
            : '活动订阅配置为空，请先重新同步订阅';
    }
  }

  Future<void> _run(
    String label,
    Future<bool> Function() action, {
    required String actionId,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    Telemetry.event(
      TelemetryEvents.connectionRepairAttempt,
      props: {'action': actionId},
    );
    try {
      // Stop through the lifecycle manager, not CoreManager directly. The
      // lifecycle path is the only one that clears system proxy, restores
      // macOS TUN DNS, records desktop_tun_* telemetry, and drives the UI
      // status back through `stopping -> stopped`.
      if (CoreManager.instance.isRunning) {
        await ref.read(coreActionsProvider).stop();
      }
      final ok = await action();
      Telemetry.event(
        TelemetryEvents.connectionRepairResult,
        props: {'action': actionId, 'ok': ok},
      );
      if (mounted) {
        if (ok) {
          AppNotifier.success('$label ${S.current.repairActionDone}');
        } else {
          AppNotifier.error('$label ${S.current.repairActionFailed}');
        }
      }
    } catch (e) {
      Telemetry.event(
        TelemetryEvents.connectionRepairResult,
        props: {
          'action': actionId,
          'ok': false,
          'error_type': e.runtimeType.toString(),
        },
      );
      if (mounted) {
        AppNotifier.error('$label ${S.current.repairActionFailed}: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return YLLargeTitleScaffold(
      title: s.repairTitle,
      slivers: [
        // ── Status ─────────────────────────────────────────────────
        const SliverToBoxAdapter(
          child: YLSection(header: 'STATUS', children: [StatusTile()]),
        ),

        if (isDesktop)
          SliverToBoxAdapter(
            child: YLSection(
              header: isEn ? 'Desktop TUN' : '桌面 TUN',
              children: const [ServiceModeRow(), DesktopTunLayeredStatus()],
            ),
          ),

        // ── iOS layered diagnostic ────────────────────────────────
        // iOS runs TUN through NEPacketTunnelProvider; driver / route /
        // interface / admin layers don't apply (sandbox + system-managed
        // VPN). Show only the layers iOS users can actually act on:
        // mihomo controller reachability, DNS hijack, exit-site probe.
        if (Platform.isIOS)
          SliverToBoxAdapter(
            child: YLSection(
              header: isEn ? 'iOS TUN' : 'iOS TUN',
              children: const [IosTunLayeredStatus()],
            ),
          ),

        // ── One-click full repair (主 CTA) ─────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            YLSpacing.lg,
            YLSpacing.lg,
            YLSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        s.repairOneClick,
                        _oneClickRepairAndReconnect,
                        actionId: 'one_click',
                      ),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: Text(_busy ? s.repairRunning : s.repairOneClick),
                style: FilledButton.styleFrom(
                  backgroundColor: isDark ? YLColors.zinc700 : YLColors.zinc800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(YLRadius.lg),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            YLSpacing.lg,
            YLSpacing.sm,
            YLSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _exportDiagnosticLogs(entry: 'top_cta'),
                icon: const Icon(Icons.file_download_rounded, size: 18),
                label: Text(isEn ? 'Export diagnostic bundle' : '导出诊断包'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(YLRadius.lg),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            YLSpacing.lg,
            YLSpacing.sm,
            YLSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Text(
              isEn
                  ? 'Stop connection → reset tunnel → clear cache, then reconnect'
                  : '停止连接 → 删除旧隧道 → 清除缓存，修复后重新连接',
              style: YLText.caption.copyWith(
                color: isDark ? YLColors.zinc500 : YLColors.zinc500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),

        // ── Repair actions（单项修复）─────────────────────────────
        SliverToBoxAdapter(
          child: YLSection(
            header: s.repairTools,
            children: [
              YLListTile(
                leading: const YLSettingIcon(
                  icon: Icons.restart_alt_rounded,
                  color: Color(0xFF3B82F6),
                ),
                title: s.repairRestartCore,
                subtitle: s.repairRestartCoreHint,
                trailing: _busy
                    ? YLListTrailing.loading()
                    : YLListTrailing.chevron(),
                onTap: _busy ? null : () => _restartCore(),
              ),
              if (Platform.isIOS) ...[
                YLListTile(
                  leading: const YLSettingIcon(
                    icon: Icons.vpn_key_rounded,
                    color: Color(0xFF8B5CF6),
                  ),
                  title: s.repairRebuildVpn,
                  subtitle: s.repairRebuildVpnHint,
                  trailing: _busy
                      ? YLListTrailing.loading()
                      : YLListTrailing.chevron(),
                  onTap: _busy
                      ? null
                      : () => _run(s.repairRebuildVpn, () async {
                          final ok = await VpnService.resetVpnProfile();
                          return ok;
                        }, actionId: 'rebuild_vpn'),
                ),
                YLListTile(
                  leading: const YLSettingIcon(
                    icon: Icons.delete_sweep_rounded,
                    color: Color(0xFFEF4444),
                  ),
                  title: s.repairClearTunnel,
                  subtitle: s.repairClearTunnelHint,
                  trailing: _busy
                      ? YLListTrailing.loading()
                      : YLListTrailing.chevron(),
                  onTap: _busy
                      ? null
                      : () => _run('清除配置', () async {
                          final ok = await VpnService.clearAppGroupConfig();
                          return ok;
                        }, actionId: 'clear_tunnel_config'),
                ),
              ],
              YLListTile(
                leading: const YLSettingIcon(
                  icon: Icons.sync_rounded,
                  color: Color(0xFF22C55E),
                ),
                title: s.repairResync,
                subtitle: s.repairResyncHint,
                trailing: _busy
                    ? YLListTrailing.loading()
                    : YLListTrailing.chevron(),
                onTap: _busy
                    ? null
                    : () => _run('同步订阅', () async {
                        final token = ref.read(authProvider).token;
                        if (token == null) {
                          AppNotifier.error(s.repairNeedLogin);
                          return false;
                        }
                        await ref
                            .read(authProvider.notifier)
                            .syncSubscription();
                        return true;
                      }, actionId: 'resync_subscription'),
              ),
              YLListTile(
                leading: const YLSettingIcon(
                  icon: Icons.cleaning_services_rounded,
                  color: Color(0xFFF59E0B),
                ),
                title: s.repairClearCache,
                subtitle: s.repairClearCacheHint,
                trailing: _busy
                    ? YLListTrailing.loading()
                    : YLListTrailing.chevron(),
                onTap: _busy
                    ? null
                    : () => _run('清除缓存', () async {
                        final appDir = await getApplicationSupportDirectory();
                        await ref
                            .read(connectionRepairActionsProvider)
                            .clearLocalCache(appDir);
                        return true;
                      }, actionId: 'clear_local_cache'),
              ),
              if (Platform.isAndroid)
                YLListTile(
                  leading: const YLSettingIcon(
                    icon: Icons.battery_saver_rounded,
                    color: Color(0xFF10B981),
                  ),
                  title: '加入电池优化白名单',
                  subtitle: 'Xiaomi / Huawei / OPPO 等厂商 Doze 休眠会杀掉 VPN',
                  trailing: _busy
                      ? YLListTrailing.loading()
                      : YLListTrailing.chevron(),
                  onTap: _busy
                      ? null
                      : () => _run('申请白名单', () async {
                          final already =
                              await VpnService.isBatteryOptimizationIgnored();
                          if (already) {
                            AppNotifier.success('已在白名单中');
                            return true;
                          }
                          // In-app rationale BEFORE the OS prompt. Android's
                          // system dialog is short and uncontextualised
                          // ("Allow YueLink to ignore battery optimizations?")
                          // — without this explainer users have no reason to
                          // trust the request. Showing the rationale here, on
                          // a user-initiated action surface (settings →
                          // connection repair), avoids the anti-pattern of
                          // surfacing the prompt at first launch.
                          if (!context.mounted) return false;
                          final proceed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('授予电池豁免?'),
                              content: const Text(
                                '小米、华为、OPPO 等国产厂商默认 30 分钟后会杀掉后台 VPN '
                                '服务，导致连接突然中断。\n\n'
                                '系统接下来会弹一个权限对话框：\n'
                                '«允许 YueLink 不进行电池优化吗?»\n\n'
                                '点「允许」后，YueLink 才能在息屏 / 长时间后台时保持 '
                                'VPN 隧道不被强制关闭。\n\n'
                                '此设置不会显著增加耗电 — VPN 的能耗主要来自心跳，'
                                'YueLink 已根据 Wi-Fi / 蜂窝自动调节。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('继续'),
                                ),
                              ],
                            ),
                          );
                          if (proceed != true) return false;
                          return VpnService.requestIgnoreBatteryOptimization();
                        }, actionId: 'battery_whitelist'),
                ),
            ],
          ),
        ),

        // ── Network diagnostics ───────────────────────────────────
        SliverToBoxAdapter(
          child: NetworkDiagnostics(header: s.diagnosticsLabel, isDark: isDark),
        ),

        // ── Reports & exports ─────────────────────────────────────
        SliverToBoxAdapter(
          child: YLSection(
            footer: s.diagnosticsHint,
            children: [
              YLListTile(
                leading: const YLSettingIcon(
                  icon: Icons.bug_report_rounded,
                  color: Color(0xFF6366F1),
                ),
                title: s.viewStartupReport,
                subtitle: s.diagnosticsHint,
                trailing: YLListTrailing.chevron(),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StartupReportPage()),
                ),
              ),
              YLListTile(
                leading: const YLSettingIcon(
                  icon: Icons.file_download_rounded,
                  color: Color(0xFF14B8A6),
                ),
                title: s.exportLogs,
                subtitle: isEn
                    ? 'Bundle core/crash/event logs into one file'
                    : '打包核心 / 崩溃 / 事件日志为单个文件',
                trailing: _busy
                    ? YLListTrailing.loading()
                    : YLListTrailing.chevron(),
                onTap: _busy ? null : () => _exportDiagnosticLogs(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Run the platform's diagnostic command list (ipconfig / ifconfig / ip etc.)
/// and assemble their (redacted) output along with a structured TUN-state
/// snapshot. Ref-coupled because the snapshot reads `connectionMode`,
/// `desktopTunStack` and writes back to `desktopTunHealthProvider`; the
/// pure parts (command list, redaction, output formatting) live in
/// `ConnectionDiagnosticsService`.
Future<String> _collectDesktopTunDiagnosticsText(WidgetRef ref) async {
  final commands = ConnectionDiagnosticsService.desktopDiagnosticCommands();
  final buffer = StringBuffer();
  buffer.writeln(await _collectDesktopTunSnapshotText(ref));
  buffer.writeln();
  for (final cmd in commands) {
    buffer.writeln('\$ ${cmd.exe} ${cmd.args.join(' ')}');
    try {
      final r = await runDiagnosticCommand(
        cmd.exe,
        cmd.args,
      ).timeout(const Duration(seconds: 5));
      final text = '${lossyUtf8(r.stdout)}\n${lossyUtf8(r.stderr)}';
      buffer.writeln(ConnectionDiagnosticsService.redactDiagnosticText(text));
    } catch (e) {
      buffer.writeln('<failed: $e>');
    }
    buffer.writeln();
  }
  return buffer.toString();
}

Future<String> _collectDesktopTunSnapshotText(WidgetRef ref) async {
  final buffer = StringBuffer();
  final manager = CoreManager.instance;
  final mode = ref.read(connectionModeProvider);
  final tunStack = ref.read(desktopTunStackProvider);
  buffer.writeln('structured_snapshot:');
  buffer.writeln('  platform: ${Platform.operatingSystem}');
  buffer.writeln('  mode: $mode');
  buffer.writeln('  tun_stack: $tunStack');
  buffer.writeln('  core_running: ${manager.isRunning}');
  buffer.writeln('  mixed_port: ${manager.mixedPort}');
  try {
    final snapshot = await DesktopTunDiagnostics.instance.inspect(
      api: manager.api,
      mixedPort: manager.mixedPort,
      mode: mode,
      tunStack: tunStack,
    );
    ref.read(desktopTunHealthProvider.notifier).set(snapshot);
    DesktopTunTelemetry.healthSnapshot(snapshot);
    buffer
      ..writeln('  state: ${snapshot.state.wireName}')
      ..writeln('  error_class: ${snapshot.errorClass}')
      ..writeln('  user_message: ${snapshot.userMessage}')
      ..writeln('  repair_action: ${snapshot.repairAction}')
      ..writeln('  driver_present: ${snapshot.driverPresent}')
      ..writeln('  has_admin: ${snapshot.hasAdmin}')
      ..writeln('  controller_ok: ${snapshot.controllerOk}')
      ..writeln('  interface_present: ${snapshot.interfacePresent}')
      ..writeln('  route_ok: ${snapshot.routeOk}')
      ..writeln('  dns_ok: ${snapshot.dnsOk}')
      ..writeln('  ipv6_enabled: ${snapshot.ipv6Enabled}')
      ..writeln('  system_proxy_enabled: ${snapshot.systemProxyEnabled}')
      ..writeln('  proxy_guard_active: ${snapshot.proxyGuardActive}')
      ..writeln('  transport_ok: ${snapshot.transportOk}')
      ..writeln('  google_ok: ${snapshot.googleOk}')
      ..writeln('  github_ok: ${snapshot.githubOk}')
      ..writeln(
        '  cleanup_ok: '
        '${snapshot.state != DesktopTunState.cleanupFailed}',
      )
      ..writeln('  repair_suggested: ${snapshot.needsRepair}')
      ..writeln('  running_verified: ${snapshot.runningVerified}');
  } catch (e) {
    buffer.writeln('  inspect_failed: ${e.toString().split('\n').first}');
  }
  return buffer.toString();
}
