import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_strings.dart';
import '../../modules/dashboard/providers/dashboard_providers.dart'
    show exitIpInfoProvider;
import '../../modules/dashboard/providers/traffic_providers.dart';
import '../../modules/connections/providers/connections_providers.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../modules/nodes/providers/nodes_providers.dart'
    show proxyGroupsProvider, delayResultsProvider;
import '../../shared/app_notifier.dart';
import '../../shared/event_log.dart';
import '../kernel/core_manager.dart';
import '../kernel/recovery_manager.dart';
import '../managers/system_proxy_manager.dart';
import '../platform/vpn_service.dart';
import '../providers/core_provider.dart';
import '../storage/settings_service.dart';

/// Coordinates "user came back to the app" semantics:
///
///   * VPN revocation listener — reacts to the OS taking the tunnel away
///     (Settings → VPN toggle off, another VPN app starting), and to the
///     underlying transport flipping Wi-Fi ↔ cellular.
///   * Resume health check — runs every time the app foregrounds, plus
///     once during cold start on Android (where the engine recreate
///     leaves Dart state at default but the Go core / VPN service may
///     still be alive).
///   * System-proxy tamper detection on resume — desktop-only side
///     channel: another proxy client (v2rayN, Clash Verge) may have
///     hijacked the system proxy while we were backgrounded; force-
///     verify and restore in one shot rather than waiting for the 30 s
///     heartbeat round.
///
/// Was inlined in `_YueLinkAppState` (lib/main.dart, ~250 lines across
/// `_setupVpnRevocationListener`, `_onAppResumed`, `_resumeProxyTamperCheck`,
/// and `_resumeInFlight`). Pulling them out keeps main.dart's lifecycle
/// code focused on widget concerns and groups the resume-time race
/// guards (recoveryInProgressProvider, userStoppedProvider, persisted
/// manualStopped flag, in-flight coalesce) in a single readable unit.
///
/// Lives under `lib/core/lifecycle/` rather than `lib/shared/` because
/// the resume path reaches deep into core/managers and core/kernel —
/// it's a core concern, not a UI helper.
class AppResumeController {
  AppResumeController({required this.ref});

  final WidgetRef ref;

  /// True while [run] is executing. Used by main.dart's
  /// `didChangeAppLifecycleState` to coalesce overlapping resume events
  /// (two background↔foreground transitions in the same ~1-2 s window
  /// would otherwise double-invalidate streams and race on recovery).
  bool get inFlight => _inFlight;
  bool _inFlight = false;

  /// Wire up the platform VPN-service callbacks. Call once from
  /// `initState` on Android / iOS. Idempotent — internally
  /// `VpnService.listenForRevocation` replaces any previous handler.
  void setupVpnRevocationListener() {
    VpnService.listenForRevocation(
      _onVpnRevoked,
      onTransportChanged: _onTransportChanged,
    );
  }

  void _onVpnRevoked() {
    // Skip if recovery is in progress — the recovery logic will handle
    // state correctly. Without this guard, onVpnRevoked races with
    // [run] on engine recreate and resets state prematurely.
    if (ref.read(recoveryInProgressProvider)) {
      debugPrint('[Resume] VPN revoked during recovery — ignoring');
      return;
    }
    debugPrint('[Resume] VPN revoked — resetting state');
    resetCoreToStopped(ref);
    // delay-state wipe happens via the coreStatusProvider listener in
    // main.dart (status → stopped clears delay results).
    AppNotifier.warning(S.current.disconnectedUnexpected);
  }

  Future<void> _onTransportChanged(String prev, String now) async {
    // Mirror the underlying transport into Riverpod so the heartbeat
    // can re-derive its cadence (Wi-Fi 15 s / cellular 30 s
    // foreground; 60 / 120 s background). Cheap state write — no
    // effect when value is unchanged.
    if (now == 'wifi' || now == 'cellular' || now == 'none') {
      ref.read(lastTransportProvider.notifier).state = now;
    }

    // Wi-Fi → cellular / cellular → Wi-Fi: stale TCP pool + polluted
    // fake-ip mappings kill perceived responsiveness for ~30 s after
    // the switch. Flush both. Skip the initial "none → wifi" transition
    // at cold start — there's nothing to flush yet.
    if (prev == 'none') return;
    if (CoreManager.instance.isMockMode) return;
    try {
      final api = CoreManager.instance.api;
      if (!await api.isAvailable()) return;
      debugPrint(
        '[Resume] transport $prev→$now — flushing fake-ip + '
        'closing connections',
      );
      // Fire both in parallel; either one failing isn't fatal.
      await Future.wait<void>([
        api.flushFakeIpCache().then((_) {}).catchError((_) {}),
        api.closeAllConnections().then((_) {}).catchError((_) {}),
      ]);
      // Invalidate cached delay results — proxies that were fast on
      // Wi-Fi may be slow on cellular and vice versa.
      ref.read(delayResultsProvider.notifier).state = {};
    } catch (e) {
      debugPrint('[Resume] transport-change flush threw: $e');
    }
  }

  /// Validate core state immediately on app resume. Avoids waiting up
  /// to 10 s for the heartbeat to detect a crashed core. If the core
  /// is alive, invalidates stream providers so WebSockets reconnect
  /// (the OS may have suspended sockets during a long background
  /// period).
  ///
  /// Coalesces overlapping calls via [inFlight] — the second concurrent
  /// invocation is dropped and the in-flight one finishes.
  Future<void> run() async {
    if (_inFlight) {
      debugPrint('[Resume] coalesced — handler already in flight');
      return;
    }
    _inFlight = true;
    try {
      await _runInner();
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _runInner() async {
    // 1. Refresh auth / user profile in background (catches token expiry)
    ref.read(authProvider.notifier).refreshUserInfo().ignore();

    final manager = CoreManager.instance;
    if (manager.isMockMode) return;

    final status = ref.read(coreStatusProvider);

    // 2. Recovery: Dart thinks stopped but Go core is actually still running.
    //    This happens on Android when the OS kills the Flutter engine in the
    //    background but the VPN service + Go core survive. On resume, the
    //    engine is recreated with default state (stopped), but the core is
    //    alive.
    //
    //    The recovery guard is set on the PROVIDER (not a local bool) so
    //    that both the heartbeat timer and the VPN revocation callback
    //    respect it. The guard stays up until auto-connect also completes —
    //    this prevents the status listener from firing "unexpected
    //    disconnect" during the brief stopped→running transition.
    if (status != CoreStatus.running) {
      // Respect the user's explicit stop. userStoppedProvider is set to
      // true by CoreLifecycleManager.stop() and only cleared on a fresh
      // start(). When it's true, the user tapped disconnect — state must
      // stay stopped until the next user-initiated connect.
      //
      // Bug this guards against: after user stop, the Go core / service
      // helper / PacketTunnel extension can still respond "alive" on the
      // mihomo API for a short window (shutdown sequence in flight, or
      // Service Mode helper's mihomo subprocess still winding down).
      // The old recovery path saw `health.alive && health.apiOk == true`,
      // bumped status → running and wiped userStoppedProvider, so the UI
      // showed "connected" while the TUN fd / system proxy were actually
      // gone — the user had a "connected" indicator and dead network.
      //
      // Engine-recreate on Android (the case this recovery path was
      // written for) is unaffected: Riverpod rebuilds ProviderScope from
      // defaults, so userStoppedProvider reverts to false and we go
      // through the normal health check.
      // v1.0.21 hotfix: also consult the persisted manual-stop flag.
      // The in-memory userStoppedProvider is wiped to its default (false)
      // whenever Riverpod's ProviderScope rebuilds — which happens on
      // every Android engine recreate (background-kill of the Flutter
      // engine while the VPN service + Go core continue running). Without
      // the persisted check, the recovery branch below would see the
      // still-alive mihomo API and pull the UI back to "running" even
      // though the user had explicitly disconnected.
      final persistedManualStopped = await SettingsService.getManualStopped();
      if (persistedManualStopped && !ref.read(userStoppedProvider)) {
        // Hydrate the in-memory provider from persistence so subsequent
        // listeners (heartbeat, VPN revocation callback) also respect it.
        ref.read(userStoppedProvider.notifier).state = true;
      }
      if (ref.read(userStoppedProvider) || persistedManualStopped) {
        debugPrint(
          '[Resume] resumed in user-stopped state — skipping health '
          'recovery (persisted=$persistedManualStopped, '
          'provider=${ref.read(userStoppedProvider)})',
        );
        return;
      }
      ref.read(recoveryInProgressProvider.notifier).state = true;
      try {
        final health = await RecoveryManager.checkCoreHealth();
        // v1.0.22 P0-1: TOCTOU re-check. Between the await above and the
        // state mutations below, the user may have tapped Stop — the
        // first guard at the top of this method only covers the pre-await
        // window. Without this re-check the recovery branch overwrites
        // `coreStatusProvider` to running and clears `userStoppedProvider`,
        // resurrecting the very bug v1.0.21 P0-1 was supposed to fix:
        // UI shows "connected" while TUN fd / system proxy are gone.
        //
        // Re-read both the in-memory provider AND the persisted flag —
        // either becoming true between the two checks means the user
        // stopped during the await, and we must not promote to running.
        final userStoppedNow = ref.read(userStoppedProvider);
        final persistedNow = await SettingsService.getManualStopped();
        if (userStoppedNow || persistedNow) {
          debugPrint(
            '[Resume] manual stop landed during health-check await — '
            'aborting recovery (provider=$userStoppedNow, '
            'persisted=$persistedNow)',
          );
          ref.read(recoveryInProgressProvider.notifier).state = false;
          return;
        }
        if (health.alive && health.apiOk) {
          debugPrint(
            '[Resume] core alive but Dart state was $status — recovering',
          );
          // Restore Dart state + ports to match reality
          await manager.markRunning();
          // Invalidate streams BEFORE setting status to running.
          // This ensures streams reconnect before heartbeat or listeners
          // check for data, preventing a brief "no data" state.
          ref.invalidate(trafficStreamProvider);
          ref.invalidate(memoryStreamProvider);
          ref.invalidate(connectionsStreamProvider);
          ref.invalidate(exitIpInfoProvider);
          // Now set state — this triggers the status listener and heartbeat
          ref.read(coreStatusProvider.notifier).state = CoreStatus.running;
          // Clear any stale startup error from previous session
          ref.read(coreStartupErrorProvider.notifier).state = null;
          // Also reset the user-stopped flag so the UI shows connected state
          ref.read(userStoppedProvider.notifier).state = false;
          ref.read(proxyGroupsProvider.notifier).refresh();
        }
        // Note: on Android the recovery guard stays up so the post-frame
        // `_maybeAutoConnect()` callback can clear it after the cold-start
        // engine-recreate path completes. Other platforms don't take that
        // path on resume, so the `finally` below drops the guard
        // unconditionally — without it, a normal-but-no-mutation resume
        // (e.g. health check returns alive=false on iOS/desktop, which
        // skips the recovery branch) would leave the guard stuck and
        // suppress every subsequent heartbeat tick.
      } catch (e) {
        debugPrint('[Resume] recovery check failed: $e');
        ref.read(recoveryInProgressProvider.notifier).state = false;
      } finally {
        if (!Platform.isAndroid) {
          ref.read(recoveryInProgressProvider.notifier).state = false;
        }
      }
      return;
    }

    // 3. Normal case: Dart says running — verify core is still alive
    try {
      final health = await RecoveryManager.checkCoreHealth();
      if (!health.alive || !health.apiOk) {
        debugPrint('[Resume] core dead after resume — resetting state');
        resetCoreToStopped(ref);
        // delay-state wipe happens via the coreStatusProvider listener.
      } else {
        // Core alive — refresh data but do NOT invalidate
        // trafficStreamProvider. Invalidating it creates a new
        // TrafficHistory(), wiping the chart. The WebSocket reconnection
        // logic (exponential backoff in MihomoStream) handles stale
        // connections automatically when data stops flowing.
        ref.invalidate(memoryStreamProvider);
        ref.invalidate(connectionsStreamProvider);
        // Refresh exit IP in case network changed during background
        ref.invalidate(exitIpInfoProvider);
        // Refresh proxy groups in case core reloaded config
        ref.read(proxyGroupsProvider.notifier).refresh();
        // v1.0.21 hotfix P0-2: system-proxy tamper detection on resume.
        // If the user flipped over to v2rayN / Clash Verge / any other
        // proxy tool while YueLink was backgrounded, the 60 s verify
        // cache would leave the heartbeat unable to notice for up to
        // that TTL — resulting in the "connected but no network" UX.
        // force:true bypasses the cache, and a tampered result
        // immediately triggers restore instead of waiting for the 30 s
        // heartbeat round.
        unawaited(_proxyTamperCheck());
      }
    } catch (e) {
      debugPrint('[Resume] resume check failed: $e');
    }
  }

  /// Best-effort force-verify + restore on resume. Runs only when the
  /// user has systemProxy mode selected and core is running.
  /// Fire-and-forget: caller doesn't await; any exception is swallowed
  /// and logged so the rest of the resume path is unaffected.
  Future<void> _proxyTamperCheck() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return;
    }
    if (ref.read(connectionModeProvider) != 'systemProxy') return;
    if (!ref.read(systemProxyOnConnectProvider)) return;
    try {
      final port = CoreManager.instance.mixedPort;
      final ok = await SystemProxyManager.verify(port, force: true);
      if (ok == false) {
        debugPrint(
          '[Resume] systemProxy tampered on resume '
          '(expected 127.0.0.1:$port) — restoring',
        );
        EventLog.write(
          '[Resume] systemProxy tamper detected on resume port=$port',
        );
        // v1.0.22 P1-4: retry on transient failure (1.5 s × 3) so a
        // settle race (DPAPI not yet warm / networksetup briefly racing
        // AV) doesn't drop the user into a 30 s wait for the next
        // heartbeat round to retry.
        final restored = await SystemProxyManager.setWithRetry(port);
        if (!restored) {
          AppNotifier.warning(S.current.errSystemProxyFailed);
        }
      }
    } catch (e) {
      debugPrint('[Resume] tamper check failed: $e');
    }
  }
}
