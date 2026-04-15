import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/kernel/core_manager.dart';
import '../../core/platform/vpn_service.dart';
import '../../i18n/app_strings.dart';
import '../../shared/app_notifier.dart';
import '../../shared/log_export_service.dart';
import '../../shared/telemetry.dart';
import '../../theme.dart';
import '../yue_auth/providers/yue_auth_providers.dart';
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
      const sources = [
        'core.log',
        'crash.log',
        'event.log',
        'startup_report.json',
      ];
      final buffer = StringBuffer();
      buffer.writeln('YueLink diagnostic bundle');
      buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
      buffer.writeln('Platform: ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}');
      buffer.writeln();
      var found = 0;
      for (final name in sources) {
        final f = File('${appDir.path}/$name');
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
      if (mounted) AppNotifier.error('$label ${S.current.repairActionFailed}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.current.repairTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status ──
          _Card(isDark: isDark, children: [
            _StatusRow(isDark: isDark),
          ]),
          const SizedBox(height: 8),

          // ── Repair actions ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(s.repairTools.toUpperCase(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: YLColors.zinc500,
                  letterSpacing: -0.08,
                )),
          ),
          _Card(isDark: isDark, children: [
            if (Platform.isIOS) ...[
              _ActionRow(
                icon: Icons.vpn_key_outlined,
                label: s.repairRebuildVpn,
                subtitle: s.repairRebuildVpnHint,
                isDark: isDark,
                busy: _busy,
                onTap: () => _run(s.repairRebuildVpn, () async {
                  final ok = await VpnService.resetVpnProfile();
                  return ok;
                }),
              ),
              Divider(height: 1, color: divColor),
              _ActionRow(
                icon: Icons.delete_sweep_outlined,
                label: s.repairClearTunnel,
                subtitle: s.repairClearTunnelHint,
                isDark: isDark,
                busy: _busy,
                onTap: () => _run('清除配置', () async {
                  final ok = await VpnService.clearAppGroupConfig();
                  return ok;
                }),
              ),
              Divider(height: 1, color: divColor),
            ],
            _ActionRow(
              icon: Icons.sync_outlined,
              label: s.repairResync,
              subtitle: s.repairResyncHint,
              isDark: isDark,
              busy: _busy,
              onTap: () => _run('同步订阅', () async {
                final token = ref.read(authProvider).token;
                if (token == null) {
                  AppNotifier.error(s.repairNeedLogin);
                  return false;
                }
                await ref.read(authProvider.notifier).syncSubscription();
                return true;
              }),
            ),
            Divider(height: 1, color: divColor),
            _ActionRow(
              icon: Icons.cleaning_services_outlined,
              label: s.repairClearCache,
              subtitle: s.repairClearCacheHint,
              isDark: isDark,
              busy: _busy,
              onTap: () => _run('清除缓存', () async {
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
          ]),
          const SizedBox(height: 8),

          // ── Diagnostics (merged: network probes + startup report) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(S.current.diagnosticsLabel.toUpperCase(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: YLColors.zinc500,
                  letterSpacing: -0.08,
                )),
          ),
          _NetworkDiagnostics(isDark: isDark),
          const SizedBox(height: 10),
          _Card(isDark: isDark, children: [
            _ActionRow(
              icon: Icons.bug_report_outlined,
              label: s.viewStartupReport,
              subtitle: S.current.diagnosticsHint,
              isDark: isDark,
              busy: false,
              trailing: const Icon(Icons.chevron_right,
                  size: 18, color: YLColors.zinc400),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const StartupReportPage())),
            ),
            Divider(height: 1, color: divColor),
            _ActionRow(
              icon: Icons.file_download_outlined,
              label: s.exportLogs,
              subtitle: Localizations.localeOf(context).languageCode == 'en'
                  ? 'Bundle core/crash/event logs into one file'
                  : '打包核心 / 崩溃 / 事件日志为单个文件',
              isDark: isDark,
              busy: _busy,
              onTap: _exportDiagnosticLogs,
            ),
          ]),
          const SizedBox(height: 8),

          // ── One-click full repair ──
          SizedBox(
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
                          await ref.read(authProvider.notifier).syncSubscription();
                        }
                        return true;
                      }),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: Text(_busy ? s.repairRunning : s.repairOneClick),
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? YLColors.zinc700 : YLColors.zinc800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(YLRadius.lg)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            Localizations.localeOf(context).languageCode == 'en'
                ? 'One-click repair: stop connection → reset tunnel → clear cache\nReconnect after repair completes'
                : '一键修复将停止连接 → 删除旧隧道 → 清除配置缓存\n修复后重新点击连接即可',
            style: YLText.caption.copyWith(color: YLColors.zinc400),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Helper widgets ──────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  final bool isDark;
  const _StatusRow({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final running = CoreManager.instance.isRunning;
    final report = CoreManager.instance.lastReport;
    final lastResult = report?.overallSuccess;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            running
                ? Icons.check_circle_rounded
                : lastResult == false
                    ? Icons.error_rounded
                    : Icons.radio_button_unchecked_rounded,
            color: running
                ? YLColors.connected
                : lastResult == false
                    ? Colors.red
                    : YLColors.zinc400,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              running
                  ? '连接正常'
                  : lastResult == false
                      ? '上次连接失败: ${report?.failureSummary ?? "未知错误"}'
                      : '未连接',
              style: YLText.body.copyWith(
                  color: isDark ? YLColors.zinc200 : YLColors.zinc700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _Card({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isDark;
  final bool busy;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isDark,
    required this.busy,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: isDark ? YLColors.zinc300 : YLColors.zinc600),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: YLText.body.copyWith(
                          fontWeight: FontWeight.w500,
                          color:
                              isDark ? YLColors.zinc200 : YLColors.zinc700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: YLText.caption.copyWith(color: YLColors.zinc400)),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
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
  _DiagEndpoint('国际网络', 'https://www.gstatic.com/generate_204'),
  _DiagEndpoint('Cloudflare', 'https://cp.cloudflare.com/generate_204'),
  _DiagEndpoint('国内网络', 'https://www.baidu.com'),
];

enum _DiagStatus { idle, testing, success, failed }

class _DiagResult {
  final _DiagStatus status;
  final int? latencyMs;
  final String? error;
  const _DiagResult({this.status = _DiagStatus.idle, this.latencyMs, this.error});
}

class _NetworkDiagnostics extends StatefulWidget {
  final bool isDark;
  const _NetworkDiagnostics({required this.isDark});

  @override
  State<_NetworkDiagnostics> createState() => _NetworkDiagnosticsState();
}

class _NetworkDiagnosticsState extends State<_NetworkDiagnostics> {
  List<_DiagResult> _results = List.filled(_kDiagEndpoints.length, const _DiagResult());
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
      final response = await request.close().timeout(const Duration(seconds: 5));
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
      return _DiagResult(status: _DiagStatus.failed, error: msg.length > 40 ? '${msg.substring(0, 40)}...' : msg);
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return _Card(isDark: isDark, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Icon(Icons.network_check_outlined,
                size: 20,
                color: isDark ? YLColors.zinc300 : YLColors.zinc600),
            const SizedBox(width: 12),
            Expanded(
              child: Text(S.current.networkDiagnostics,
                  style: YLText.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isDark ? YLColors.zinc200 : YLColors.zinc700)),
            ),
            TextButton(
              onPressed: _testing ? null : _runDiagnostics,
              child: Text(
                _testing ? '检测中...' : '开始检测',
                style: YLText.caption.copyWith(
                    color: _testing ? YLColors.zinc400 : YLColors.zinc600,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
      for (var i = 0; i < _kDiagEndpoints.length; i++) ...[
        Divider(
          height: 1,
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _diagIcon(_results[i].status),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_kDiagEndpoints[i].label,
                        style: YLText.caption.copyWith(
                            fontWeight: FontWeight.w500,
                            color: isDark ? YLColors.zinc200 : YLColors.zinc700)),
                    Text(
                      _diagSubtitle(_results[i]),
                      style: YLText.caption.copyWith(
                          color: YLColors.zinc400, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_results[i].latencyMs != null)
                Text('${_results[i].latencyMs}ms',
                    style: YLText.caption.copyWith(
                        color: _results[i].status == _DiagStatus.success
                            ? YLColors.connected
                            : Colors.red,
                        fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    ]);
  }

  Widget _diagIcon(_DiagStatus status) {
    switch (status) {
      case _DiagStatus.idle:
        return const Icon(Icons.circle_outlined, size: 16, color: YLColors.zinc400);
      case _DiagStatus.testing:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: YLColors.zinc400),
        );
      case _DiagStatus.success:
        return const Icon(Icons.check_circle_rounded, size: 16, color: YLColors.connected);
      case _DiagStatus.failed:
        return const Icon(Icons.cancel_rounded, size: 16, color: Colors.red);
    }
  }

  String _diagSubtitle(_DiagResult result) {
    if (result.status == _DiagStatus.idle) return '等待检测';
    if (result.status == _DiagStatus.testing) return '正在检测...';
    if (result.status == _DiagStatus.success) return '连接正常';
    return result.error ?? '未知错误';
  }
}
