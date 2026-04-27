import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Lightweight persistent event logger for beta debugging.
///
/// Writes tagged lines to event.log in the app support directory.
/// Survives app restarts. Users can share the file for bug reports.
/// Release builds only — debugPrint is stripped in release mode.
///
/// Usage:
///   EventLog.write('[Auth] login_ok email=user@x.com');
///   EventLog.write('[Sync] sync_failed error=timeout');
class EventLog {
  EventLog._();

  static const _kFileName = 'event.log';
  static const _kMaxLines = 500; // rotate when file exceeds this
  static File? _file;

  static Future<File> _getFile() async {
    _file ??= File(
      '${(await getApplicationSupportDirectory()).path}/$_kFileName',
    );
    return _file!;
  }

  /// Append a tagged event line. Non-blocking — errors are silently swallowed.
  static void write(String tag) {
    _append(tag);
  }

  /// Keys in a context map whose values should never land on disk. Matched
  /// case-insensitively against the bare key name.
  static const _redactedKeys = <String>{
    // Credentials
    'token',
    'access_token',
    'auth_token',
    'authorization',
    'auth_data',
    'password',
    'secret',
    'api_key',
    'apikey',
    'cookie',
    // PII / account identifiers — XBoard & checkin surface these in
    // context maps during sync/diagnostic paths. Keeping them out of
    // event.log is a compliance baseline, not a per-caller judgment.
    'subscribe_url',
    'subscribeurl',
    'order_no',
    'orderno',
    'email',
    'phone',
    'ip',
  };

  /// Format a tagged event with context key/values. Safe for logs:
  /// - sensitive keys ([_redactedKeys]) are replaced with `<redacted>`
  /// - whitespace (including embedded newlines) is collapsed to single spaces
  /// - the full line is truncated to ~160 chars, ending with `...`
  ///
  /// `tag` may be passed bare (`'Auth'`) or already bracketed (`'[Auth]'`).
  static String formatTagged(
    String tag,
    String event, {
    Map<String, Object?>? context,
  }) {
    final normTag = tag.startsWith('[') ? tag : '[$tag]';
    final buf = StringBuffer('$normTag $event');
    if (context != null) {
      for (final entry in context.entries) {
        final key = entry.key;
        final isSecret = _redactedKeys.contains(key.toLowerCase());
        final rawValue = entry.value == null ? '' : entry.value.toString();
        final value = isSecret ? '<redacted>' : _normalizeWs(rawValue);
        buf.write(' $key=$value');
      }
    }
    return _clampLine(buf.toString());
  }

  /// Append a formatted tagged event. Preferred over [write] when you have
  /// structured context — the formatter handles redaction + clamping so
  /// callers don't have to.
  static void writeTagged(
    String tag,
    String event, {
    Map<String, Object?>? context,
  }) {
    _append(formatTagged(tag, event, context: context));
  }

  static String _normalizeWs(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _clampLine(String line) {
    const maxLen = 160;
    if (line.length <= maxLen) return line;
    return '${line.substring(0, maxLen - 3)}...';
  }

  static void _append(String tag) async {
    try {
      final f = await _getFile();
      final now = DateTime.now().toIso8601String().substring(0, 19);
      final line = '$now $tag\n';

      // Simple rotation: if file > _kMaxLines lines, keep last half
      if (f.existsSync()) {
        final lines = await f.readAsLines();
        if (lines.length >= _kMaxLines) {
          await f.writeAsString(
            '${lines.skip(lines.length ~/ 2).join('\n')}\n',
          );
        }
      }

      await f.writeAsString(line, mode: FileMode.append);
    } catch (_) {
      // Never crash the app for logging errors
    }
  }

  /// Read last N lines for display or export.
  static Future<String> tail({int lines = 100}) async {
    try {
      final f = await _getFile();
      if (!f.existsSync()) return '';
      final all = await f.readAsLines();
      return all.skip(all.length > lines ? all.length - lines : 0).join('\n');
    } catch (_) {
      return '';
    }
  }

  /// Delete the log file (e.g., on logout).
  static Future<void> clear() async {
    try {
      final f = await _getFile();
      if (f.existsSync()) await f.delete();
      _file = null;
    } catch (_) {}
  }
}
