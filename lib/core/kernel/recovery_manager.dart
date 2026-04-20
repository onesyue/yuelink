import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/models/traffic.dart';
import '../../domain/models/traffic_history.dart';
import '../providers/core_provider.dart';
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

  // ── Shared state reset ─────────────────────────────────────────────────

  /// Reset all core-related provider state to stopped and stop the core.
  ///
  /// Used by:
  /// - `coreHeartbeatProvider` (core crash detection + proxy conflict)
  /// - `_onAppResumed()` (core dead after background)
  /// - `_setupVpnRevocationListener()` (Android VPN revoked)
  ///
  /// Both [Ref] and [WidgetRef] produce the same [StateController] from
  /// `.read(provider.notifier)`, so callers just pass the 4 notifiers.
  static void resetToStopped({
    required StateController<CoreStatus> status,
    required StateController<Traffic> traffic,
    required StateController<TrafficHistory> history,
    required StateController<int> historyVersion,
    bool clearDesktopProxy = true,
  }) {
    status.state = CoreStatus.stopped;
    traffic.state = const Traffic();
    history.state = TrafficHistory();
    historyVersion.state = 0;
    if (clearDesktopProxy && (Platform.isMacOS || Platform.isWindows)) {
      CoreActions.clearSystemProxyStatic().catchError((_) {});
    }
    CoreManager.instance.stop().catchError((_) {});
  }

  // ── Shared alive check ────────────────────────────────────────────────

  /// Check if the core is alive, handling iOS PacketTunnel extension.
  ///
  /// On iOS the Go core runs in a separate process so FFI `IsRunning`
  /// always returns false in the main app. Only the REST API check works.
  static Future<({bool alive, bool apiOk})> checkCoreHealth() async {
    final manager = CoreManager.instance;
    final apiOk = await manager.api
        .isAvailable()
        .timeout(const Duration(seconds: 2), onTimeout: () => false);
    if (Platform.isIOS || Platform.isAndroid) {
      return (alive: apiOk, apiOk: apiOk);
    }
    if (Platform.isMacOS || Platform.isWindows) {
      final connectionMode = await SettingsService.getConnectionMode();
      if (connectionMode == 'tun') {
        return (alive: apiOk, apiOk: apiOk);
      }
    }
    final alive = manager.isCoreActuallyRunning;
    return (
      alive: isAliveForPlatform(
        apiOk: apiOk,
        ffiRunning: alive,
        isAndroid: Platform.isAndroid,
        isIOS: Platform.isIOS,
      ),
      apiOk: apiOk,
    );
  }
}

// ── Convenience helper for call sites ─────────────────────────────────────

/// Shorthand: reads all 4 notifiers from [ref] and calls [RecoveryManager.resetToStopped].
///
/// Works from both `Ref` (Provider context) and `WidgetRef` (Widget context)
/// since both expose `.read(provider.notifier)`.
void resetCoreToStopped(dynamic ref, {bool clearDesktopProxy = true}) {
  RecoveryManager.resetToStopped(
    status: (ref as dynamic).read(coreStatusProvider.notifier),
    traffic: (ref as dynamic).read(trafficProvider.notifier),
    history: (ref as dynamic).read(trafficHistoryProvider.notifier),
    historyVersion:
        (ref as dynamic).read(trafficHistoryVersionProvider.notifier),
    clearDesktopProxy: clearDesktopProxy,
  );
}
