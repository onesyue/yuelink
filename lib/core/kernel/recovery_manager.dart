import 'dart:io';

import '../../domain/models/traffic.dart';
import '../../domain/models/traffic_history.dart';
import '../providers/core_provider.dart';
import '../managers/core_lifecycle_manager.dart';
import '../storage/settings_service.dart';
import 'core_manager.dart';

/// Centralised VPN recovery utilities.
///
/// Eliminates the duplicated "reset to stopped" pattern that was previously
/// copy-pasted across heartbeat, resume check, and VPN revocation handlers.
class RecoveryManager {
  RecoveryManager._();

  /// Android/iOS treat a reachable mihomo API as authoritative.
  ///
  /// On Android we've observed `IsRunning()` go false while the REST API is
  /// still healthy, which makes the UI flap to "disconnected" and triggers
  /// needless silent restarts. iOS already has the same property because the
  /// Go core lives in the PacketTunnel extension process.
  static bool isAliveForPlatform({
    required bool apiOk,
    required bool ffiRunning,
    required bool isAndroid,
    required bool isIOS,
  }) {
    if (isAndroid || isIOS) return apiOk;
    return apiOk && ffiRunning;
  }

  /// Same as [isAliveForPlatform] but also handles desktop TUN service
  /// mode (mihomo runs in the privileged helper subprocess, so the in-app
  /// FFI `IsRunning()` flag stays `false` even when the core is healthy).
  ///
  /// When [isDesktopTunService] is true, trust [apiOk] alone — symmetric
  /// to Android/iOS where the core also lives outside the main process.
  /// Without this branch the heartbeat sees apiOk=true + ffi=false on
  /// Windows/macOS/Linux service-mode TUN and triggers an endless loop
  /// of false-positive auto-recovery restarts.
  static bool isAliveForMode({
    required bool apiOk,
    required bool ffiRunning,
    required bool isAndroid,
    required bool isIOS,
    required bool isDesktopTunService,
  }) {
    if (isAndroid || isIOS || isDesktopTunService) return apiOk;
    return apiOk && ffiRunning;
  }

  // ── Shared state reset ─────────────────────────────────────────────────

  /// Reset all core-related provider state to stopped and stop the core.
  ///
  /// Used by:
  /// - `coreHeartbeatProvider` (core crash detection + proxy conflict)
  /// - `_onAppResumed()` (core dead after background)
  /// - `_setupVpnRevocationListener()` (Android VPN revoked)
  ///
  /// Both [Ref] and [WidgetRef] produce the same Notifier instance from
  /// `.read(provider.notifier)`, so callers just pass the 4 notifiers via
  /// the [resetCoreToStopped] convenience helper below.
  static void resetToStopped({
    required CoreStatusNotifier status,
    required TrafficNotifier traffic,
    required TrafficHistoryNotifier history,
    required TrafficHistoryVersionNotifier historyVersion,
    bool clearDesktopProxy = true,
  }) {
    status.set(CoreStatus.stopped);
    traffic.set(const Traffic());
    history.set(TrafficHistory());
    historyVersion.set(0);
    if (clearDesktopProxy && (Platform.isMacOS || Platform.isWindows)) {
      CoreActions.clearSystemProxyStatic().catchError((_) {});
    }
    CoreLifecycleManager.stopCoreForRecovery().catchError((_) {});
  }

  // ── Shared alive check ────────────────────────────────────────────────

  /// Check if the core is alive, handling iOS PacketTunnel extension.
  ///
  /// On iOS the Go core runs in a separate process so FFI `IsRunning`
  /// always returns false in the main app. Only the REST API check works.
  static Future<({bool alive, bool apiOk, String apiReason})>
  checkCoreHealth() async {
    final manager = CoreManager.instance;
    // Snapshot returns a classified reason (`'ok'` / `'socket'` /
    // `'timeout'` / `'http_<N>'` / `'other'`) so heartbeat can write
    // it to EventLog instead of just "down" — useful for
    // distinguishing transient network flap from a wedged mihomo
    // when triaging user reports.
    final snap = await manager.api.healthSnapshot().timeout(
      const Duration(seconds: 2),
      onTimeout: () => (ok: false, reason: 'timeout'),
    );
    var isDesktopTunService = false;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final connectionMode = await SettingsService.getConnectionMode();
      isDesktopTunService = connectionMode == 'tun';
    }
    return (
      alive: isAliveForMode(
        apiOk: snap.ok,
        ffiRunning: manager.isCoreActuallyRunning,
        isAndroid: Platform.isAndroid,
        isIOS: Platform.isIOS,
        isDesktopTunService: isDesktopTunService,
      ),
      apiOk: snap.ok,
      apiReason: snap.reason,
    );
  }
}

// ── Convenience helper for call sites ─────────────────────────────────────

/// Shorthand: reads all 4 notifiers from [ref] and calls
/// [RecoveryManager.resetToStopped].
///
/// Accepts `dynamic` so the same helper works from `Ref` (Provider) and
/// `WidgetRef` (Widget) call sites — both expose `.read(provider.notifier)`
/// and both yield the same typed Notifier instance per provider.
void resetCoreToStopped(dynamic ref, {bool clearDesktopProxy = true}) {
  RecoveryManager.resetToStopped(
    status: (ref as dynamic).read(coreStatusProvider.notifier)
        as CoreStatusNotifier,
    traffic: (ref as dynamic).read(trafficProvider.notifier) as TrafficNotifier,
    history: (ref as dynamic).read(trafficHistoryProvider.notifier)
        as TrafficHistoryNotifier,
    historyVersion: (ref as dynamic).read(trafficHistoryVersionProvider.notifier)
        as TrafficHistoryVersionNotifier,
    clearDesktopProxy: clearDesktopProxy,
  );
}
