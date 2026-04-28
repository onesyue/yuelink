import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../domain/logs/log_entry.dart';
import '../../../infrastructure/repositories/log_repository.dart';
import '../../../core/providers/core_provider.dart';

// Re-export logLevelProvider so it can be accessed via this module too
export '../../../core/providers/core_provider.dart' show logLevelProvider;

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
        if (!ref.read(appInBackgroundProvider)) _startListening();
      } else if (next == CoreStatus.stopped) {
        _stopListening();
        state = [];
      }
    });
    // Battery: pause the WebSocket subscription whenever the app is in
    // background. The Logs page itself isn't visible there, but pre-fix
    // the stream kept pushing into an in-memory buffer 24/7 — a slow drip
    // of CPU + radio wakeups for a screen the user can't see. State is
    // preserved on resume so the user comes back to the entries they
    // already saw, with newer entries arriving from the moment they're
    // back. Acceptable trade-off vs always-on.
    ref.listen(appInBackgroundProvider, (prev, inBg) {
      final running = ref.read(coreStatusProvider) == CoreStatus.running;
      if (!running) return;
      if (inBg) {
        _stopListening();
      } else {
        _startListening();
      }
    });
    // `ref.listen` only fires on CHANGE — if the provider is rebuilt after
    // the core is already running (opening the Logs page mid-session), we
    // must kick off listening ourselves; otherwise the tail stays empty
    // until the next core state change.
    if (ref.read(coreStatusProvider) == CoreStatus.running &&
        !ref.read(appInBackgroundProvider)) {
      _startListening();
    }
    // Restart stream when log level changes while core is running
    // (skip when backgrounded — resume listener will pick the new level up).
    ref.listen(logLevelProvider, (prev, next) {
      if (prev != next &&
          ref.read(coreStatusProvider) == CoreStatus.running &&
          !ref.read(appInBackgroundProvider)) {
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
      // Generate mock log entries periodically — pulled from the unified
      // ClashCore interface (snapshot-only; real mode uses websocket stream).
      final mockLogs = manager.core.getLogsSnapshot();
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
