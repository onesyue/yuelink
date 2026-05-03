import 'dart:io';

import '../../../shared/diagnostic_text.dart';
import '../../../shared/log_export_sources.dart';

/// Pure-data helpers for the connection-repair page: log-bundle assembly,
/// diagnostic redaction, endpoint-probe result classification.
///
/// Riverpod-coupled orchestrations live in `ConnectionRepairActions`.
/// Side-effecting probes (running mihomo, mutating providers, emitting
/// telemetry) stay in the page until they're worth abstracting.
class ConnectionDiagnosticsService {
  const ConnectionDiagnosticsService._();

  // ── Log bundle ─────────────────────────────────────────────────────────

  /// Assemble a diagnostic log bundle from files in [appDir].
  ///
  /// Reads `core.log` (and any rotated `core.log.1` / `core.log.2`
  /// sidecars present), `crash.log`, `event.log`, `startup_report.json`.
  /// Per-source headers are emitted even when the file is absent so the
  /// reader can see at a glance which expected files were missing — except
  /// for rotated sidecars, which are silently skipped when absent (they
  /// only exist after rotation, so a fresh install would otherwise show
  /// noisy `<not present>` lines for them).
  ///
  /// [extraSection] is appended verbatim under a `desktop_tun_diagnostics`
  /// header — used by the page to inject Ref-coupled platform diagnostic
  /// command output that doesn't belong inside this pure helper.
  static Future<LogBundle> buildLogBundle({
    required Directory appDir,
    String? extraSection,
  }) async {
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

    if (extraSection != null && extraSection.isNotEmpty) {
      buffer.writeln('═══ desktop_tun_diagnostics ═════════════════════════');
      buffer.writeln(extraSection);
      buffer.writeln();
    }

    return LogBundle(content: buffer.toString(), filesFound: found);
  }

  // ── Redaction ──────────────────────────────────────────────────────────

  /// Mask MAC addresses, IPv4 literals, and `Bearer <token>` substrings.
  /// Applied to platform diagnostic command output before it lands in the
  /// exported bundle so users don't ship MACs/IPs/tokens to support.
  static String redactDiagnosticText(String input) {
    return input
        .replaceAll(RegExp(r'([A-Fa-f0-9]{2}[:-]){5}[A-Fa-f0-9]{2}'), '<mac>')
        .replaceAll(RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b'), '<ip>')
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+-]+'), 'Bearer <redacted>');
  }

  // ── Desktop diagnostic commands ────────────────────────────────────────

  /// Platform-specific diagnostic commands collected into the export
  /// bundle. Returns an empty list on platforms without TUN diagnostics
  /// (mobile / unknown).
  static List<DiagnosticCommand> desktopDiagnosticCommands() {
    if (Platform.isWindows) {
      return const [
        DiagnosticCommand('ipconfig', ['/all']),
        DiagnosticCommand('route', ['print']),
        DiagnosticCommand('netsh', ['interface', 'ipv4', 'show', 'interfaces']),
        DiagnosticCommand('netsh', ['interface', 'ipv6', 'show', 'interfaces']),
        DiagnosticCommand('netsh', ['winhttp', 'show', 'proxy']),
        DiagnosticCommand('powershell', [
          '-NoProfile',
          '-Command',
          'Get-NetAdapter | Select-Object Name,Status,InterfaceDescription | Format-Table -AutoSize',
        ]),
        DiagnosticCommand('powershell', [
          '-NoProfile',
          '-Command',
          'Get-DnsClientServerAddress | Select-Object InterfaceAlias,AddressFamily,ServerAddresses | Format-Table -AutoSize',
        ]),
      ];
    }
    if (Platform.isMacOS) {
      return const [
        DiagnosticCommand('ifconfig', []),
        DiagnosticCommand('netstat', ['-rn']),
        DiagnosticCommand('scutil', ['--dns']),
        DiagnosticCommand('networksetup', ['-getdnsservers', 'Wi-Fi']),
        DiagnosticCommand('route', ['-n', 'get', 'default']),
        DiagnosticCommand('lsof', ['-i', ':9090']),
      ];
    }
    if (Platform.isLinux) {
      return const [
        DiagnosticCommand('ip', ['addr']),
        DiagnosticCommand('ip', ['route']),
        DiagnosticCommand('ip', ['-6', 'route']),
        DiagnosticCommand('resolvectl', ['status']),
        DiagnosticCommand('systemctl', [
          'status',
          'systemd-resolved',
          '--no-pager',
        ]),
        DiagnosticCommand('ss', ['-lntup']),
        DiagnosticCommand('ls', ['-l', '/dev/net/tun']),
      ];
    }
    return const [];
  }

  // ── Endpoint probe classification ──────────────────────────────────────

  /// Map a successful HTTP response (no thrown error) to an
  /// [EndpointResult]. `aiTarget` enables the 403/429-as-`limited`
  /// rule so AI-blocked exits don't surface as outright failures —
  /// they're reachable but rate-limited or geo-blocked, which is a
  /// different remediation than "node down".
  static EndpointResult classifyHttpResponse({
    required int statusCode,
    required int latencyMs,
    required bool aiTarget,
  }) {
    if (aiTarget && (statusCode == 403 || statusCode == 429)) {
      return EndpointResult(
        status: EndpointStatus.limited,
        latencyMs: latencyMs,
        statusCode: statusCode,
        errorClass: statusCode == 403 ? 'ai_blocked' : 'http_429',
        error: statusCode == 403 ? 'AI 出口受限' : 'AI 请求被限速',
      );
    }
    if (statusCode < 500) {
      return EndpointResult(
        status: EndpointStatus.success,
        latencyMs: latencyMs,
        statusCode: statusCode,
        errorClass: 'ok',
      );
    }
    return EndpointResult(
      status: EndpointStatus.failed,
      latencyMs: latencyMs,
      statusCode: statusCode,
      errorClass: 'target_failed',
      error: '目标站点 HTTP $statusCode',
    );
  }

  /// Map a thrown probe error to an [EndpointResult] with a stable
  /// `errorClass` tag. The tag is the durable contract — text changes
  /// with translations, but `dns_failed` / `tls_failed` / `timeout` /
  /// `connection_reset` / `tcp_failed` are what telemetry and downstream
  /// triage logic key off.
  static EndpointResult classifyHttpError(Object error) {
    final msg = error.toString();
    if (msg.contains('TimeoutException')) {
      return const EndpointResult(
        status: EndpointStatus.failed,
        errorClass: 'timeout',
        error: '节点或本地网络超时',
      );
    }
    final lower = msg.toLowerCase();
    if (lower.contains('failed host lookup') ||
        lower.contains('nodename nor servname') ||
        lower.contains('name or service not known')) {
      return const EndpointResult(
        status: EndpointStatus.failed,
        errorClass: 'dns_failed',
        error: 'DNS 解析失败',
      );
    }
    if (lower.contains('handshake') || lower.contains('certificate')) {
      return const EndpointResult(
        status: EndpointStatus.failed,
        errorClass: 'tls_failed',
        error: 'TLS 握手失败',
      );
    }
    if (lower.contains('connection reset')) {
      return const EndpointResult(
        status: EndpointStatus.failed,
        errorClass: 'connection_reset',
        error: '连接被重置',
      );
    }
    return EndpointResult(
      status: EndpointStatus.failed,
      errorClass: 'tcp_failed',
      error: msg.length > 40 ? '${msg.substring(0, 40)}...' : msg,
    );
  }
}

// ── Types ────────────────────────────────────────────────────────────────

/// Result of [ConnectionDiagnosticsService.buildLogBundle].
class LogBundle {
  final String content;

  /// Number of canonical source files that existed on disk when the
  /// bundle was assembled. Reflects "files found", not "files
  /// successfully read" — a present-but-unreadable file still counts
  /// (its `<read failed>` marker is in [content]).
  final int filesFound;

  const LogBundle({required this.content, required this.filesFound});
}

/// One probe row in the network-diagnostic table.
enum EndpointStatus { idle, testing, success, limited, failed }

class EndpointResult {
  final EndpointStatus status;
  final int? latencyMs;
  final int? statusCode;
  final String? errorClass;
  final String? error;
  const EndpointResult({
    this.status = EndpointStatus.idle,
    this.latencyMs,
    this.statusCode,
    this.errorClass,
    this.error,
  });
}

class EndpointSpec {
  final String label;
  final String url;
  final bool aiTarget;
  const EndpointSpec(this.label, this.url, {this.aiTarget = false});
}

/// Default endpoint set for the network-diagnostics widget. Labels are
/// user-facing and abstract away internal endpoint URLs; each test probes
/// a standard reachability target with no internal server URLs exposed.
const kDefaultDiagEndpoints = <EndpointSpec>[
  EndpointSpec('Google', 'https://www.gstatic.com/generate_204'),
  EndpointSpec('GitHub', 'https://github.com/'),
  EndpointSpec('Claude', 'https://claude.ai/', aiTarget: true),
  EndpointSpec('ChatGPT', 'https://chatgpt.com/', aiTarget: true),
];

/// `(executable, args)` pair for a desktop diagnostic command. Plain
/// record-shaped class so tests can inspect by field.
class DiagnosticCommand {
  final String exe;
  final List<String> args;
  const DiagnosticCommand(this.exe, this.args);
}
