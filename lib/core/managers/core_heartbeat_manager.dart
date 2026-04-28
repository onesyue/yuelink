import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kernel/core_manager.dart';
import '../../core/kernel/recovery_manager.dart';
import '../../core/profile/profile_service.dart';
import '../../core/storage/settings_service.dart';
import '../../i18n/app_strings.dart';
import '../providers/core_provider.dart';
import '../../shared/app_notifier.dart';
import '../../shared/event_log.dart';
import 'system_proxy_manager.dart';

/// Periodic core heartbeat with reachability-aware throttling and ProxyGuard.
///
/// Was inlined in `coreHeartbeatProvider` (lib/providers/core_provider.dart)
/// before the manager split — extracted as a class so the timer + state
/// machine can be reasoned about (and unit-tested) in isolation.
///
/// Behaviour:
///   • Interval depends on background flag AND underlying transport
///     (see [_intervalFor]). Cellular cadence is 2× Wi-Fi to dodge the
///     radio-dwell cost that dominates phone battery on always-on VPNs.
///   • 5 consecutive failures → silent restart attempt; 5 more → reset
///     state via [resetCoreToStopped].
///   • Skips itself while [recoveryInProgressProvider] is true.
///   • ProxyGuard runs on a 30 s wall-clock cadence — independent of
///     heartbeat interval — so cellular/background heartbeat slowdown
///     does NOT delay tamper detection from rival proxy clients.
class CoreHeartbeatManager {
  CoreHeartbeatManager(this.ref);

  final Ref ref;

  Timer? _timer;
  int _failures = 0;
  // Wall-clock timestamp of the last ProxyGuard pass. Decoupling from the
  // tick counter lets ProxyGuard stay on its 30 s cadence even when the
  // heartbeat itself slows to 30/60/120 s on cellular or background.
  DateTime? _lastProxyCheckAt;
  // Consecutive "set(port) returned false" count in the ProxyGuard path.
  // Reset on any successful restore. Cleared on stop(). Used below to
  // tolerate v2rayN / other clients that momentarily overwrite the
  // system proxy (a single round-trip) before letting go — without
  // forcing a core reset on the very first missed write.
  int _proxyRestoreFailures = 0;
  // One-shot retry gate: the first time we hit the failure threshold we
  // try a silent restart before giving up. This survives things like cell
  // tower flap / brief Wi-Fi lapse / transient DNS failure — cases where a
  // single `stop + start` fixes the core faster than the user could even
  // notice. Reset on any successful heartbeat OR after a hard giveup.
  bool _retriedThisOutage = false;
  bool _restartInFlight = false;
  // Cooldown after a hard give-up: suppresses the next wave of recovery
  // attempts so we don't toast the user every 30 s when the underlying
  // problem (no network, helper down) hasn't gone away.
  DateTime? _lastGiveUpAt;

  // Visible for tests.
  static const int failureThreshold = 5;
  static const Duration giveUpCooldown = Duration(seconds: 60);
  static const Duration proxyGuardCadence = Duration(seconds: 30);

  /// Pick the heartbeat interval given current foreground/background and
  /// transport state. Cellular is the high-cost case (each radio wake
  /// drains 5–10× more battery than a Wi-Fi packet); doubling the
  /// cadence there is the single biggest VPN-app battery win on phones.
  /// Wi-Fi values are still tight enough to detect a dead core within
  /// ~1.5 min (5 × 15 s) so auto-recovery semantics stay snappy.
  ///
  /// Closed transport values: `'wifi'`, `'cellular'`, `'none'`. Anything
  /// else (or absence) collapses to the Wi-Fi profile — the cheap
  /// default keeps the heartbeat responsive on platforms that don't
  /// surface a transport signal (iOS / desktop never call
  /// `onTransportChanged`).
  @visibleForTesting
  static Duration intervalFor({
    required bool inBackground,
    required String transport,
  }) {
    final isCellular = transport == 'cellular';
    if (inBackground) {
      return Duration(seconds: isCellular ? 120 : 60);
    }
    return Duration(seconds: isCellular ? 30 : 15);
  }

  /// Start the heartbeat. Idempotent — repeated calls reset the timer
  /// (used when background or transport state flips and interval changes).
  void start({required bool inBackground, String transport = 'wifi'}) {
    _timer?.cancel();
    final interval = intervalFor(
      inBackground: inBackground,
      transport: transport,
    );
    _timer = Timer.periodic(interval, (_) => _tick(inBackground: inBackground));
  }

  /// Stop the heartbeat. Idempotent.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _failures = 0;
    _lastProxyCheckAt = null;
    _proxyRestoreFailures = 0;
    _retriedThisOutage = false;
    _restartInFlight = false;
    _lastGiveUpAt = null;
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
    // Cooldown after a give-up: don't immediately re-enter the recovery
    // dance every 30 s while the underlying problem (no network, helper
    // dead, hardware sleep) is unchanged.
    if (_lastGiveUpAt != null &&
        DateTime.now().difference(_lastGiveUpAt!) < giveUpCooldown) {
      return;
    }

    // Use [RecoveryManager.checkCoreHealth] so desktop TUN service mode
    // (mihomo runs in the privileged helper subprocess) is treated as
    // alive when the REST API responds — the in-app FFI flag stays
    // false in that mode and the previous inline check would loop the
    // user through endless false-positive auto-recovery restarts.
    final health = await RecoveryManager.checkCoreHealth();
    if (health.alive) {
      _failures = 0;
      _retriedThisOutage = false;
      await _maybeProxyGuard(inBackground: inBackground);
      return;
    }

    _failures++;
    debugPrint(
        '[Heartbeat] failure #$_failures — apiOk=${health.apiOk} '
        'reason=${health.apiReason}');
    // v1.0.22 P1-1: per-failure structured event so user-export
    // diagnostics can distinguish a true core hang from a one-off
    // network flap (cell-tower hand-off vs WiFi suspend vs mihomo
    // wedged). Closed reason set comes from MihomoApi.healthSnapshot.
    EventLog.write(
        '[Heartbeat] failure n=$_failures reason=${health.apiReason}');
    if (_failures < failureThreshold) return;

    if (!_retriedThisOutage) {
      _retriedThisOutage = true;
      _failures = 0; // give the restart a clean window to prove recovery
      await _silentRestart();
      return;
    }

    // Second round of failures after a restart attempt — give up.
    // v1.0.21 hotfix P2-7: surface this to the user. Before, silent
    // restart + silent give-up both ran invisibly; the user saw
    // "disconnected" appear and had no clue auto-recovery was tried
    // and failed. Audit issue #7.
    debugPrint('[Heartbeat] core dead after retry, cleaning up');
    EventLog.write('[Heartbeat] auto_recovery give_up');
    AppNotifier.error('自动恢复失败，连接已断开');
    resetCoreToStopped(ref);
    // delay-state wipe is handled by _delayResetSub in main.dart (listens
    // for coreStatusProvider → stopped transition).
    _failures = 0;
    _retriedThisOutage = false;
    _lastGiveUpAt = DateTime.now();
  }

  /// Last-chance silent restart before declaring the core dead. Matches CVR
  /// `restart_core` behaviour — avoids dropping the user's session for a
  /// one-off hiccup (e.g. cell tower flap, transient DNS failure).
  ///
  /// v1.0.21 hotfix P2-7: no longer silent at the UX level. Users were
  /// experiencing "disconnect then reconnect within seconds" with no
  /// explanation — the behaviour was intentional but invisible, making
  /// it look like random state flapping. We keep the recovery action
  /// itself automatic (it works more than half the time, and asking the
  /// user to re-tap connect for a cell-tower flap is worse than just
  /// fixing it) but make each transition observable: a start toast, a
  /// success toast, and structured event_log entries for diagnostic
  /// export. A final-failure toast fires from the caller's give-up
  /// branch, not here, so both "restart ok" and "restart ok=false"
  /// paths reach the heartbeat's own logic.
  Future<void> _silentRestart() async {
    _restartInFlight = true;
    try {
      // Read persisted value rather than watching `activeProfileIdProvider`
      // (modules/). Silent restart fires after 3 × 10 s of failed heartbeats
      // — any in-memory profile switch has long since been persisted.
      final activeId = await SettingsService.getActiveProfileId();
      if (activeId == null) {
        debugPrint('[Heartbeat] silent restart skipped — no active profile');
        EventLog.write('[Heartbeat] auto_recovery skipped reason=no_profile');
        return;
      }
      final config = await ProfileService.loadConfig(activeId);
      if (config == null) {
        debugPrint('[Heartbeat] silent restart skipped — config not found');
        EventLog.write('[Heartbeat] auto_recovery skipped reason=no_config');
        return;
      }
      debugPrint('[Heartbeat] attempting silent core restart');
      EventLog.write('[Heartbeat] auto_recovery start');
      AppNotifier.info('正在自动恢复连接...');
      final ok = await ref.read(coreActionsProvider).restart(config);
      debugPrint('[Heartbeat] silent restart ok=$ok');
      EventLog.write('[Heartbeat] auto_recovery done ok=$ok');
      if (ok) {
        AppNotifier.success('已自动恢复连接');
      }
      // ok==false intentionally NOT surfaced here — the next heartbeat
      // round will hit the "second 3 failures" branch above, which emits
      // the proper give-up toast. Emitting a failure toast here too
      // would double-fire on the same outage.
    } catch (e) {
      debugPrint('[Heartbeat] silent restart threw: $e');
      EventLog.write(
          '[Heartbeat] auto_recovery err=${e.toString().split("\n").first}');
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
  /// Cadence is now driven by [proxyGuardCadence] wall-clock rather
  /// than a tick counter — the heartbeat tick interval itself is now
  /// reachability-aware (15/30/60/120 s), and a tick-based cadence
  /// would have stretched ProxyGuard to 90 s+ on cellular. Tamper
  /// detection has to stay tight regardless of radio state.
  ///
  /// Tolerates up to 3 consecutive `set()` failures before declaring a
  /// sticky conflict. A transient overwrite by another client that
  /// lets go after a single write (v2rayN's common pattern) gets
  /// silently recovered on the next tick; only persistent stealing
  /// (another client re-writing continuously) trips the reset path.
  Future<void> _maybeProxyGuard({required bool inBackground}) async {
    if (inBackground) return;
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;

    final now = DateTime.now();
    if (_lastProxyCheckAt != null &&
        now.difference(_lastProxyCheckAt!) < proxyGuardCadence) {
      return;
    }
    _lastProxyCheckAt = now;

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
    // null == unknown: the OS doesn't expose a usable verification path
    // (Linux w/o gsettings). Skip tamper/restore and clear the failure
    // counter so historical false-positives can't bleed forward.
    if (proxyOk == null) {
      _proxyRestoreFailures = 0;
      return;
    }
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
