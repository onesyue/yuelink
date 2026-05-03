import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/traffic.dart';
import '../../domain/models/traffic_history.dart';
import '../../infrastructure/datasources/mihomo_api.dart';
import '../kernel/core_manager.dart';
import '../managers/core_heartbeat_manager.dart';
import '../managers/core_lifecycle_manager.dart';
import '../managers/system_proxy_manager.dart';
import '../tun/desktop_tun_state.dart';

// All 11 mutable providers in this file follow the same shape introduced in
// S3 batch3/4a: `NotifierProvider<XNotifier, T>` with a Notifier whose
// constructor takes the initial value (used by `provider.overrideWith(() =>
// XNotifier(saved))` from main.dart's bootstrap), `build()` returns it, and
// `set(value)` is the public write surface. Multi-writer providers
// (`coreStatusProvider`, `desktopTunHealthProvider`,
// `recoveryInProgressProvider`, `trafficHistory*`) keep this single
// `set` entry point — every lifecycle / recovery / heartbeat caller routes
// through it, so any future ordering invariant added here is enforced
// uniformly.

// ──────────────────────────────────────────────────────────────────────────
// App background state (battery optimization)
// ──────────────────────────────────────────────────────────────────────────

/// True when the app is in the background (paused/hidden/inactive).
/// Stream providers watch this to pause WebSocket connections and reduce
/// heartbeat frequency, significantly reducing battery drain on Android.
final appInBackgroundProvider =
    NotifierProvider<AppInBackgroundNotifier, bool>(
      AppInBackgroundNotifier.new,
    );

class AppInBackgroundNotifier extends Notifier<bool> {
  AppInBackgroundNotifier([this._initial = false]);
  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}

// ──────────────────────────────────────────────────────────────────────────
// Core state
// ──────────────────────────────────────────────────────────────────────────

enum CoreStatus { stopped, starting, running, degraded, stopping }

final coreStatusProvider =
    NotifierProvider<CoreStatusNotifier, CoreStatus>(CoreStatusNotifier.new);

class CoreStatusNotifier extends Notifier<CoreStatus> {
  CoreStatusNotifier([this._initial = CoreStatus.stopped]);
  final CoreStatus _initial;

  @override
  CoreStatus build() => _initial;

  void set(CoreStatus value) => state = value;
}

/// Last startup error message — shown on dashboard when core fails to start.
final coreStartupErrorProvider =
    NotifierProvider<CoreStartupErrorNotifier, String?>(
      CoreStartupErrorNotifier.new,
    );

class CoreStartupErrorNotifier extends Notifier<String?> {
  CoreStartupErrorNotifier([this._initial]);
  final String? _initial;

  @override
  String? build() => _initial;

  void set(String? value) => state = value;
}

/// Last desktop TUN health snapshot. Null outside desktop TUN mode or before
/// the first verification pass. This is deliberately separate from
/// [coreStatusProvider]: the core may still be alive while TUN route/DNS is
/// degraded, and the UI must not collapse that state into a fake "running".
final desktopTunHealthProvider =
    NotifierProvider<DesktopTunHealthNotifier, DesktopTunSnapshot?>(
      DesktopTunHealthNotifier.new,
    );

class DesktopTunHealthNotifier extends Notifier<DesktopTunSnapshot?> {
  DesktopTunHealthNotifier([this._initial]);
  final DesktopTunSnapshot? _initial;

  @override
  DesktopTunSnapshot? build() => _initial;

  void set(DesktopTunSnapshot? value) => state = value;
}

/// Whether the core is running in mock mode (no native library).
final isMockModeProvider = Provider<bool>((ref) {
  return CoreManager.instance.isMockMode;
});

/// The MihomoApi client for data operations.
final mihomoApiProvider = Provider<MihomoApi>((ref) {
  return CoreManager.instance.api;
});

/// Set to true when the user explicitly stops the VPN.
/// Prevents auto-connect from re-enabling on app resume.
/// Reset on next explicit start.
final userStoppedProvider =
    NotifierProvider<UserStoppedNotifier, bool>(UserStoppedNotifier.new);

class UserStoppedNotifier extends Notifier<bool> {
  UserStoppedNotifier([this._initial = false]);
  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}

/// UI-facing status: collapses to [CoreStatus.stopped] whenever the user
/// has explicitly stopped, regardless of what [coreStatusProvider] says.
///
/// Belt-and-suspenders against the resume race: if the user taps Stop
/// while `_onAppResumed` is mid-await on `checkCoreHealth()`, the core
/// can briefly answer "alive" before fully shutting down (mihomo helper
/// in flight, PacketTunnel extension still tearing down). Without this
/// derived layer the UI would show "connected" for the last frame
/// before lifecycle drives `coreStatusProvider` back to stopped — long
/// enough for the user to see the inconsistency in screenshot reports.
///
/// Internal state machines (heartbeat, lifecycle, tray, recovery) MUST
/// keep reading [coreStatusProvider] — they need ground truth, not the
/// user-intent overlay.
final displayCoreStatusProvider = Provider<CoreStatus>((ref) {
  final status = ref.watch(coreStatusProvider);
  final userStopped = ref.watch(userStoppedProvider);
  if (userStopped) return CoreStatus.stopped;
  return status;
});

/// True while Android background→foreground recovery is in progress.
/// Heartbeat and status listeners must check this before resetting state,
/// otherwise they race with the recovery logic in _onAppResumed().
final recoveryInProgressProvider =
    NotifierProvider<RecoveryInProgressNotifier, bool>(
      RecoveryInProgressNotifier.new,
    );

class RecoveryInProgressNotifier extends Notifier<bool> {
  RecoveryInProgressNotifier([this._initial = false]);
  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}

// ──────────────────────────────────────────────────────────────────────────
// Traffic state (written by both heartbeat and stream activators)
// ──────────────────────────────────────────────────────────────────────────

final trafficProvider =
    NotifierProvider<TrafficNotifier, Traffic>(TrafficNotifier.new);

class TrafficNotifier extends Notifier<Traffic> {
  TrafficNotifier([this._initial = const Traffic()]);
  final Traffic _initial;

  @override
  Traffic build() => _initial;

  void set(Traffic value) => state = value;
}

final trafficHistoryProvider =
    NotifierProvider<TrafficHistoryNotifier, TrafficHistory>(
      TrafficHistoryNotifier.new,
    );

class TrafficHistoryNotifier extends Notifier<TrafficHistory> {
  TrafficHistoryNotifier([TrafficHistory? initial])
    : _initial = initial ?? TrafficHistory();
  final TrafficHistory _initial;

  @override
  TrafficHistory build() => _initial;

  void set(TrafficHistory value) => state = value;
}

/// Monotonically increasing version counter for [trafficHistoryProvider].
/// Bumped on every sample add — ChartCard watches this instead of a full
/// TrafficHistory copy, saving ~3600 double copies per second.
final trafficHistoryVersionProvider =
    NotifierProvider<TrafficHistoryVersionNotifier, int>(
      TrafficHistoryVersionNotifier.new,
    );

class TrafficHistoryVersionNotifier extends Notifier<int> {
  TrafficHistoryVersionNotifier([this._initial = 0]);
  final int _initial;

  @override
  int build() => _initial;

  void set(int value) => state = value;
}

// ──────────────────────────────────────────────────────────────────────────
// Memory usage state
// ──────────────────────────────────────────────────────────────────────────

final memoryUsageProvider =
    NotifierProvider<MemoryUsageNotifier, int>(MemoryUsageNotifier.new);

class MemoryUsageNotifier extends Notifier<int> {
  MemoryUsageNotifier([this._initial = 0]);
  final int _initial;

  @override
  int build() => _initial;

  void set(int value) => state = value;
}

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

// Most recently observed underlying transport — drives reachability-aware
// heartbeat cadence. Updated from `VpnService.listenForRevocation`'s
// `onTransportChanged` callback (Android only — iOS / desktop never flip
// it). Closed value set: `'wifi'`, `'cellular'`, `'none'`. Default
// `'wifi'` is the radio-cheap profile, so platforms that never emit a
// transport signal stay on the shorter heartbeat interval rather than
// silently degrading to the cellular cadence.
final lastTransportProvider =
    NotifierProvider<LastTransportNotifier, String>(LastTransportNotifier.new);

class LastTransportNotifier extends Notifier<String> {
  LastTransportNotifier([this._initial = 'wifi']);
  final String _initial;

  @override
  String build() => _initial;

  void set(String value) => state = value;
}

// ──────────────────────────────────────────────────────────────────────────
// Core heartbeat — provider wrapper around CoreHeartbeatManager
// ──────────────────────────────────────────────────────────────────────────
//
// Periodically pings the core API while running. Auto-detects crashes and
// resets state via [resetCoreToStopped]. The provider re-runs whenever
// [coreStatusProvider], [appInBackgroundProvider], or
// [lastTransportProvider] change — start() is called on every re-run,
// which restarts the timer with the new interval (15 s Wi-Fi foreground
// / 30 s cellular foreground / 60 s Wi-Fi background / 120 s cellular
// background). See `CoreHeartbeatManager._intervalFor` for rationale.

final coreHeartbeatProvider = Provider<void>((ref) {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return;

  final manager = CoreManager.instance;
  if (manager.isMockMode) return; // mock never crashes

  final inBackground = ref.watch(appInBackgroundProvider);
  final transport = ref.watch(lastTransportProvider);
  final heartbeat = CoreHeartbeatManager(ref);
  heartbeat.start(inBackground: inBackground, transport: transport);
  ref.onDispose(heartbeat.stop);
});
