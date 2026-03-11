import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/core_controller.dart';
import '../models/traffic.dart';
import '../models/traffic_history.dart';
import '../providers/proxy_provider.dart';
import '../l10n/app_strings.dart';
import '../services/app_notifier.dart';
import '../services/core_manager.dart';
import '../services/mihomo_api.dart';
import '../services/settings_service.dart';
import '../services/vpn_service.dart';

// ------------------------------------------------------------------
// Core state
// ------------------------------------------------------------------

enum CoreStatus { stopped, starting, running, stopping }

final coreStatusProvider =
    StateProvider<CoreStatus>((ref) => CoreStatus.stopped);

/// Whether the core is running in mock mode (no native library).
final isMockModeProvider = Provider<bool>((ref) {
  return CoreManager.instance.isMockMode;
});

/// The MihomoApi client for data operations.
final mihomoApiProvider = Provider<MihomoApi>((ref) {
  return CoreManager.instance.api;
});

// ------------------------------------------------------------------
// Settings-backed providers
// ------------------------------------------------------------------

/// Routing mode: "rule" | "global" | "direct"
final routingModeProvider = StateProvider<String>((ref) => 'rule');

/// Connection mode: "tun" | "systemProxy"
final connectionModeProvider = StateProvider<String>((ref) => 'systemProxy');

/// Log level: "info" | "debug" | "warning" | "error" | "silent"
final logLevelProvider = StateProvider<String>((ref) => 'info');

/// Whether to auto-set system proxy on connect (desktop only)
final systemProxyOnConnectProvider = StateProvider<bool>((ref) => true);

/// Whether to auto-connect on startup
final autoConnectProvider = StateProvider<bool>((ref) => true);

// ------------------------------------------------------------------
// Core actions
// ------------------------------------------------------------------

final coreActionsProvider = Provider<CoreActions>((ref) => CoreActions(ref));

class CoreActions {
  final Ref ref;
  CoreActions(this.ref);

  Future<bool> start(String configYaml) async {
    debugPrint('[CoreActions] start() called, config length: ${configYaml.length}');
    ref.read(coreStatusProvider.notifier).state = CoreStatus.starting;

    try {
      final manager = CoreManager.instance;
      debugPrint('[CoreActions] mode: ${manager.mode}, isMock: ${manager.isMockMode}');

      // 1. Check VPN Permission (Android only — always needed for VpnService)
      if (Platform.isAndroid && !manager.isMockMode) {
        final hasPerm = await VpnService.requestPermission();
        if (!hasPerm) {
          debugPrint('[CoreActions] VPN permission denied');
          ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
          AppNotifier.error(S.current.errVpnPermission);
          return false;
        }
      }

      // 2. Start Core (CoreManager handles VPN tunnel internally for Android/iOS)
      debugPrint('[CoreActions] calling CoreManager.start()...');
      final ok = await manager.start(configYaml);
      debugPrint('[CoreActions] CoreManager.start() returned: $ok');
      if (!ok) {
        ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
        AppNotifier.error(S.current.errCoreStartFailed);
        return false;
      }

      ref.read(coreStatusProvider.notifier).state = CoreStatus.running;
      AppNotifier.success(S.current.msgConnected);

      // 3. Apply routing mode from settings to running core
      final routingMode = ref.read(routingModeProvider);
      if (routingMode != 'rule') {
        try {
          final ok = await manager.api.setRoutingMode(routingMode);
          debugPrint('[CoreActions] setRoutingMode($routingMode): $ok');
        } catch (e) {
          debugPrint('[CoreActions] setRoutingMode failed: $e');
        }
      }

      // 4. Auto-set system proxy on macOS/Windows
      if ((Platform.isMacOS || Platform.isWindows) &&
          ref.read(systemProxyOnConnectProvider)) {
        await applySystemProxy();
      }

      // Trigger initial proxy data fetch
      ref.read(proxyGroupsProvider.notifier).refresh();

      return true;
    } catch (e, st) {
      debugPrint('[CoreActions] start() error: $e');
      debugPrint('[CoreActions] stack trace: $st');
      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;

      // 真实状态闭环：精准透传底层错误（如 YAML 语法错误及行号）
      String msg = e.toString();
      if (e is FormatException) {
        msg = e.message;
      } else if (e is MihomoApiException) {
        msg = S.current.errApiError(e.statusCode, e.body);
      } else {
        msg = msg.split('\n').first; // 保持提示简短
      }
      
      AppNotifier.error(S.current.errStartFailed(msg));
      return false;
    }
  }

  Future<void> stop() async {
    ref.read(coreStatusProvider.notifier).state = CoreStatus.stopping;

    try {
      // Clear system proxy on macOS/Windows
      if ((Platform.isMacOS || Platform.isWindows) &&
          ref.read(systemProxyOnConnectProvider)) {
        await clearSystemProxy();
      }

      final manager = CoreManager.instance;
      await manager.stop();

      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
      ref.read(trafficProvider.notifier).state = const Traffic();
      AppNotifier.info(S.current.msgDisconnected);
    } catch (e) {
      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
      AppNotifier.error(S.current.errStopFailed);
    }
  }

  Future<void> toggle(String configYaml) async {
    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.running) {
      await stop();
    } else if (status == CoreStatus.stopped) {
      await start(configYaml);
    }
  }

  Future<bool> applySystemProxy() async {
    final port = CoreManager.instance.mixedPort;
    final ok = await _setSystemProxy(port);
    if (!ok) {
      debugPrint('[CoreActions] System proxy setup failed for port $port');
      AppNotifier.warning(S.current.errSystemProxyFailed);
    }
    return ok;
  }

  Future<void> clearSystemProxy() async {
    await _clearSystemProxy();
  }

  static Future<bool> _setSystemProxy(int mixedPort) async {
    if (Platform.isMacOS) {
      final services = await _listNetworkServices();
      if (services.isEmpty) {
        debugPrint('[SystemProxy] No network services found');
        return false;
      }
      var anySuccess = false;
      for (final svc in services) {
        try {
          final results = await Future.wait([
            Process.run('networksetup',
                ['-setwebproxy', svc, '127.0.0.1', '$mixedPort']),
            Process.run('networksetup',
                ['-setsecurewebproxy', svc, '127.0.0.1', '$mixedPort']),
            Process.run('networksetup',
                ['-setsocksfirewallproxy', svc, '127.0.0.1', '$mixedPort']),
          ]);
          final allOk = results.every((r) => r.exitCode == 0);
          if (!allOk) {
            for (final r in results) {
              if (r.exitCode != 0) {
                debugPrint('[SystemProxy] networksetup failed for $svc: '
                    'exit=${r.exitCode} stderr=${r.stderr}');
              }
            }
          }
          // Enable each proxy type
          await Future.wait([
            Process.run('networksetup', ['-setwebproxystate', svc, 'on']),
            Process.run('networksetup',
                ['-setsecurewebproxystate', svc, 'on']),
            Process.run('networksetup',
                ['-setsocksfirewallproxystate', svc, 'on']),
          ]);
          if (allOk) anySuccess = true;
        } catch (e) {
          debugPrint('[SystemProxy] Failed to set proxy for $svc: $e');
        }
      }
      // Verify the proxy was actually set
      if (anySuccess) {
        final verified = await _verifySystemProxy(mixedPort);
        if (!verified) {
          debugPrint('[SystemProxy] WARNING: proxy set commands succeeded '
              'but verification failed');
        }
        return verified;
      }
      return false;
    } else if (Platform.isWindows) {
      final r1 = await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f'
      ]);
      final r2 = await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyServer', '/t', 'REG_SZ',
        '/d', '127.0.0.1:$mixedPort', '/f'
      ]);
      if (r1.exitCode != 0 || r2.exitCode != 0) {
        debugPrint('[SystemProxy] Windows registry update failed: '
            'r1=${r1.exitCode} r2=${r2.exitCode}');
        return false;
      }
      return true;
    }
    return false;
  }

  /// Verify that macOS system proxy is actually pointing to our port.
  static Future<bool> _verifySystemProxy(int mixedPort) async {
    if (!Platform.isMacOS) return true;
    try {
      final services = await _listNetworkServices();
      for (final svc in services) {
        final result = await Process.run(
            'networksetup', ['-getwebproxy', svc]);
        final output = result.stdout as String;
        if (output.contains('Enabled: Yes') &&
            output.contains('Port: $mixedPort')) {
          debugPrint('[SystemProxy] Verified proxy on $svc: port $mixedPort');
          return true;
        }
      }
      debugPrint('[SystemProxy] Verification failed: no service has '
          'proxy set to port $mixedPort');
      return false;
    } catch (e) {
      debugPrint('[SystemProxy] Verification error: $e');
      return false;
    }
  }

  static Future<void> _clearSystemProxy() async {
    if (Platform.isMacOS) {
      final services = await _listNetworkServices();
      for (final svc in services) {
        try {
          await Future.wait([
            Process.run('networksetup', ['-setwebproxystate', svc, 'off']),
            Process.run(
                'networksetup', ['-setsecurewebproxystate', svc, 'off']),
            Process.run(
                'networksetup', ['-setsocksfirewallproxystate', svc, 'off']),
          ]);
        } catch (e) {
          debugPrint('[SystemProxy] Failed to clear proxy for $svc: $e');
        }
      }
    } else if (Platform.isWindows) {
      final r = await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f'
      ]);
      if (r.exitCode != 0) {
        debugPrint('[SystemProxy] Windows registry clear failed: ${r.stderr}');
      }
    }
  }

  /// Enumerate all active network services on macOS.
  static Future<List<String>> _listNetworkServices() async {
    try {
      final result =
          await Process.run('networksetup', ['-listallnetworkservices']);
      return (result.stdout as String)
          .split('\n')
          .skip(1) // First line is the header notice
          .map((l) => l.startsWith('*') ? l.substring(1).trim() : l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return ['Wi-Fi']; // Fallback
    }
  }
}

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
// Core heartbeat — detects unexpected crashes
// ------------------------------------------------------------------

/// Periodically pings the core API while running.
/// If the API stops responding (3 consecutive failures), automatically
/// transitions state to stopped so the UI reflects the real situation.
final coreHeartbeatProvider = Provider<void>((ref) {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return;

  final manager = CoreManager.instance;
  if (manager.isMockMode) return; // mock never crashes

  var failures = 0;
  final timer = Timer.periodic(const Duration(seconds: 5), (_) async {
    final ok = await manager.api.isAvailable();
    if (ok) {
      failures = 0;
    } else {
      failures++;
      if (failures >= 3) {
        ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
        ref.read(trafficProvider.notifier).state = const Traffic();
      }
    }
  });
  ref.onDispose(() => timer.cancel());
});

// ------------------------------------------------------------------
// Traffic streaming
// ------------------------------------------------------------------

final trafficProvider = StateProvider<Traffic>((ref) => const Traffic());

final trafficHistoryProvider =
    StateProvider<TrafficHistory>((ref) => TrafficHistory());

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
      ref.read(trafficHistoryProvider.notifier).state = history;
      ref.read(dailyTrafficProvider.notifier).add(t.up, t.down);
    });
    ref.onDispose(() => timer.cancel());
  } else {
    final sub = manager.stream.trafficStream().listen((t) {
      ref.read(trafficProvider.notifier).state =
          Traffic(up: t.up, down: t.down);
      final history = ref.read(trafficHistoryProvider);
      history.add(t.up, t.down);
      ref.read(trafficHistoryProvider.notifier).state = history;
      ref.read(dailyTrafficProvider.notifier).add(t.up, t.down);
    });
    ref.onDispose(() => sub.cancel());
  }
});

// ------------------------------------------------------------------
// Memory usage streaming
// ------------------------------------------------------------------

final memoryUsageProvider = StateProvider<int>((ref) => 0);

final memoryStreamProvider = Provider<void>((ref) {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return;

  final manager = CoreManager.instance;
  if (manager.isMockMode) return;

  final sub = manager.stream.memoryStream().listen((bytes) {
    ref.read(memoryUsageProvider.notifier).state = bytes;
  });
  ref.onDispose(() => sub.cancel());
});
