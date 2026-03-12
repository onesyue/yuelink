import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datasources/mihomo_stream.dart';
import '../../core/kernel/core_manager.dart';

/// Repository that exposes the log stream from mihomo.
/// Wraps CoreManager.instance.stream so providers never call it directly.
class LogRepository {
  final MihomoStream _stream;

  LogRepository(this._stream);

  /// Returns a stream of [LogEntry] items at the given log level.
  Stream<LogEntry> logStream({String level = 'info'}) {
    return _stream.logStream(level: level);
  }
}

final logRepositoryProvider = Provider<LogRepository>((ref) {
  return LogRepository(CoreManager.instance.stream);
});
