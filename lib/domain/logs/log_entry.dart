/// A single log entry from mihomo.
///
/// Pure Dart — no Flutter or network dependencies.
class LogEntry {
  final String type; // info, warning, error, debug
  final String payload;
  final DateTime timestamp;

  LogEntry({
    required this.type,
    required this.payload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
