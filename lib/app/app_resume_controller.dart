import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../i18n/app_strings.dart';
import '../modules/dashboard/providers/dashboard_providers.dart'
    show exitIpInfoProvider;
import '../modules/dashboard/providers/traffic_providers.dart';
import '../modules/connections/providers/connections_providers.dart';
import '../modules/yue_auth/providers/yue_auth_providers.dart';
import '../modules/nodes/providers/nodes_providers.dart'
    show proxyGroupsProvider, delayResultsProvider;
import '../shared/app_notifier.dart';
import '../shared/event_log.dart';
import '../core/kernel/core_manager.dart';
import '../core/kernel/recovery_manager.dart';
import '../core/managers/system_proxy_manager.dart';
import '../core/platform/vpn_service.dart';
import '../core/profile/profile_service.dart';
import '../core/providers/core_provider.dart';
import '../core/storage/settings_service.dart';
import '../core/tun/desktop_tun_diagnostics.dart';
import '../core/tun/desktop_tun_repair_service.dart';
import '../core/tun/desktop_tun_telemetry.dart';

/// One-shot event published by [AppResumeController] when iOS reports a
/// tunnel that connected then dropped within 10 s — the signature of an
/// untrusted IPA (TrollStore / unsigned re-sign). Connection page listens
/// and surfaces an explicit error dialog with iOS install guide.
class IosEntitlementSuspectEvent {
  final int elapsedMs;
  final DateTime at;
  const IosEntitlementSuspectEvent({required this.elapsedMs, required this.at});
}

/// Latest entitlement-suspect event. `null` until first occurrence.
final iosEntitlementSuspectProvider =
    StateProvider<IosEntitlementSuspectEvent?>((_) => null);

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
  int _transportRecoveryGeneration = 0;
  bool _transportRestartInFlight = false;
  Timer? _networkPollTimer;
  String? _lastNetworkSignature;
  final DesktopTunRepairService _desktopTunRepair = DesktopTunRepairService();

  /// Wire up the platform VPN-service callbacks. Call once from
  /// `initState` on Android / iOS / macOS. Idempotent — internally
  /// `VpnService.listenForRevocation` replaces any previous handler.
  void setupVpnRevocationListener() {
    VpnService.listenForRevocation(
      _onVpnRevoked,
      onTransportChanged: _onTransportChanged,
    );
  }

  /// Desktop fallback path. macOS also has NWPathMonitor, but polling catches
  /// same-medium changes that the transport label cannot express, such as
  /// Wi-Fi A → Wi-Fi B or Ethernet DHCP address changes.
  void startNetworkChangePolling() {
    if (_networkPollTimer != null) return;
    unawaited(_pollNetworkSignature(seedOnly: true));
    _networkPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_pollNetworkSignature()),
    );
  }

  void dispose() {
    _networkPollTimer?.cancel();
    _networkPollTimer = null;
  }

  void _onVpnRevoked(VpnRevocationReason reason) {
    // Skip if recovery is in progress — the recovery logic will handle
    // state correctly. Without this guard, onVpnRevoked races with
    // [run] on engine recreate and resets state prematurely.
    if (ref.read(recoveryInProgressProvider)) {
      debugPrint('[Resume] VPN revoked during recovery — ignoring');
      return;
    }
    debugPrint(
      '[Resume] VPN revoked (kind=${reason.kind}, elapsed=${reason.elapsedMs}ms) — resetting state',
    );
    resetCoreToStopped(ref);
    // delay-state wipe happens via the coreStatusProvider listener in
    // main.dart (status → stopped clears delay results).

    if (reason.kind == VpnRevocationKind.entitlementSuspect) {
      // Surface a strong signal: tunnel reached .connected then dropped
      // within 10 s — almost always means the IPA isn't trusted enough by
      // the system to actually route packets (TrollStore-installed,
      // unsigned re-pack, etc.). Mark a flag the connection page checks
      // next frame to show the iOS install guide dialog.
      ref
          .read(iosEntitlementSuspectProvider.notifier)
          .state = IosEntitlementSuspectEvent(
        elapsedMs: reason.elapsedMs ?? 0,
        at: DateTime.now(),
      );
    } else {
      AppNotifier.warning(S.current.disconnectedUnexpected);
    }
  }

  Future<void> _onTransportChanged(
    String prev,
    String now, {
    bool force = false,
  }) async {
    // Mirror the underlying transport into Riverpod so the heartbeat
    // can re-derive its cadence (Wi-Fi 15 s / cellular 30 s
    // foreground; 60 / 120 s background). Cheap state write — no
    // effect when value is unchanged.
    if (now == 'wifi' || now == 'cellular' || now == 'none') {
      ref.read(lastTransportProvider.notifier).state = now;
    }

    // Wi-Fi → cellular / cellular → Wi-Fi: stale TCP pool + polluted
    // fake-ip mappings kill perceived responsiveness after the switch.
    // Flush them repeatedly because Android emits the callback before
    // DNS/route state has fully settled on some ROMs. The cold-start
    // "none → wifi" transition is harmless because recovery exits while
    // the core is still starting, but a real no-network → network return
    // while connected gets the same cleanup.
    if (!_isTransportHandoff(prev, now, force: force)) return;
    if (CoreManager.instance.isMockMode) return;

    final generation = ++_transportRecoveryGeneration;
    await _recoverTransportHandoff(prev, now, generation);
  }

  Future<void> _pollNetworkSignature({bool seedOnly = false}) async {
    if (_networkPollTimer == null && !seedOnly) return;
    if (CoreManager.instance.isMockMode) return;
    if (ref.read(appInBackgroundProvider)) return;

    final signature = await _networkSignature().timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    if (signature == null) return;

    if (seedOnly ||
        ref.read(coreStatusProvider) != CoreStatus.running ||
        ref.read(userStoppedProvider)) {
      _lastNetworkSignature = signature;
      return;
    }

    final previous = _lastNetworkSignature;
    if (previous == null) {
      _lastNetworkSignature = signature;
      return;
    }
    if (previous == signature) return;

    _lastNetworkSignature = signature;
    final prevTransport = _transportFromNetworkSignature(previous);
    final nowTransport = _transportFromNetworkSignature(signature);
    debugPrint(
      '[Resume] network signature changed $prevTransport→$nowTransport',
    );
    await _onTransportChanged(prevTransport, nowTransport, force: true);
  }

  Future<String?> _networkSignature() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.any,
      );
      final parts = <String>[];
      for (final iface in interfaces) {
        if (!_isPhysicalInterfaceName(iface.name)) continue;
        final addresses =
            iface.addresses
                .where((a) => !a.isLoopback && !a.isLinkLocal)
                .map((a) => a.address)
                .where((a) => a.isNotEmpty)
                .toList()
              ..sort();
        if (addresses.isEmpty) continue;
        parts.add('${iface.name.toLowerCase()}=${addresses.join(",")}');
      }
      parts.sort();
      return parts.isEmpty ? 'none' : parts.join('|');
    } catch (e) {
      debugPrint('[Resume] network signature probe failed: $e');
      return null;
    }
  }

  bool _isPhysicalInterfaceName(String name) {
    final lower = name.toLowerCase();
    if (lower.isEmpty) return false;
    if (lower == 'lo' || lower.startsWith('lo:')) return false;
    const virtualPrefixes = [
      'tun',
      'tap',
      'utun',
      'wg',
      'awdl',
      'llw',
      'docker',
      'veth',
      'br-',
      'vmnet',
      'vboxnet',
      'zt',
    ];
    for (final prefix in virtualPrefixes) {
      if (lower.startsWith(prefix)) return false;
    }
    const virtualContains = [
      'loopback',
      'virtual',
      'vethernet',
      'hyper-v',
      'docker',
      'wsl',
      'tailscale',
      'zerotier',
      'clash',
      'mihomo',
      'yuelink',
    ];
    for (final token in virtualContains) {
      if (lower.contains(token)) return false;
    }
    return true;
  }

  String _transportFromNetworkSignature(String signature) {
    if (signature == 'none' || signature.isEmpty) return 'none';
    final lower = signature.toLowerCase();
    if (lower.contains('wi-fi') ||
        lower.contains('wifi') ||
        lower.contains('wlan') ||
        lower.contains('wlp')) {
      return 'wifi';
    }
    if (lower.contains('cell') ||
        lower.contains('mobile') ||
        lower.contains('wwan') ||
        lower.contains('wwp') ||
        lower.contains('rmnet')) {
      return 'cellular';
    }
    if (lower.contains('ethernet') ||
        lower.contains('eth') ||
        lower.contains('enp') ||
        lower.contains('eno')) {
      return 'ethernet';
    }
    return 'other';
  }

  bool _isTransportHandoff(String prev, String now, {bool force = false}) {
    if (!_isPhysicalTransport(now)) return false;
    if (force) return true;
    if (prev == now) return _isPhysicalTransport(prev);
    return prev == 'none' || _isPhysicalTransport(prev);
  }

  bool _isPhysicalTransport(String transport) {
    return transport == 'wifi' ||
        transport == 'cellular' ||
        transport == 'ethernet' ||
        transport == 'other';
  }

  Future<void> _recoverTransportHandoff(
    String prev,
    String now,
    int generation,
  ) async {
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 900),
      Duration(milliseconds: 2500),
    ];

    debugPrint('[Resume] transport $prev→$now — recovery scheduled');
    EventLog.write('[Transport] handoff from=$prev to=$now');
    _invalidatePlatformNetworkCaches();

    var lastReason = 'not_attempted';
    var successAttempt = 0;
    for (var attempt = 0; attempt < delays.length; attempt++) {
      final delay = delays[attempt];
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (generation != _transportRecoveryGeneration) return;
      if (ref.read(coreStatusProvider) != CoreStatus.running) return;
      if (ref.read(userStoppedProvider)) return;

      final result = await _flushTransportState(attempt + 1, prev, now);
      if (generation != _transportRecoveryGeneration) return;
      if (result.ok) {
        successAttempt = attempt + 1;
      } else {
        lastReason = result.reason;
      }
    }

    if (successAttempt > 0) {
      EventLog.write(
        '[Transport] recovery ok from=$prev to=$now '
        'last_attempt=$successAttempt',
      );
      unawaited(_repairPlatformNetworkSettingsAfterHandoff(prev, now));
      return;
    }

    if (generation != _transportRecoveryGeneration) return;
    await _restartAfterTransportHandoff(prev, now, lastReason, generation);
  }

  void _invalidatePlatformNetworkCaches() {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    SystemProxyManager.invalidateNetworkServicesCache();
    SystemProxyManager.invalidateVerifyCache();
  }

  Future<void> _repairPlatformNetworkSettingsAfterHandoff(
    String prev,
    String now,
  ) async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    try {
      final mode = ref.read(connectionModeProvider);
      if (Platform.isMacOS && mode == 'tun') {
        EventLog.write('[Transport] reapply_macos_tun_dns from=$prev to=$now');
        await SystemProxyManager.setTunDns();
        return;
      }
      if (mode == 'systemProxy') {
        await _proxyTamperCheck();
      }
    } catch (e) {
      debugPrint('[Resume] platform network repair failed: $e');
      EventLog.write(
        '[Transport] platform_repair err=${e.toString().split("\n").first}',
      );
    }
  }

  Future<({bool ok, String reason})> _flushTransportState(
    int attempt,
    String prev,
    String now,
  ) async {
    try {
      final api = CoreManager.instance.api;
      final health = await api.healthSnapshot();
      if (!health.ok) {
        debugPrint(
          '[Resume] transport $prev→$now attempt=$attempt api=${health.reason}',
        );
        return (ok: false, reason: health.reason);
      }

      debugPrint(
        '[Resume] transport $prev→$now attempt=$attempt — closing '
        'connections + flushing fake-ip',
      );

      var closeOk = false;
      var fakeIpOk = false;
      Object? lastError;
      try {
        closeOk = await api.closeAllConnections().timeout(
          const Duration(seconds: 3),
        );
      } catch (e) {
        lastError = e;
      }
      try {
        fakeIpOk = await api.flushFakeIpCache().timeout(
          const Duration(seconds: 3),
        );
      } catch (e) {
        lastError = e;
      }

      if (!closeOk && !fakeIpOk) {
        final reason = lastError == null
            ? 'cleanup_false'
            : lastError.toString().split('\n').first;
        debugPrint('[Resume] transport $prev→$now cleanup failed: $reason');
        return (ok: false, reason: reason);
      }

      // Invalidate cached state tied to the old network. Keep the traffic
      // chart intact; its WebSocket reconnect logic handles stale sockets.
      ref.read(delayResultsProvider.notifier).state = {};
      ref.invalidate(memoryStreamProvider);
      ref.invalidate(connectionsStreamProvider);
      ref.invalidate(exitIpInfoProvider);
      ref.read(proxyGroupsProvider.notifier).refresh();
      return (ok: true, reason: 'ok');
    } catch (e) {
      final reason = e.toString().split('\n').first;
      debugPrint('[Resume] transport-change cleanup threw: $reason');
      return (ok: false, reason: reason);
    }
  }

  Future<void> _restartAfterTransportHandoff(
    String prev,
    String now,
    String reason,
    int generation,
  ) async {
    if (_transportRestartInFlight) return;
    if (ref.read(coreStatusProvider) != CoreStatus.running) return;
    if (ref.read(userStoppedProvider)) return;

    _transportRestartInFlight = true;
    try {
      final activeId = await SettingsService.getActiveProfileId();
      if (activeId == null) {
        EventLog.write(
          '[Transport] restart skipped from=$prev to=$now reason=no_profile',
        );
        return;
      }
      final config = await ProfileService.loadConfig(activeId);
      if (config == null) {
        EventLog.write(
          '[Transport] restart skipped from=$prev to=$now reason=no_config',
        );
        return;
      }
      if (generation != _transportRecoveryGeneration) return;
      if (ref.read(coreStatusProvider) != CoreStatus.running) return;
      if (ref.read(userStoppedProvider)) return;

      debugPrint(
        '[Resume] transport $prev→$now cleanup failed ($reason) — '
        'silent restart',
      );
      EventLog.write(
        '[Transport] restart start from=$prev to=$now reason=$reason',
      );
      AppNotifier.info('网络切换后正在自动恢复连接...');
      final ok = await ref.read(coreActionsProvider).restart(config);
      EventLog.write('[Transport] restart done from=$prev to=$now ok=$ok');
      if (ok) {
        AppNotifier.success('已自动恢复连接');
      }
    } catch (e) {
      final msg = e.toString().split('\n').first;
      debugPrint('[Resume] transport restart threw: $msg');
      EventLog.write('[Transport] restart err=$msg');
    } finally {
      _transportRestartInFlight = false;
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

    // Defer entirely while start() is mid-flight. The in-memory state
    // (userStoppedProvider, coreStatusProvider) is being driven by the
    // active CoreLifecycleManager.start() call and is authoritative —
    // the persistence-based hydrate path below would read the still-
    // stale `manualStopped=true` (from before start() flushed false)
    // and stomp the just-cleared userStoppedProvider. Symptom: macOS
    // 2026-04-28 — startup SUCCESS, mihomo + system proxy both up,
    // but UI rendered '未连接' because displayCoreStatusProvider
    // returned stopped on the resurrected userStopped flag.
    if (manager.isStartInFlight) {
      debugPrint('[Resume] start() in flight — deferring resume handler');
      return;
    }

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
    if (status != CoreStatus.running && status != CoreStatus.degraded) {
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

    // 3. Normal case: Dart says running/degraded — verify core is still alive
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
        // Windows/Linux fallback: if the app was suspended while the
        // physical network changed, the polling timer resumes after this
        // lifecycle tick. Run one immediate probe so stale connections
        // are cleaned without waiting for the next 5 s poll.
        unawaited(_pollNetworkSignature());
        // v1.0.21 hotfix P0-2: system-proxy tamper detection on resume.
        // If the user flipped over to v2rayN / Clash Verge / any other
        // proxy tool while YueLink was backgrounded, the 60 s verify
        // cache would leave the heartbeat unable to notice for up to
        // that TTL — resulting in the "connected but no network" UX.
        // force:true bypasses the cache, and a tampered result
        // immediately triggers restore instead of waiting for the 30 s
        // heartbeat round.
        unawaited(_proxyTamperCheck());
        unawaited(_desktopTunResumeCheck());
      }
    } catch (e) {
      debugPrint('[Resume] resume check failed: $e');
    }
  }

  Future<void> _desktopTunResumeCheck() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    if (ref.read(connectionModeProvider) != 'tun') return;
    if (ref.read(userStoppedProvider)) return;
    try {
      final snapshot = await DesktopTunDiagnostics.instance.inspect(
        api: CoreManager.instance.api,
        mixedPort: CoreManager.instance.mixedPort,
        mode: 'tun',
        tunStack: ref.read(desktopTunStackProvider),
      );
      ref.read(desktopTunHealthProvider.notifier).state = snapshot;
      DesktopTunTelemetry.healthSnapshot(snapshot);
      if (snapshot.runningVerified) {
        if (ref.read(coreStatusProvider) == CoreStatus.degraded) {
          ref.read(coreStatusProvider.notifier).state = CoreStatus.running;
          ref.read(coreStartupErrorProvider.notifier).state = null;
        }
        return;
      }

      ref.read(coreStatusProvider.notifier).state = CoreStatus.degraded;
      ref.read(coreStartupErrorProvider.notifier).state = snapshot.userMessage;
      final plan = _desktopTunRepair.plan(snapshot);
      DesktopTunTelemetry.repairAttempt(snapshot, plan.action);
      await _desktopTunRepair.runThrottled(plan, () async {
        if (!plan.canRunAutomatically) return;
        if (plan.action == 'clear_system_proxy' ||
            plan.action == 'reapply_dns' ||
            plan.action == 'reapply_route' ||
            plan.action == 'refresh_state') {
          await SystemProxyManager.clear();
          if (Platform.isMacOS) await SystemProxyManager.setTunDns();
          try {
            await CoreManager.instance.api.closeAllConnections();
            await CoreManager.instance.api.flushFakeIpCache();
          } catch (_) {}
          return;
        }
        if (plan.action == 'restart_core' ||
            plan.action == 'cleanup_and_restart') {
          final activeId = await SettingsService.getActiveProfileId();
          if (activeId == null) return;
          final config = await ProfileService.loadConfig(activeId);
          if (config == null) return;
          await ref.read(coreActionsProvider).restart(config);
        }
      });
      final after = await DesktopTunDiagnostics.instance.inspect(
        api: CoreManager.instance.api,
        mixedPort: CoreManager.instance.mixedPort,
        mode: 'tun',
        tunStack: ref.read(desktopTunStackProvider),
      );
      ref.read(desktopTunHealthProvider.notifier).state = after;
      DesktopTunTelemetry.repairResult(after, plan.action);
      if (after.runningVerified) {
        ref.read(coreStatusProvider.notifier).state = CoreStatus.running;
        ref.read(coreStartupErrorProvider.notifier).state = null;
      }
    } catch (e) {
      debugPrint('[Resume] desktop TUN health/repair failed: $e');
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
