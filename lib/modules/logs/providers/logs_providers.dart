import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/core_mock.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../domain/logs/log_entry.dart';
import '../../../infrastructure/repositories/log_repository.dart';
import '../../../providers/core_provider.dart';

// Re-export logLevelProvider so it can be accessed via this module too
export '../../../providers/core_provider.dart' show logLevelProvider;

/// Live log entries from mihomo.
final logEntriesProvider =
    NotifierProvider<LogEntriesNotifier, List<LogEntry>>(
  LogEntriesNotifier.new,
);

class LogEntriesNotifier extends Notifier<List<LogEntry>> {
  StreamSubscription? _sub;
  Timer? _mockTimer;
  bool _disposed = false;
  static const _maxEntries = 500;

  @override
  List<LogEntry> build() {
    _disposed = false;

    ref.onDispose(() {
      _disposed = true;
      _stopListening();
    });

    ref.listen(coreStatusProvider, (prev, next) {
      if (next == CoreStatus.running) {
        _startListening();
      } else if (next == CoreStatus.stopped) {
        _stopListening();
        state = [];
      }
    });
    // Restart stream when log level changes while core is running
    ref.listen(logLevelProvider, (prev, next) {
      if (prev != next && ref.read(coreStatusProvider) == CoreStatus.running) {
        _startListening(); // _startListening calls _stopListening first
      }
    });

    return [];
  }

  void _startListening() {
    // Ensure old subscription is fully cleaned before starting new one
    _stopListening();

    final manager = CoreManager.instance;
    final level = ref.read(logLevelProvider);

    if (manager.isMockMode) {
      // Generate mock log entries periodically
      final mockLogs = CoreMock.instance.getLogs();
      var index = 0;
      _mockTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (_disposed) return;
        final entry = mockLogs[index % mockLogs.length];
        _addEntry(LogEntry(
          type: entry['type'] ?? 'info',
          payload: entry['payload'] ?? '',
        ));
        index++;
      });
    } else {
      // Connect via LogRepository (goes through infrastructure layer)
      final repo = ref.read(logRepositoryProvider);
      _sub = repo.logStream(level: level).listen((entry) {
        if (!_disposed) _addEntry(entry);
      });
    }
  }

  /// Batch buffer — accumulates entries and flushes every 200ms to avoid
  /// creating a new List on every single log line (can be 100+/sec on debug).
  List<LogEntry>? _pendingBatch;
  Timer? _batchTimer;

  void _addEntry(LogEntry entry) {
    _pendingBatch ??= [];
    _pendingBatch!.add(entry);
    _batchTimer ??= Timer(const Duration(milliseconds: 200), _flushBatch);
  }

  void _flushBatch() {
    _batchTimer = null;
    final batch = _pendingBatch;
    if (batch == null || batch.isEmpty || _disposed) return;
    _pendingBatch = null;

    // Prepend batch (newest first) and trim to max
    final newState = [...batch.reversed, ...state];
    state = newState.length > _maxEntries
        ? newState.sublist(0, _maxEntries)
        : newState;
  }

  void _stopListening() {
    _sub?.cancel();
    _sub = null;
    _mockTimer?.cancel();
    _mockTimer = null;
    _batchTimer?.cancel();
    _batchTimer = null;
    _pendingBatch = null;
  }

  void clear() => state = [];
}
