import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/kernel/core_manager.dart';
import '../../core/platform/vpn_service.dart';
import '../../core/profile/profile_service.dart';
import '../../core/providers/core_provider.dart';
import '../../core/storage/settings_service.dart';
import '../../core/tun/desktop_tun_diagnostics.dart';
import '../../core/tun/desktop_tun_state.dart';
import '../../core/tun/desktop_tun_telemetry.dart';
import '../../i18n/app_strings.dart';
import '../../shared/app_notifier.dart';
import '../../shared/diagnostic_text.dart';
import '../../shared/log_export_sources.dart';
import '../../shared/log_export_service.dart';
import '../../shared/telemetry.dart';
import '../../shared/widgets/setting_icon.dart';
import '../../shared/widgets/yl_list.dart';
import '../../shared/widgets/yl_scaffold.dart';
import '../../theme.dart';
import '../profiles/providers/profiles_providers.dart';
import '../yue_auth/providers/yue_auth_providers.dart';
import 'sub/widgets/service_mode_row.dart';
import 'startup_report_page.dart';

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

  Future<void> _exportDiagnosticLogs() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final appDir = await getApplicationSupportDirectory();
      // v1.0.22 P3-A: expand `core.log` to include rotated sidecars
      // (`.2` and `.1` if present) so the export captures recent
      // history that the Go-side rotation may have shifted out of the
      // live file mid-session. Other sources pass through unchanged.
      final sources = expandRotatedLogSources(const [
        'core.log',
        'crash.log',
        'event.log',
        'startup_report.json',
      ]);
      final buffer = StringBuffer();
      buffer.writeln('YueLink diagnostic bundle');
      buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
      buffer.writeln(
        'Platform: ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}',
      );
      buffer.writeln();
      var found = 0;
      for (final name in sources) {
        final f = File('${appDir.path}/$name');
        // Sidecars are routinely absent on freshly-installed
        // instances or sessions that never crossed the rotation
        // threshold. Skip the "═══ name ═══ <not present>" header
        // for absent rotated sidecars to keep the bundle readable;
        // still emit the header for the canonical sources so the
        // user can see at a glance which expected files were missing.
        final isRotatedSidecar = name.startsWith('core.log.');
        if (isRotatedSidecar && !f.existsSync()) continue;
        buffer.writeln('═══ $name ${'═' * (60 - name.length)}');
        if (f.existsSync()) {
          found++;
          try {
            buffer.writeln(await readLogTextLossy(f));
          } catch (e) {
            buffer.writeln('<read failed: $e>');
          }
        } else {
          buffer.writeln('<not present>');
        }
        buffer.writeln();
      }
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        buffer.writeln('═══ desktop_tun_diagnostics ═════════════════════════');
        buffer.writeln(await _collectDesktopTunDiagnosticsText(ref));
        buffer.writeln();
      }
      if (found == 0) {
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
        content: buffer.toString(),
        dialogTitle: S.current.exportLogs,
      );
      if (!mounted) return;
      if (result.cancelled) return;
      if (result.saved) {
        Telemetry.event(TelemetryEvents.diagnosticExport);
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
    try {
      final config = await _loadActiveConfigForRepair();
      if (config == null) {
        return;
      }
      final ok = await ref.read(coreActionsProvider).restart(config);
      if (!mounted) return;
      final label = S.current.repairRestartCore;
      if (ok) {
        AppNotifier.success('$label ${S.current.repairActionDone}');
      } else {
        AppNotifier.error('$label ${S.current.repairActionFailed}');
      }
    } catch (e) {
      if (mounted) {
        AppNotifier.error(
          '${S.current.repairRestartCore} ${S.current.repairActionFailed}: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _loadActiveConfigForRepair() async {
    final activeId =
        ref.read(activeProfileIdProvider) ??
        await SettingsService.getActiveProfileId();
    if (activeId == null) {
      AppNotifier.error(
        S.current.isEn ? 'No active subscription selected' : '未选择活动订阅',
      );
      return null;
    }
    final config = await ProfileService.loadConfig(activeId);
    if (config == null || config.trim().isEmpty) {
      AppNotifier.error(
        S.current.isEn
            ? 'Active subscription config is empty. Re-sync first.'
            : '活动订阅配置为空，请先重新同步订阅',
      );
      return null;
    }
    return config;
  }

  Future<bool> _oneClickRepairAndReconnect() async {
    if (Platform.isIOS) {
      await VpnService.resetVpnProfile();
      await VpnService.clearAppGroupConfig();
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // Clear stale system proxy before reconnecting. In TUN mode this avoids
      // controller self-loop; in system-proxy mode start() will reapply the
      // proxy if the user has "set proxy on connect" enabled.
      await ref.read(coreActionsProvider).clearSystemProxy();
      if (Platform.isMacOS) await CoreActions.restoreTunDns();
    }

    final token = ref.read(authProvider).token;
    if (token != null) {
      await ref.read(authProvider.notifier).syncSubscription();
    }

    final config = await _loadActiveConfigForRepair();
    if (config == null) return false;
    return ref.read(coreActionsProvider).start(config);
  }

  Future<void> _run(String label, Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Stop through the lifecycle manager, not CoreManager directly. The
      // lifecycle path is the only one that clears system proxy, restores
      // macOS TUN DNS, records desktop_tun_* telemetry, and drives the UI
      // status back through `stopping -> stopped`.
      if (CoreManager.instance.isRunning) {
        await ref.read(coreActionsProvider).stop();
      }
      final ok = await action();
      if (mounted) {
        if (ok) {
          AppNotifier.success('$label ${S.current.repairActionDone}');
        } else {
          AppNotifier.error('$label ${S.current.repairActionFailed}');
        }
      }
    } catch (e) {
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
          child: YLSection(header: 'STATUS', children: [_StatusTile()]),
        ),

        if (isDesktop)
          SliverToBoxAdapter(
            child: YLSection(
              header: isEn ? 'Desktop TUN' : '桌面 TUN',
              children: const [ServiceModeRow(), _DesktopTunLayeredStatus()],
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
                    : () => _run(s.repairOneClick, _oneClickRepairAndReconnect),
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
                        }),
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
                        }),
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
                      }),
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
                        final targets = [
                          'config.yaml',
                          'startup_report.json',
                          'core.log',
                          'crash.log',
                          'event.log',
                        ];
                        for (final name in targets) {
                          final f = File('${appDir.path}/$name');
                          if (f.existsSync()) f.deleteSync();
                        }
                        return true;
                      }),
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
                        }),
                ),
            ],
          ),
        ),

        // ── Network diagnostics ───────────────────────────────────
        SliverToBoxAdapter(
          child: _NetworkDiagnostics(
            header: s.diagnosticsLabel,
            isDark: isDark,
          ),
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
                onTap: _busy ? null : _exportDiagnosticLogs,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<String> _collectDesktopTunDiagnosticsText(WidgetRef ref) async {
  final commands = <(String, List<String>)>[];
  if (Platform.isWindows) {
    commands.addAll(const [
      ('ipconfig', ['/all']),
      ('route', ['print']),
      ('netsh', ['interface', 'ipv4', 'show', 'interfaces']),
      ('netsh', ['interface', 'ipv6', 'show', 'interfaces']),
      ('netsh', ['winhttp', 'show', 'proxy']),
      (
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Get-NetAdapter | Select-Object Name,Status,InterfaceDescription | Format-Table -AutoSize',
        ],
      ),
      (
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Get-DnsClientServerAddress | Select-Object InterfaceAlias,AddressFamily,ServerAddresses | Format-Table -AutoSize',
        ],
      ),
    ]);
  } else if (Platform.isMacOS) {
    commands.addAll(const [
      ('ifconfig', []),
      ('netstat', ['-rn']),
      ('scutil', ['--dns']),
      ('networksetup', ['-getdnsservers', 'Wi-Fi']),
      ('route', ['-n', 'get', 'default']),
      ('lsof', ['-i', ':9090']),
    ]);
  } else if (Platform.isLinux) {
    commands.addAll(const [
      ('ip', ['addr']),
      ('ip', ['route']),
      ('ip', ['-6', 'route']),
      ('resolvectl', ['status']),
      ('systemctl', ['status', 'systemd-resolved', '--no-pager']),
      ('ss', ['-lntup']),
      ('ls', ['-l', '/dev/net/tun']),
    ]);
  }

  final buffer = StringBuffer();
  buffer.writeln(await _collectDesktopTunSnapshotText(ref));
  buffer.writeln();
  for (final (exe, args) in commands) {
    buffer.writeln('\$ $exe ${args.join(' ')}');
    try {
      final r = await runDiagnosticCommand(
        exe,
        args,
      ).timeout(const Duration(seconds: 5));
      final text = '${lossyUtf8(r.stdout)}\n${lossyUtf8(r.stderr)}';
      buffer.writeln(_redactDiagnosticText(text));
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
    ref.read(desktopTunHealthProvider.notifier).state = snapshot;
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
      ..writeln('  repair_suggested: ${snapshot.needsRepair}')
      ..writeln('  running_verified: ${snapshot.runningVerified}');
  } catch (e) {
    buffer.writeln('  inspect_failed: ${e.toString().split('\n').first}');
  }
  return buffer.toString();
}

String _redactDiagnosticText(String input) {
  return input
      .replaceAll(RegExp(r'([A-Fa-f0-9]{2}[:-]){5}[A-Fa-f0-9]{2}'), '<mac>')
      .replaceAll(RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b'), '<ip>')
      .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+-]+'), 'Bearer <redacted>');
}

// ── Helper widgets ──────────────────────────────────────────────────────────

/// Connection status row — shows whether the core is currently running, or
/// surfaces the last failure if the most recent startup attempt did not
/// succeed.
class _StatusTile extends StatelessWidget {
  const _StatusTile();

  @override
  Widget build(BuildContext context) {
    final running = CoreManager.instance.isRunning;
    final report = CoreManager.instance.lastReport;
    final lastResult = report?.overallSuccess;

    final IconData icon;
    final Color color;
    final String title;
    String? subtitle;
    if (running) {
      icon = Icons.check_circle_rounded;
      color = YLColors.connected;
      title = '连接正常';
    } else if (lastResult == false) {
      icon = Icons.error_rounded;
      color = YLColors.error;
      title = '上次连接失败';
      subtitle = report?.failureSummary ?? '未知错误';
    } else {
      icon = Icons.radio_button_unchecked_rounded;
      color = YLColors.zinc400;
      title = '未连接';
    }

    return YLListTile(
      leading: YLSettingIcon(icon: icon, color: color),
      title: title,
      subtitle: subtitle,
    );
  }
}

class _DesktopTunLayeredStatus extends ConsumerStatefulWidget {
  const _DesktopTunLayeredStatus();

  @override
  ConsumerState<_DesktopTunLayeredStatus> createState() =>
      _DesktopTunLayeredStatusState();
}

class _DesktopTunLayeredStatusState
    extends ConsumerState<_DesktopTunLayeredStatus> {
  bool _checking = false;

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final snapshot = await DesktopTunDiagnostics.instance.inspect(
        api: CoreManager.instance.api,
        mixedPort: CoreManager.instance.mixedPort,
        mode: ref.read(connectionModeProvider),
        tunStack: ref.read(desktopTunStackProvider),
      );
      ref.read(desktopTunHealthProvider.notifier).state = snapshot;
      DesktopTunTelemetry.healthSnapshot(snapshot);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(desktopTunHealthProvider);
    final mode = ref.watch(connectionModeProvider);
    final isTun = mode == 'tun';
    final rows = _rows(snapshot, isTun: isTun);
    return Column(
      children: [
        YLListTile(
          leading: YLSettingIcon(
            icon: isTun ? Icons.hub_rounded : Icons.http_rounded,
            color: isTun ? YLColors.tunConnected : YLColors.zinc500,
          ),
          title: '当前模式',
          subtitle: isTun ? 'TUN · 分层诊断已启用' : '系统代理 · TUN 未开启',
          trailing: _checking
              ? YLListTrailing.loading()
              : YLListTrailing.value('重新检测'),
          onTap: _checking ? null : _refresh,
        ),
        for (final row in rows)
          YLListTile(
            leading: YLSettingIcon(icon: row.icon, color: row.color),
            title: row.title,
            subtitle: row.subtitle,
            trailing: YLListTrailing.badge(
              text: row.ok ? 'OK' : row.badge,
              color: row.ok ? YLColors.connected : row.color,
            ),
          ),
      ],
    );
  }

  List<_TunDiagRow> _rows(DesktopTunSnapshot? s, {required bool isTun}) {
    if (!isTun) {
      return const [
        _TunDiagRow(
          title: 'TUN 层',
          subtitle: '当前未使用 TUN，节点超时不会归因到 TUN',
          ok: true,
          badge: 'OFF',
          icon: Icons.power_settings_new_rounded,
          color: YLColors.zinc400,
        ),
      ];
    }
    if (s == null) {
      return const [
        _TunDiagRow(
          title: 'TUN 状态',
          subtitle: '尚未检测；点击重新检测',
          ok: false,
          badge: '待检测',
          icon: Icons.help_rounded,
          color: YLColors.connecting,
        ),
      ];
    }
    return [
      _TunDiagRow(
        title: 'App 层',
        subtitle: s.systemProxyEnabled
            ? 'TUN 与系统代理同时开启，可能造成控制面回环'
            : 'mode=${s.mode} · stack=${s.tunStack}',
        ok: !s.systemProxyEnabled,
        badge: '冲突',
        icon: Icons.desktop_windows_rounded,
        color: s.systemProxyEnabled ? YLColors.error : YLColors.connected,
      ),
      _TunDiagRow(
        title: 'Core 层',
        subtitle: s.controllerOk ? 'mihomo 控制接口可访问' : 'mihomo 已启动但控制接口不可用',
        ok: s.controllerOk,
        badge: '失败',
        icon: Icons.memory_rounded,
        color: s.controllerOk ? YLColors.connected : YLColors.error,
      ),
      _TunDiagRow(
        title: 'TUN 层',
        subtitle: _tunLayerSubtitle(s),
        ok: s.driverPresent && s.hasAdmin && s.interfacePresent,
        badge: '异常',
        icon: Icons.route_rounded,
        color: (s.driverPresent && s.hasAdmin && s.interfacePresent)
            ? YLColors.connected
            : YLColors.error,
      ),
      _TunDiagRow(
        title: 'Route / DNS',
        subtitle: s.routeOk
            ? (s.dnsOk ? '路由和 DNS 已验证' : 'DNS 未接管')
            : 'TUN 网卡已创建，但路由未接管',
        ok: s.routeOk && s.dnsOk,
        badge: '异常',
        icon: Icons.dns_rounded,
        color: (s.routeOk && s.dnsOk) ? YLColors.connected : YLColors.error,
      ),
      _TunDiagRow(
        title: '目标站层',
        subtitle:
            'Google ${s.googleOk ? "OK" : "失败"} · GitHub ${s.githubOk ? "OK" : "失败"}；Claude 403 会归因 AI 出口受限，不归因 TUN',
        ok: s.googleOk || s.githubOk,
        badge: '异常',
        icon: Icons.public_rounded,
        color: (s.googleOk || s.githubOk) ? YLColors.connected : YLColors.error,
      ),
    ];
  }

  String _tunLayerSubtitle(DesktopTunSnapshot s) {
    if (!s.driverPresent) return 'TUN 驱动/设备缺失';
    if (!s.hasAdmin) return '需要管理员权限或服务模式权限';
    if (!s.interfacePresent) return 'TUN interface 未创建';
    return 'TUN interface 已创建';
  }
}

class _TunDiagRow {
  const _TunDiagRow({
    required this.title,
    required this.subtitle,
    required this.ok,
    required this.badge,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final bool ok;
  final String badge;
  final IconData icon;
  final Color color;
}

// ── Network diagnostics widget ─────────────────────────────────────────────

class _DiagEndpoint {
  final String label;
  final String url;
  final bool aiTarget;
  const _DiagEndpoint(this.label, this.url, {this.aiTarget = false});
}

// User-facing labels abstract away internal endpoint URLs.
// Each test probes a standard reachability target — no internal server
// URLs exposed to the user.
const _kDiagEndpoints = [
  _DiagEndpoint('Google', 'https://www.gstatic.com/generate_204'),
  _DiagEndpoint('GitHub', 'https://github.com/'),
  _DiagEndpoint('Claude', 'https://claude.ai/', aiTarget: true),
  _DiagEndpoint('ChatGPT', 'https://chatgpt.com/', aiTarget: true),
];

enum _DiagStatus { idle, testing, success, limited, failed }

class _DiagResult {
  final _DiagStatus status;
  final int? latencyMs;
  final int? statusCode;
  final String? errorClass;
  final String? error;
  const _DiagResult({
    this.status = _DiagStatus.idle,
    this.latencyMs,
    this.statusCode,
    this.errorClass,
    this.error,
  });
}

class _NetworkDiagnostics extends StatefulWidget {
  final String header;
  final bool isDark;
  const _NetworkDiagnostics({required this.header, required this.isDark});

  @override
  State<_NetworkDiagnostics> createState() => _NetworkDiagnosticsState();
}

class _NetworkDiagnosticsState extends State<_NetworkDiagnostics> {
  List<_DiagResult> _results = List.filled(
    _kDiagEndpoints.length,
    const _DiagResult(),
  );
  bool _testing = false;

  Future<void> _runDiagnostics() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _results = List.generate(
        _kDiagEndpoints.length,
        (_) => const _DiagResult(status: _DiagStatus.testing),
      );
    });

    final futures = <Future<_DiagResult>>[];
    for (final endpoint in _kDiagEndpoints) {
      futures.add(_testEndpoint(endpoint));
    }

    final results = await Future.wait(futures);
    if (mounted) {
      setState(() {
        _results = results;
        _testing = false;
      });
    }
  }

  Future<_DiagResult> _testEndpoint(_DiagEndpoint endpoint) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final sw = Stopwatch()..start();
      final request = await client.getUrl(Uri.parse(endpoint.url));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      sw.stop();
      // Drain the response body
      await response.drain<void>();
      final ms = sw.elapsedMilliseconds;
      final statusCode = response.statusCode;
      if (endpoint.aiTarget && (statusCode == 403 || statusCode == 429)) {
        return _DiagResult(
          status: _DiagStatus.limited,
          latencyMs: ms,
          statusCode: statusCode,
          errorClass: statusCode == 403 ? 'ai_blocked' : 'http_429',
          error: statusCode == 403 ? 'AI 出口受限' : 'AI 请求被限速',
        );
      }
      // Accept any non-server-error response as reachable
      if (statusCode < 500) {
        return _DiagResult(
          status: _DiagStatus.success,
          latencyMs: ms,
          statusCode: statusCode,
          errorClass: 'ok',
        );
      }
      return _DiagResult(
        status: _DiagStatus.failed,
        latencyMs: ms,
        statusCode: statusCode,
        errorClass: 'target_failed',
        error: '目标站点 HTTP $statusCode',
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('TimeoutException')) {
        return const _DiagResult(
          status: _DiagStatus.failed,
          errorClass: 'timeout',
          error: '节点或本地网络超时',
        );
      }
      final lower = msg.toLowerCase();
      if (lower.contains('failed host lookup') ||
          lower.contains('nodename nor servname') ||
          lower.contains('name or service not known')) {
        return const _DiagResult(
          status: _DiagStatus.failed,
          errorClass: 'dns_failed',
          error: 'DNS 解析失败',
        );
      }
      if (lower.contains('handshake') || lower.contains('certificate')) {
        return const _DiagResult(
          status: _DiagStatus.failed,
          errorClass: 'tls_failed',
          error: 'TLS 握手失败',
        );
      }
      if (lower.contains('connection reset')) {
        return const _DiagResult(
          status: _DiagStatus.failed,
          errorClass: 'connection_reset',
          error: '连接被重置',
        );
      }
      return _DiagResult(
        status: _DiagStatus.failed,
        errorClass: 'tcp_failed',
        error: msg.length > 40 ? '${msg.substring(0, 40)}...' : msg,
      );
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return YLSection(
      header: widget.header,
      children: [
        YLListTile(
          leading: const YLSettingIcon(
            icon: Icons.network_check_rounded,
            color: Color(0xFF0EA5E9),
          ),
          title: S.current.networkDiagnostics,
          trailing: _testing
              ? YLListTrailing.loading()
              : YLListTrailing.value(_testing ? '检测中...' : '开始检测'),
          onTap: _testing ? null : _runDiagnostics,
        ),
        for (var i = 0; i < _kDiagEndpoints.length; i++)
          _DiagRow(endpoint: _kDiagEndpoints[i], result: _results[i]),
      ],
    );
  }
}

class _DiagRow extends StatelessWidget {
  final _DiagEndpoint endpoint;
  final _DiagResult result;
  const _DiagRow({required this.endpoint, required this.result});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color iconColor;
    switch (result.status) {
      case _DiagStatus.idle:
        icon = Icons.circle_outlined;
        iconColor = YLColors.zinc400;
        break;
      case _DiagStatus.testing:
        icon = Icons.sync_rounded;
        iconColor = YLColors.zinc400;
        break;
      case _DiagStatus.success:
        icon = Icons.check_circle_rounded;
        iconColor = YLColors.connected;
        break;
      case _DiagStatus.limited:
        icon = Icons.shield_rounded;
        iconColor = YLColors.connecting;
        break;
      case _DiagStatus.failed:
        icon = Icons.cancel_rounded;
        iconColor = YLColors.error;
        break;
    }

    final Widget? trailing;
    if (result.status == _DiagStatus.testing) {
      trailing = YLListTrailing.loading();
    } else if (result.latencyMs != null) {
      trailing = YLListTrailing.badge(
        text: '${result.latencyMs}ms',
        color: result.status == _DiagStatus.success
            ? YLColors.connected
            : result.status == _DiagStatus.limited
            ? YLColors.connecting
            : YLColors.error,
      );
    } else {
      trailing = null;
    }

    return YLListTile(
      leading: YLSettingIcon(icon: icon, color: iconColor),
      title: endpoint.label,
      subtitle: _subtitle(result),
      trailing: trailing,
    );
  }

  String _subtitle(_DiagResult result) {
    if (result.status == _DiagStatus.idle) return '等待检测';
    if (result.status == _DiagStatus.testing) return '正在检测...';
    if (result.status == _DiagStatus.success) {
      return result.statusCode == null
          ? '连接正常'
          : '连接正常 · HTTP ${result.statusCode}';
    }
    if (result.status == _DiagStatus.limited) {
      return result.error ?? 'AI 出口受限';
    }
    return result.error ?? '未知错误';
  }
}
