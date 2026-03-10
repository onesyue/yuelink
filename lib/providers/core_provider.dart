import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../ffi/core_controller.dart';
import '../models/traffic.dart';
import '../services/core_manager.dart';
import '../services/mihomo_api.dart';
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
/// All proxy/traffic/connection/config queries go through this.
final mihomoApiProvider = Provider<MihomoApi>((ref) {
  return CoreManager.instance.api;
});

// ------------------------------------------------------------------
// Core actions
// ------------------------------------------------------------------

final coreActionsProvider = Provider<CoreActions>((ref) => CoreActions(ref));

class CoreActions {
  final Ref ref;
  CoreActions(this.ref);

  Future<bool> start(String configYaml) async {
    ref.read(coreStatusProvider.notifier).state = CoreStatus.starting;

    // Small delay to show transition animation
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

    // Trigger initial proxy data fetch
    ref.read(proxyRefreshProvider);

    return true;
  }

  Future<void> stop() async {
    ref.read(coreStatusProvider.notifier).state = CoreStatus.stopping;
    await Future.delayed(const Duration(milliseconds: 300));

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
}

// ------------------------------------------------------------------
// Traffic polling (uses REST API in real mode, FFI mock in mock mode)
// ------------------------------------------------------------------

final trafficProvider = StateProvider<Traffic>((ref) => const Traffic());

final trafficPollingProvider = Provider<Timer?>((ref) {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return null;

  final manager = CoreManager.instance;

  final timer = Timer.periodic(const Duration(seconds: 1), (_) async {
    if (manager.isMockMode) {
      // Mock mode: use direct FFI mock
      final t = CoreController.instance.getTraffic();
      ref.read(trafficProvider.notifier).state =
          Traffic(up: t.up, down: t.down);
    } else {
      // Real mode: use REST API
      try {
        final t = await manager.api.getTraffic();
        ref.read(trafficProvider.notifier).state =
            Traffic(up: t.up, down: t.down);
      } catch (_) {
        // API temporarily unavailable, skip this tick
      }
    }
  });

  ref.onDispose(() => timer.cancel());
  return timer;
});

// ------------------------------------------------------------------
// Proxy refresh trigger (for post-start initial load)
// ------------------------------------------------------------------

final proxyRefreshProvider = Provider<void>((ref) {
  // This is a trigger provider — reading it refreshes proxy data
});
