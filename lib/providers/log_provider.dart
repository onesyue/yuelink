import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/core_mock.dart';
import '../services/core_manager.dart';
import '../services/mihomo_stream.dart';
import 'core_provider.dart';

/// Live log entries from mihomo.
final logEntriesProvider =
    StateNotifierProvider<LogEntriesNotifier, List<LogEntry>>(
  (ref) => LogEntriesNotifier(ref),
);

class LogEntriesNotifier extends StateNotifier<List<LogEntry>> {
  final Ref ref;
  StreamSubscription? _sub;
  Timer? _mockTimer;
  static const _maxEntries = 500;

  LogEntriesNotifier(this.ref) : super([]) {
    ref.listen(coreStatusProvider, (prev, next) {
      if (next == CoreStatus.running) {
        _startListening();
      } else if (next == CoreStatus.stopped) {
        _stopListening();
        state = [];
      }
    });
  }

  void _startListening() {
    final manager = CoreManager.instance;

    if (manager.isMockMode) {
      // Generate mock log entries periodically
      final mockLogs = CoreMock.instance.getLogs();
      var index = 0;
      _mockTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!mounted) return;
        final entry = mockLogs[index % mockLogs.length];
        _addEntry(LogEntry(
          type: entry['type'] ?? 'info',
          payload: entry['payload'] ?? '',
        ));
        index++;
      });
    } else {
      // Connect to real WebSocket log stream
      _sub = manager.stream.logStream().listen((entry) {
        if (mounted) _addEntry(entry);
      });
    }
  }

  void _addEntry(LogEntry entry) {
    final updated = [entry, ...state];
    if (updated.length > _maxEntries) {
      state = updated.sublist(0, _maxEntries);
    } else {
      state = updated;
    }
  }

  void _stopListening() {
    _sub?.cancel();
    _sub = null;
    _mockTimer?.cancel();
    _mockTimer = null;
  }

  void clear() => state = [];

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }
}

// logLevelProvider moved to core_provider.dart
