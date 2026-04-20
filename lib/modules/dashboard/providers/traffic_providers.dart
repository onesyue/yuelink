import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../core/storage/settings_service.dart';
import '../../../domain/models/traffic.dart';
import '../../../infrastructure/repositories/traffic_repository.dart';
import '../../../core/providers/core_provider.dart';

// ------------------------------------------------------------------
// Daily traffic accumulation
// ------------------------------------------------------------------

final dailyTrafficProvider =
    NotifierProvider<DailyTrafficNotifier, (int, int)>(
  DailyTrafficNotifier.new,
);

class DailyTrafficNotifier extends Notifier<(int, int)> {
  Timer? _flushTimer;
  bool _loaded = false;
  bool _disposed = false;
  String _loadedDateKey = '';

  @override
  (int, int) build() {
    _loaded = false;
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _flushTimer?.cancel();
      // Fire-and-forget final flush so we don't lose partial data on exit
      SettingsService.saveTodayTraffic(state.$1, state.$2);
    });
    _load();
    return (0, 0);
  }

  static String _todayKey() {
    final d = DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  Future<void> _load() async {
    _loadedDateKey = _todayKey();
    final data = await SettingsService.getTodayTraffic();
    if (!_disposed) {
      state = (data['up']!, data['down']!);
      _loaded = true;
    }
  }

  void add(int upDelta, int downDelta) {
    if (!_loaded || _disposed) return;

    // Reset counters on day rollover (midnight boundary)
    final today = _todayKey();
    if (today != _loadedDateKey) {
      _loadedDateKey = today;
      state = (upDelta, downDelta);
      SettingsService.saveTodayTraffic(upDelta, downDelta);
      return;
    }

    state = (state.$1 + upDelta, state.$2 + downDelta);
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 30), _flush);
  }

  Future<void> _flush() async {
    await SettingsService.saveTodayTraffic(state.$1, state.$2);
  }
}

// ------------------------------------------------------------------
// Traffic chart UI state
// ------------------------------------------------------------------

/// Selected time range for the traffic chart in seconds: 60 / 300 / 1800.
final trafficChartRangeProvider =
    NotifierProvider<TrafficChartRangeNotifier, int>(
        TrafficChartRangeNotifier.new);

class TrafficChartRangeNotifier extends Notifier<int> {
  @override
  int build() => 60;

  void set(int seconds) => state = seconds;
}

/// Whether the traffic chart is locked (frozen at snapshot).
final trafficChartLockedProvider =
    NotifierProvider<TrafficChartLockedNotifier, bool>(
        TrafficChartLockedNotifier.new);

class TrafficChartLockedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool locked) => state = locked;
}

// ------------------------------------------------------------------
// Traffic streaming
// ------------------------------------------------------------------

final trafficStreamProvider = Provider<void>((ref) {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return;

  // Battery optimization: pause traffic WebSocket when app is in background.
  // The stream auto-reconnects when appInBackgroundProvider flips back to false
  // because Riverpod re-evaluates this provider on any watched state change.
  final inBackground = ref.watch(appInBackgroundProvider);
  if (inBackground) return;

  // Closure-local dispose flag. `timer.cancel()` doesn't interrupt a tick
  // already past its `await`; broadcast streams may still dispatch a
  // queued event to a just-cancelled subscriber. Each callback below
  // early-returns on this flag before touching any provider state.
  bool disposed = false;
  ref.onDispose(() => disposed = true);

  final manager = CoreManager.instance;
  // Shared history instance — mutated in-place, version bump triggers rebuilds.
  final history = ref.read(trafficHistoryProvider);

  if (manager.isMockMode) {
    final timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final t = await manager.core.getTraffic();
      if (disposed) return;
      final traffic = Traffic(up: t.up, down: t.down);
      ref.read(trafficProvider.notifier).state = traffic;
      history.add(t.up, t.down);
      ref.read(trafficHistoryVersionProvider.notifier).state = history.version;
      ref.read(dailyTrafficProvider.notifier).add(t.up, t.down);
    });
    ref.onDispose(() => timer.cancel());
  } else {
    final repo = ref.watch(trafficRepositoryProvider);
    // Single WebSocket subscription drives both speed display and chart history.
    // Two separate WebSocket connections to the same mihomo /traffic endpoint
    // is unreliable — mihomo may silently drop the second connection, leaving
    // trafficHistoryProvider empty and the chart blank.
    final trafficSub = repo.trafficStream().listen((t) {
      if (disposed) return;
      ref.read(trafficProvider.notifier).state = t;
      ref.read(dailyTrafficProvider.notifier).add(t.up, t.down);
      history.add(t.up, t.down);
      ref.read(trafficHistoryVersionProvider.notifier).state = history.version;
    });
    ref.onDispose(() => trafficSub.cancel());
  }
});

// ------------------------------------------------------------------
// Memory usage streaming
// ------------------------------------------------------------------

final memoryStreamProvider = Provider<void>((ref) {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return;

  // Battery optimization: pause memory WebSocket when app is in background.
  final inBackground = ref.watch(appInBackgroundProvider);
  if (inBackground) return;

  final manager = CoreManager.instance;
  if (manager.isMockMode) return;

  bool disposed = false;
  ref.onDispose(() => disposed = true);

  // Throttle is handled inside TrafficRepository.memoryStream() (5 s window)
  final repo = ref.watch(trafficRepositoryProvider);
  final sub = repo.memoryStream().listen((bytes) {
    if (disposed) return;
    ref.read(memoryUsageProvider.notifier).state = bytes;
  });
  ref.onDispose(() => sub.cancel());
});
