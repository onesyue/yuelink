import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/core_controller.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../core/storage/settings_service.dart';
import '../../../domain/models/traffic.dart';
import '../../../domain/models/traffic_history.dart';
import '../../../infrastructure/repositories/traffic_repository.dart';
import '../../../providers/core_provider.dart';

// ------------------------------------------------------------------
// Daily traffic accumulation
// ------------------------------------------------------------------

final dailyTrafficProvider =
    StateNotifierProvider<DailyTrafficNotifier, (int, int)>(
  (ref) => DailyTrafficNotifier(),
);

class DailyTrafficNotifier extends StateNotifier<(int, int)> {
  Timer? _flushTimer;
  bool _loaded = false;
  String _loadedDateKey = '';

  DailyTrafficNotifier() : super((0, 0)) {
    _load();
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
    if (mounted) {
      state = (data['up']!, data['down']!);
      _loaded = true;
    }
  }

  void add(int upDelta, int downDelta) {
    if (!_loaded || !mounted) return;

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

  @override
  void dispose() {
    _flushTimer?.cancel();
    // Fire-and-forget final flush so we don't lose partial data on exit
    SettingsService.saveTodayTraffic(state.$1, state.$2);
    super.dispose();
  }
}

// ------------------------------------------------------------------
// Traffic chart UI state
// ------------------------------------------------------------------

/// Selected time range for the traffic chart in seconds: 60 / 300 / 1800.
final trafficChartRangeProvider = StateProvider<int>((ref) => 60);

/// Whether the traffic chart is locked (frozen at snapshot).
final trafficChartLockedProvider = StateProvider<bool>((ref) => false);

// ------------------------------------------------------------------
// Traffic streaming
// ------------------------------------------------------------------

final trafficStreamProvider = Provider<void>((ref) {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return;

  final manager = CoreManager.instance;

  if (manager.isMockMode) {
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final t = CoreController.instance.getTraffic();
      final traffic = Traffic(up: t.up, down: t.down);
      ref.read(trafficProvider.notifier).state = traffic;
      final history = ref.read(trafficHistoryProvider);
      history.add(t.up, t.down);
      ref.read(trafficHistoryProvider.notifier).state = history.copy();
      ref.read(dailyTrafficProvider.notifier).add(t.up, t.down);
    });
    ref.onDispose(() => timer.cancel());
  } else {
    final repo = ref.watch(trafficRepositoryProvider);
    // Single WebSocket subscription drives both speed display and chart history.
    // Two separate WebSocket connections to the same mihomo /traffic endpoint
    // is unreliable — mihomo may silently drop the second connection, leaving
    // trafficHistoryProvider empty and the chart blank.
    final trafficHistory = TrafficHistory();
    final trafficSub = repo.trafficStream().listen((t) {
      ref.read(trafficProvider.notifier).state = t;
      ref.read(dailyTrafficProvider.notifier).add(t.up, t.down);
      trafficHistory.add(t.up, t.down);
      ref.read(trafficHistoryProvider.notifier).state = trafficHistory.copy();
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

  final manager = CoreManager.instance;
  if (manager.isMockMode) return;

  // Throttle is handled inside TrafficRepository.memoryStream() (5 s window)
  final repo = ref.watch(trafficRepositoryProvider);
  final sub = repo.memoryStream().listen((bytes) {
    ref.read(memoryUsageProvider.notifier).state = bytes;
  });
  ref.onDispose(() => sub.cancel());
});
