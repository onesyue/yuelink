import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/kernel/core_manager.dart';
import '../../core/platform/vpn_service.dart';
import '../../core/profile/profile_service.dart';
import '../../core/providers/core_provider.dart';
import '../../i18n/app_strings.dart';
import '../../shared/app_notifier.dart';
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
            buffer.writeln(await f.readAsString());
          } catch (e) {
            buffer.writeln('<read failed: $e>');
          }
        } else {
          buffer.writeln('<not present>');
        }
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
      final activeId = ref.read(activeProfileIdProvider);
      if (activeId == null) {
        AppNotifier.error(S.current.repairNeedLogin);
        return;
      }
      final config = await ProfileService.loadConfig(activeId);
      if (config == null) {
        AppNotifier.error(S.current.repairActionFailed);
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

  Future<void> _run(String label, Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Stop core first to avoid conflicts
      if (CoreManager.instance.isRunning) {
        await CoreManager.instance.stop();
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
              children: const [ServiceModeRow()],
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
                    : () => _run('一键修复', () async {
                        if (Platform.isIOS) {
                          await VpnService.resetVpnProfile();
                          await VpnService.clearAppGroupConfig();
                        }
                        final token = ref.read(authProvider).token;
                        if (token != null) {
                          await ref
                              .read(authProvider.notifier)
                              .syncSubscription();
                        }
                        return true;
                      }),
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

// ── Network diagnostics widget ─────────────────────────────────────────────

class _DiagEndpoint {
  final String label;
  final String url;
  const _DiagEndpoint(this.label, this.url);
}

// User-facing labels abstract away internal endpoint URLs.
// Each test probes a standard reachability target — no internal server
// URLs exposed to the user.
const _kDiagEndpoints = [
  _DiagEndpoint('Google', 'https://www.gstatic.com/generate_204'),
  _DiagEndpoint('Cloudflare', 'https://cp.cloudflare.com/generate_204'),
];

enum _DiagStatus { idle, testing, success, failed }

class _DiagResult {
  final _DiagStatus status;
  final int? latencyMs;
  final String? error;
  const _DiagResult({
    this.status = _DiagStatus.idle,
    this.latencyMs,
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
      futures.add(_testEndpoint(endpoint.url));
    }

    final results = await Future.wait(futures);
    if (mounted) {
      setState(() {
        _results = results;
        _testing = false;
      });
    }
  }

  Future<_DiagResult> _testEndpoint(String url) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final sw = Stopwatch()..start();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      sw.stop();
      // Drain the response body
      await response.drain<void>();
      final ms = sw.elapsedMilliseconds;
      // Accept any non-server-error response as reachable
      if (response.statusCode < 500) {
        return _DiagResult(status: _DiagStatus.success, latencyMs: ms);
      }
      return _DiagResult(
        status: _DiagStatus.failed,
        latencyMs: ms,
        error: 'HTTP ${response.statusCode}',
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('TimeoutException')) {
        return const _DiagResult(status: _DiagStatus.failed, error: '超时');
      }
      return _DiagResult(
        status: _DiagStatus.failed,
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
    if (result.status == _DiagStatus.success) return '连接正常';
    return result.error ?? '未知错误';
  }
}
