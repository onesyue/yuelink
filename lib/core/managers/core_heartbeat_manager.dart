import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ffi/core_controller.dart';
import '../../core/kernel/core_manager.dart';
import '../../core/kernel/recovery_manager.dart';
import '../../core/profile/profile_service.dart';
import '../../core/storage/settings_service.dart';
import '../../i18n/app_strings.dart';
import '../providers/core_provider.dart';
import '../../shared/app_notifier.dart';
import 'system_proxy_manager.dart';

/// Periodic core heartbeat with battery-aware throttling and ProxyGuard.
///
/// Was inlined in `coreHeartbeatProvider` (lib/providers/core_provider.dart)
/// before the manager split — extracted as a class so the timer + state
/// machine can be reasoned about (and unit-tested) in isolation.
///
/// Behaviour preserved exactly from the inlined version:
///   • 10 s interval foreground, 60 s background
///   • 3 consecutive failures → reset state via [resetCoreToStopped]
///   • Skips itself while [recoveryInProgressProvider] is true
///   • Every ~5 min in foreground (30 ticks × 10 s), runs ProxyGuard:
///     re-verifies the system proxy and restores it if another client
///     took over. After 1 failed restore, the core is force-stopped to
///     surface the conflict to the user.
class CoreHeartbeatManager {
  CoreHeartbeatManager(this.ref);

  final Ref ref;

  Timer? _timer;
  int _failures = 0;
  int _proxyCheckTick = 0;
  // Consecutive "set(port) returned false" count in the ProxyGuard path.
  // Reset on any successful restore. Cleared on stop(). Used below to
  // tolerate v2rayN / other clients that momentarily overwrite the
  // system proxy (a single round-trip) before letting go — without
  // forcing a core reset on the very first missed write.
  int _proxyRestoreFailures = 0;
  // One-shot retry gate: the first time we hit the "3 failures" threshold we
  // try a silent restart before giving up. This survives things like cell
  // tower flap / brief Wi-Fi lapse / transient DNS failure — cases where a
  // single `stop + start` fixes the core faster than the user could even
  // notice. Reset on any successful heartbeat OR after a hard giveup.
  bool _retriedThisOutage = false;
  bool _restartInFlight = false;

  /// Start the heartbeat. Idempotent — repeated calls reset the timer
  /// (used when [appInBackgroundProvider] flips and the interval changes).
  void start({required bool inBackground}) {
    _timer?.cancel();
    final interval = Duration(seconds: inBackground ? 60 : 10);
    _timer = Timer.periodic(interval, (_) => _tick(inBackground: inBackground));
  }

  /// Stop the heartbeat. Idempotent.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _failures = 0;
    _proxyCheckTick = 0;
    _proxyRestoreFailures = 0;
    _retriedThisOutage = false;
    _restartInFlight = false;
  }

  Future<void> _tick({required bool inBackground}) async {
    // Skip while recovery is in progress — the recovery logic handles
    // state transitions. Without this guard, the heartbeat can accumulate
    // failures during recovery and reset state prematurely.
    if (ref.read(recoveryInProgressProvider)) {
      debugPrint('[Heartbeat] skipped — recovery in progress');
      return;
    }
    // Don't pile ticks on top of an in-flight silent restart. The restart
    // itself takes 500-2000 ms and we'd rather wait one interval than race.
    if (_restartInFlight) {
      debugPrint('[Heartbeat] skipped — silent restart in flight');
      return;
    }

    final manager = CoreManager.instance;

    final ffiRunning =
        Platform.isIOS ? false : CoreController.instance.isRunning;
    final apiOk = await manager.api.isAvailable();

    if (RecoveryManager.isAliveForPlatform(
      apiOk: apiOk,
      ffiRunning: ffiRunning,
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
    )) {
      _failures = 0;
      _retriedThisOutage = false;
      await _maybeProxyGuard(inBackground: inBackground);
      return;
    }

    _failures++;
    debugPrint('[Heartbeat] failure #$_failures — '
        'ffi.isRunning=$ffiRunning, api=$apiOk');
    if (_failures < 3) return;

    if (!_retriedThisOutage) {
      _retriedThisOutage = true;
      _failures = 0; // give the restart a clean window to prove recovery
      await _silentRestart();
      return;
    }

    // Second round of 3 failures after a restart attempt — give up.
    debugPrint('[Heartbeat] core dead after retry, cleaning up');
    resetCoreToStopped(ref);
    // delay-state wipe is handled by _delayResetSub in main.dart (listens
    // for coreStatusProvider → stopped transition).
    _failures = 0;
    _retriedThisOutage = false;
  }

  /// Last-chance silent restart before declaring the core dead. Matches CVR
  /// `restart_core` behaviour — avoids dropping the user's session for a
  /// one-off hiccup (e.g. cell tower flap, transient DNS failure).
  Future<void> _silentRestart() async {
    _restartInFlight = true;
    try {
      // Read persisted value rather than watching `activeProfileIdProvider`
      // (modules/). Silent restart fires after 3 × 10 s of failed heartbeats
      // — any in-memory profile switch has long since been persisted.
      final activeId = await SettingsService.getActiveProfileId();
      if (activeId == null) {
        debugPrint('[Heartbeat] silent restart skipped — no active profile');
        return;
      }
      final config = await ProfileService.loadConfig(activeId);
      if (config == null) {
        debugPrint('[Heartbeat] silent restart skipped — config not found');
        return;
      }
      debugPrint('[Heartbeat] attempting silent core restart');
      final ok = await ref.read(coreActionsProvider).restart(config);
      debugPrint('[Heartbeat] silent restart ok=$ok');
    } catch (e) {
      debugPrint('[Heartbeat] silent restart threw: $e');
    } finally {
      _restartInFlight = false;
    }
  }

  /// Re-verify the system proxy every ~30 seconds (foreground only) and
  /// re-assert it if another proxy client (v2rayN, Clash Verge, etc.) has
  /// overwritten it. Previously this ran only every 5 minutes — opening
  /// v2rayN even without connecting it would overwrite the registry /
  /// `networksetup` / gsettings state, and YueLink's users would lose
  /// network for up to 5 minutes before noticing. A single write-failure
  /// would also immediately `resetCoreToStopped`, forcing a manual
  /// reconnect.
  ///
  /// Changes:
  /// - check cadence 5 min → 30 s (3 × 10 s foreground heartbeat ticks).
  /// - tolerate up to 3 consecutive `set()` failures before declaring
  ///   a sticky conflict. A transient overwrite by another client that
  ///   lets go after a single write (v2rayN's common pattern) gets
  ///   silently recovered on the next tick; only persistent stealing
  ///   (another client re-writing continuously) trips the reset path.
  Future<void> _maybeProxyGuard({required bool inBackground}) async {
    if (inBackground) return;
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;

    _proxyCheckTick++;
    if (_proxyCheckTick < 3) return; // 3 × 10s = ~30s cadence
    _proxyCheckTick = 0;

    final connMode = ref.read(connectionModeProvider);
    if (connMode != 'systemProxy') {
      _proxyRestoreFailures = 0;
      return;
    }
    if (!ref.read(systemProxyOnConnectProvider)) {
      _proxyRestoreFailures = 0;
      return;
    }

    final port = CoreManager.instance.mixedPort;
    final proxyOk = await SystemProxyManager.verify(port);
    if (proxyOk) {
      _proxyRestoreFailures = 0;
      return;
    }

    debugPrint('[ProxyGuard] system proxy tampered — attempting restore');
    final restored = await SystemProxyManager.set(port);
    if (restored) {
      debugPrint('[ProxyGuard] system proxy restored successfully');
      _proxyRestoreFailures = 0;
      return;
    }

    _proxyRestoreFailures++;
    debugPrint(
      '[ProxyGuard] restore attempt $_proxyRestoreFailures/3 failed',
    );
    if (_proxyRestoreFailures < 3) {
      // Another client is briefly holding the system proxy setting (typical
      // v2rayN startup pattern) — give it another 30s before giving up.
      return;
    }

    debugPrint('[ProxyGuard] restore failed 3× — another client took over');
    AppNotifier.warning(S.current.msgSystemProxyConflict);
    resetCoreToStopped(ref, clearDesktopProxy: false);
    // delay-state wipe is handled by _delayResetSub in main.dart (listens
    // for coreStatusProvider → stopped transition).
    _failures = 0;
    _proxyRestoreFailures = 0;
  }
}
