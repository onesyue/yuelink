import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../ffi/core_controller.dart';
import '../models/traffic.dart';
import '../models/traffic_history.dart';
import '../services/core_manager.dart';
import '../services/mihomo_api.dart';
import '../services/unlock_test_service.dart';
import '../services/vpn_service.dart';

// ------------------------------------------------------------------
// Core state
// ------------------------------------------------------------------

enum CoreStatus { stopped, starting, running, stopping }

final coreStatusProvider =
    StateProvider<CoreStatus>((ref) => CoreStatus.stopped);

final coreInitProvider = FutureProvider<bool>((ref) async {
  final appDir = await getApplicationSupportDirectory();
  return CoreController.instance.init(appDir.path);
});

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
final connectionModeProvider = StateProvider<String>((ref) => 'tun');

/// Log level: "info" | "debug" | "warning" | "error" | "silent"
final logLevelProvider = StateProvider<String>((ref) => 'info');

/// Whether to auto-set system proxy on connect (desktop only)
final systemProxyOnConnectProvider = StateProvider<bool>((ref) => true);

/// Whether to auto-connect on startup
final autoConnectProvider = StateProvider<bool>((ref) => false);

// ------------------------------------------------------------------
// Core actions
// ------------------------------------------------------------------

final coreActionsProvider = Provider<CoreActions>((ref) => CoreActions(ref));

class CoreActions {
  final Ref ref;
  CoreActions(this.ref);

  Future<bool> start(String configYaml) async {
    ref.read(coreStatusProvider.notifier).state = CoreStatus.starting;

    await Future.delayed(const Duration(milliseconds: 300));

    final manager = CoreManager.instance;
    final ok = await manager.start(configYaml);
    if (!ok) {
      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
      return false;
    }

    // Start platform VPN tunnel (skip in mock mode)
    if (!manager.isMockMode) {
      await VpnService.startVpn();
    }

    ref.read(coreStatusProvider.notifier).state = CoreStatus.running;

    // Apply routing mode from settings to running core
    final routingMode = ref.read(routingModeProvider);
    if (routingMode != 'rule') {
      try {
        await manager.api.setRoutingMode(routingMode);
      } catch (_) {}
    }

    // Auto-set system proxy on macOS/Windows
    if ((Platform.isMacOS || Platform.isWindows) &&
        ref.read(systemProxyOnConnectProvider)) {
      try {
        await _setSystemProxy(manager.mixedPort);
      } catch (_) {}
    }

    // Trigger initial proxy data fetch
    ref.read(proxyRefreshProvider);

    return true;
  }

  Future<void> stop() async {
    ref.read(coreStatusProvider.notifier).state = CoreStatus.stopping;
    await Future.delayed(const Duration(milliseconds: 300));

    // Clear system proxy on macOS/Windows
    if ((Platform.isMacOS || Platform.isWindows) &&
        ref.read(systemProxyOnConnectProvider)) {
      try {
        await _clearSystemProxy();
      } catch (_) {}
    }

    final manager = CoreManager.instance;
    if (!manager.isMockMode) {
      await VpnService.stopVpn();
    }
    await manager.stop();

    ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
    ref.read(trafficProvider.notifier).state = const Traffic();
  }

  Future<void> toggle(String configYaml) async {
    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.running) {
      await stop();
    } else if (status == CoreStatus.stopped) {
      await start(configYaml);
    }
  }

  static Future<void> _setSystemProxy(int mixedPort) async {
    if (Platform.isMacOS) {
      await Process.run(
          'networksetup', ['-setwebproxy', 'Wi-Fi', '127.0.0.1', '$mixedPort']);
      await Process.run('networksetup',
          ['-setsecurewebproxy', 'Wi-Fi', '127.0.0.1', '$mixedPort']);
      await Process.run('networksetup',
          ['-setsocksfirewallproxy', 'Wi-Fi', '127.0.0.1', '$mixedPort']);
    } else if (Platform.isWindows) {
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f'
      ]);
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyServer', '/t', 'REG_SZ',
        '/d', '127.0.0.1:$mixedPort', '/f'
      ]);
    }
  }

  static Future<void> _clearSystemProxy() async {
    if (Platform.isMacOS) {
      await Process.run(
          'networksetup', ['-setwebproxystate', 'Wi-Fi', 'off']);
      await Process.run(
          'networksetup', ['-setsecurewebproxystate', 'Wi-Fi', 'off']);
      await Process.run(
          'networksetup', ['-setsocksfirewallproxystate', 'Wi-Fi', 'off']);
    } else if (Platform.isWindows) {
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f'
      ]);
    }
  }
}

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
      // Reassign history to trigger rebuild
      final history = ref.read(trafficHistoryProvider);
      history.add(t.up, t.down);
      ref.read(trafficHistoryProvider.notifier).state = history;
    });
    ref.onDispose(() => timer.cancel());
  } else {
    final sub = manager.stream.trafficStream().listen((t) {
      ref.read(trafficProvider.notifier).state =
          Traffic(up: t.up, down: t.down);
      final history = ref.read(trafficHistoryProvider);
      history.add(t.up, t.down);
      ref.read(trafficHistoryProvider.notifier).state = history;
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

// ------------------------------------------------------------------
// Proxy refresh trigger
// ------------------------------------------------------------------

final proxyRefreshProvider = Provider<void>((ref) {});

// ------------------------------------------------------------------
// Unlock test
// ------------------------------------------------------------------

final unlockResultsProvider =
    StateProvider<Map<String, UnlockResult>>((ref) => {});

final unlockTestingProvider = StateProvider<bool>((ref) => false);

final unlockTestActionsProvider =
    Provider<UnlockTestActions>((ref) => UnlockTestActions(ref));

class UnlockTestActions {
  final Ref ref;
  UnlockTestActions(this.ref);

  Future<void> runAll() async {
    if (ref.read(unlockTestingProvider)) return;
    ref.read(unlockTestingProvider.notifier).state = true;

    // Mark all as "testing"
    final initial = {
      for (final svc in UnlockTestService.services)
        svc.id: const UnlockResult(status: UnlockStatus.testing),
    };
    ref.read(unlockResultsProvider.notifier).state = Map.from(initial);

    try {
      final mixedPort = CoreManager.instance.mixedPort;
      final results =
          await UnlockTestService.instance.testAll(proxyPort: mixedPort);
      ref.read(unlockResultsProvider.notifier).state = results;
    } finally {
      ref.read(unlockTestingProvider.notifier).state = false;
    }
  }
}
