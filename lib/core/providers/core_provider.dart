import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../kernel/core_manager.dart';
import '../managers/core_heartbeat_manager.dart';
import '../managers/core_lifecycle_manager.dart';
import '../managers/system_proxy_manager.dart';
import '../../domain/models/traffic.dart';
import '../../domain/models/traffic_history.dart';
import '../../infrastructure/datasources/mihomo_api.dart';

// Re-export traffic stream providers and chart UI state
// (defined in modules/dashboard to avoid circular imports)
export '../../modules/dashboard/providers/traffic_providers.dart';

// ──────────────────────────────────────────────────────────────────────────
// App background state (battery optimization)
// ──────────────────────────────────────────────────────────────────────────

/// True when the app is in the background (paused/hidden/inactive).
/// Stream providers watch this to pause WebSocket connections and reduce
/// heartbeat frequency, significantly reducing battery drain on Android.
final appInBackgroundProvider = StateProvider<bool>((ref) => false);

// ──────────────────────────────────────────────────────────────────────────
// Core state
// ──────────────────────────────────────────────────────────────────────────

enum CoreStatus { stopped, starting, running, stopping }

final coreStatusProvider = StateProvider<CoreStatus>(
  (ref) => CoreStatus.stopped,
);

/// Last startup error message — shown on dashboard when core fails to start.
final coreStartupErrorProvider = StateProvider<String?>((ref) => null);

/// Whether the core is running in mock mode (no native library).
final isMockModeProvider = Provider<bool>((ref) {
  return CoreManager.instance.isMockMode;
});

/// The MihomoApi client for data operations.
final mihomoApiProvider = Provider<MihomoApi>((ref) {
  return CoreManager.instance.api;
});

// ──────────────────────────────────────────────────────────────────────────
// Settings-backed providers
// ──────────────────────────────────────────────────────────────────────────

/// Routing mode: "rule" | "global" | "direct"
final routingModeProvider = StateProvider<String>((ref) => 'rule');

/// Connection mode: "tun" | "systemProxy"
final connectionModeProvider = StateProvider<String>((ref) => 'systemProxy');

/// Desktop TUN stack: "mixed" | "system" | "gvisor"
final desktopTunStackProvider = StateProvider<String>((ref) => 'mixed');

/// Log level: "info" | "debug" | "warning" | "error" | "silent"
/// Default is `error` to match SettingsService.getLogLevel(). mihomo logs
/// every L4 connection at warn, so anything below `error` produces tens of
/// thousands of lines per session and buries real failures.
final logLevelProvider = StateProvider<String>((ref) => 'error');

/// Whether to auto-set system proxy on connect (desktop only)
final systemProxyOnConnectProvider = StateProvider<bool>((ref) => true);

/// Whether to auto-connect on startup
final autoConnectProvider = StateProvider<bool>((ref) => false);

/// Set to true when the user explicitly stops the VPN.
/// Prevents auto-connect from re-enabling on app resume.
/// Reset on next explicit start.
final userStoppedProvider = StateProvider<bool>((ref) => false);

/// True while Android background→foreground recovery is in progress.
/// Heartbeat and status listeners must check this before resetting state,
/// otherwise they race with the recovery logic in _onAppResumed().
final recoveryInProgressProvider = StateProvider<bool>((ref) => false);

// ──────────────────────────────────────────────────────────────────────────
// Traffic state (written by both heartbeat and stream activators)
// ──────────────────────────────────────────────────────────────────────────

final trafficProvider = StateProvider<Traffic>((ref) => const Traffic());

final trafficHistoryProvider = StateProvider<TrafficHistory>(
  (ref) => TrafficHistory(),
);

/// Monotonically increasing version counter for [trafficHistoryProvider].
/// Bumped on every sample add — ChartCard watches this instead of a full
/// TrafficHistory copy, saving ~3600 double copies per second.
final trafficHistoryVersionProvider = StateProvider<int>((ref) => 0);

// ──────────────────────────────────────────────────────────────────────────
// Memory usage state
// ──────────────────────────────────────────────────────────────────────────

final memoryUsageProvider = StateProvider<int>((ref) => 0);

// ──────────────────────────────────────────────────────────────────────────
// Core actions (thin facade over CoreLifecycleManager + SystemProxyManager)
// ──────────────────────────────────────────────────────────────────────────
//
// `CoreActions` was a 700-line god-class containing connect/disconnect logic,
// platform-specific system proxy setup, DNS management, verification caches,
// heartbeat coordination, and recovery glue. The work has been moved into
// three dedicated managers (lib/core/managers/) and this class is now a
// thin facade that the UI providers + tests can call without importing the
// managers directly.
//
// External call sites — `ref.read(coreActionsProvider).start(...)` etc. —
// keep working unchanged. New code may call the managers directly.

final coreActionsProvider = Provider<CoreActions>((ref) => CoreActions(ref));

class CoreActions {
  final Ref ref;
  CoreActions(this.ref);

  CoreLifecycleManager get _lifecycle => CoreLifecycleManager(ref);

  Future<bool> start(String configYaml) => _lifecycle.start(configYaml);
  Future<void> stop() => _lifecycle.stop();
  Future<void> toggle(String configYaml) => _lifecycle.toggle(configYaml);
  Future<bool> restart(String configYaml) => _lifecycle.restart(configYaml);
  Future<bool> hotSwitchConnectionMode(
    String newMode, {
    String? fallbackMode,
  }) => _lifecycle.hotSwitchConnectionMode(newMode, fallbackMode: fallbackMode);
  Future<bool> applySystemProxy() => _lifecycle.applySystemProxy();
  Future<void> clearSystemProxy() => SystemProxyManager.clear();

  // Static forwards retained for legacy callers (recovery_manager,
  // _YueLinkAppState exit handler). New code should call SystemProxyManager
  // directly.
  static Future<void> clearSystemProxyStatic() => SystemProxyManager.clear();
  static Future<bool?> verifySystemProxy(int mixedPort) =>
      SystemProxyManager.verify(mixedPort);
  static void invalidateVerifyCache() =>
      SystemProxyManager.invalidateVerifyCache();
  static void invalidateNetworkServicesCache() =>
      SystemProxyManager.invalidateNetworkServicesCache();
  static Future<void> setTunDns() => SystemProxyManager.setTunDns();
  static Future<void> restoreTunDns() => SystemProxyManager.restoreTunDns();
}

// ──────────────────────────────────────────────────────────────────────────
// Core heartbeat — provider wrapper around CoreHeartbeatManager
// ──────────────────────────────────────────────────────────────────────────
//
// Periodically pings the core API while running. Auto-detects crashes and
// resets state via [resetCoreToStopped]. The provider re-runs whenever
// [coreStatusProvider] or [appInBackgroundProvider] changes — start()
// is called on every re-run, which restarts the timer with the new
// interval (10 s foreground / 60 s background).

final coreHeartbeatProvider = Provider<void>((ref) {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return;

  final manager = CoreManager.instance;
  if (manager.isMockMode) return; // mock never crashes

  final inBackground = ref.watch(appInBackgroundProvider);
  final heartbeat = CoreHeartbeatManager(ref);
  heartbeat.start(inBackground: inBackground);
  ref.onDispose(heartbeat.stop);
});
