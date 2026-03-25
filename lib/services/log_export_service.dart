import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../shared/app_notifier.dart';
import '../l10n/app_strings.dart';

/// Production-grade log collector with PII redaction.
///
/// Collects: core.log (Go), crash.log (Dart), event.log (business events),
/// startup_report.json (diagnostics). Redacts sensitive data (IPs, tokens,
/// passwords) before export.
class LogExportService {
  LogExportService._();

  // ── Redaction patterns ──────────────────────────────────────────────

  static List<RegExp> get _redactPatterns => [
    // Auth tokens (Bearer, api_key, token=)
    RegExp(r'(Bearer\s+)\S+'),
    RegExp(r'(api_key=)\S+'),
    RegExp(r'(token=)\S+'),
    RegExp(r'(Token=")[^"]+'),
    RegExp(r'(auth_data[":\s]+)[^\s,"}{]+'),
    // Passwords
    RegExp(r'(password[":\s]+)[^\s,"}{]+'),
    // Real server IPs (IPv4 with port, not 127.0.0.1 or 0.0.0.0)
    RegExp(r'(?<!127\.0\.0\.)(?<!0\.0\.0\.)\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(:\d+)?'),
    // Email addresses
    RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b'),
    // UUID
    RegExp(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'),
    // Subscribe URLs (contain user tokens)
    RegExp(r'(https?://\S+/subscribe\?)\S+'),
  ];

  /// Redact sensitive information from log text.
  static String redact(String text) {
    var result = text;
    for (final pattern in _redactPatterns) {
      result = result.replaceAllMapped(pattern, (m) {
        // Preserve the key/prefix, redact only the value
        if (m.groupCount > 0 && m.group(1) != null) {
          return '${m.group(1)}[REDACTED]';
        }
        return '[REDACTED]';
      });
    }
    return result;
  }

  // ── Collection ──────────────────────────────────────────────────────

  /// Collect all available logs into a single redacted text file.
  static Future<String> collectRedactedLogs() async {
    final appDir = await getApplicationSupportDirectory();
    final buf = StringBuffer();

    buf.writeln('═══ YueLink Diagnostic Log ═══');
    buf.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buf.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buf.writeln();

    // Startup report
    await _appendFile(buf, '── Startup Report ──',
        File('${appDir.path}/startup_report.json'), maxLines: 100);

    // Core log (Go mihomo)
    await _appendFile(buf, '── Core Log (last 200 lines) ──',
        File('${appDir.path}/core.log'), maxLines: 200);

    // Crash log (Dart)
    await _appendFile(buf, '── Crash Log ──',
        File('${appDir.path}/crash.log'), maxLines: 100);

    // Event log (business events)
    await _appendFile(buf, '── Event Log ──',
        File('${appDir.path}/event.log'), maxLines: 100);

    return redact(buf.toString());
  }

  static Future<void> _appendFile(
      StringBuffer buf, String header, File file,
      {int maxLines = 200}) async {
    buf.writeln(header);
    try {
      if (await file.exists()) {
        final lines = await file.readAsLines();
        final start = lines.length > maxLines ? lines.length - maxLines : 0;
        for (var i = start; i < lines.length; i++) {
          buf.writeln(lines[i]);
        }
      } else {
        buf.writeln('(not found)');
      }
    } catch (e) {
      buf.writeln('(read error: $e)');
    }
    buf.writeln();
  }

  // ── Export actions ──────────────────────────────────────────────────

  /// Copy redacted logs to clipboard.
  static Future<void> copyToClipboard() async {
    final logs = await collectRedactedLogs();
    await Clipboard.setData(ClipboardData(text: logs));
    AppNotifier.success(S.current.exportLogsCopied);
  }

  /// Save redacted logs to a file via system file picker.
  static Future<void> saveToFile() async {
    final logs = await collectRedactedLogs();
    final now = DateTime.now();
    final fileName = 'yuelink_logs_'
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}'
        '.txt';
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: S.current.exportLogs,
        fileName: fileName,
        bytes: Uint8List.fromList(logs.codeUnits),
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
      AppNotifier.success(S.current.isEn ? 'Logs exported' : '日志已导出');
    } catch (e) {
      debugPrint('[LogExportService] saveToFile error: $e');
      AppNotifier.error(S.current.isEn ? 'Export failed' : '导出失败');
    }
  }
}
