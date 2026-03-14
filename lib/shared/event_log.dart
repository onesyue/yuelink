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

  static void _append(String tag) async {
    try {
      final f = await _getFile();
      final now = DateTime.now().toIso8601String().substring(0, 19);
      final line = '$now $tag\n';

      // Simple rotation: if file > _kMaxLines lines, keep last half
      if (f.existsSync()) {
        final lines = await f.readAsLines();
        if (lines.length >= _kMaxLines) {
          await f.writeAsString(lines.skip(lines.length ~/ 2).join('\n') + '\n');
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
