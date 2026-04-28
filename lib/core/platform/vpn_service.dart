import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../storage/settings_service.dart';

/// Callback type for VPN revocation events.

/// Platform-specific VPN service abstraction.
///
/// Handles starting/stopping the OS-level VPN tunnel:
/// - Android: VpnService → returns TUN fd for injection into config YAML
/// - iOS: NEPacketTunnelProvider (Go core runs inside the extension)
/// - macOS: system proxy via networksetup
/// - Windows: system proxy via registry
class VpnService {
  static const _channel = MethodChannel('com.yueto.yuelink/vpn');

  // ── MethodChannel timeout budgets ──────────────────────────────────────
  //
  // Pre-fix (v1.0.22 P3): MethodChannel calls relied entirely on the native
  // side returning. If the platform code hung — Samsung Secure Folder
  // edge cases, Doze-suspended VpnService binder, iOS configurationStale
  // race past the native 20 s cap — Dart awaits would never complete and
  // the user-facing "Connect" spinner stuck forever. Each call now has an
  // explicit budget; on expiry we surface failure via the same channel as
  // a `PlatformException` (return -1 / false / null) so callers' existing
  // error paths apply.
  //
  // Buckets:
  //   • _kPermissionDialogBudget — calls that surface a system dialog the
  //     user reads and decides on (VPN consent, battery whitelist).
  //   • _kStartTunnelBudget — `startVpn` after permission already granted;
  //     covers tunnel handshake + iOS configurationStale retry but stays
  //     short enough that a wedged native side surfaces fast.
  //   • _kQuickOpBudget — local file / state ops with no I/O blocking
  //     dialog (stop, reset, clear, query).
  static const _kPermissionDialogBudget = Duration(seconds: 60);
  static const _kStartTunnelBudget = Duration(seconds: 30);
  static const _kQuickOpBudget = Duration(seconds: 10);

  /// Start the Android VPN service and obtain the TUN file descriptor.
  ///
  /// Returns the fd integer (> 0) on success, or -1 on failure.
  /// The fd must be injected into the mihomo config YAML as `tun.file-descriptor`
  /// before calling [CoreManager.start].
  ///
  /// Auto-retries once on first-attempt failure. Android's `establish()` can
  /// return null even after a fresh `RESULT_OK` from the permission dialog on
  /// Samsung / Xiaomi / Huawei ROMs — the system hasn't finished settling
  /// VPN state. 1.5 s later, it succeeds. Previously this manifested as
  /// "first connect fails, second connect works" — the same symptom class
  /// that bites Windows TUN cold start.
  static Future<int> startAndroidVpn({int mixedPort = 7890}) async {
    assert(Platform.isAndroid);
    final splitMode = await SettingsService.getSplitTunnelMode();
    final splitApps = await SettingsService.getSplitTunnelApps();

    Future<int> attempt() async {
      try {
        final fd = await _channel.invokeMethod<int>('startVpn', {
          'mixedPort': mixedPort,
          'splitMode': splitMode,
          'splitApps': splitApps,
        }).timeout(_kPermissionDialogBudget);
        return fd ?? -1;
      } on TimeoutException {
        debugPrint('[VpnService] startAndroidVpn timed out after '
            '${_kPermissionDialogBudget.inSeconds}s');
        return -1;
      } on PlatformException catch (_) {
        return -1;
      }
    }

    var fd = await attempt();
    if (fd > 0) return fd;

    debugPrint('[VpnService] startAndroidVpn attempt-1 returned $fd — '
        'retrying once after 1.5 s (OEM settle race)');
    await Future.delayed(const Duration(milliseconds: 1500));
    fd = await attempt();
    if (fd <= 0) {
      debugPrint('[VpnService] startAndroidVpn retry also failed ($fd)');
    }
    return fd;
  }

  static const _appsChannel = MethodChannel('com.yueto.yuelink/apps');

  /// Returns installed apps as a list of {packageName, appName} maps.
  static Future<List<Map<String, String>>> getInstalledApps({
    bool showSystem = false,
  }) async {
    if (!Platform.isAndroid) return [];
    try {
      final raw = await _appsChannel.invokeListMethod<Map>(
        'getInstalledApps',
        {'showSystem': showSystem},
      ).timeout(_kStartTunnelBudget);
      return (raw ?? [])
          .map((m) => {
                'packageName': m['packageName'] as String? ?? '',
                'appName': m['appName'] as String? ?? '',
              })
          .toList();
    } on TimeoutException {
      debugPrint('[VpnService] getInstalledApps timed out after '
          '${_kStartTunnelBudget.inSeconds}s');
      return [];
    } on PlatformException catch (e) {
      debugPrint('[VpnService] getInstalledApps PlatformException: $e');
      return [];
    } catch (e) {
      debugPrint('[VpnService] getInstalledApps error: $e');
      return [];
    }
  }

  /// Get the current TUN fd without starting a new tunnel.
  /// Returns -1 if the VPN is not running.
  static Future<int> getTunFd() async {
    assert(Platform.isAndroid);
    try {
      final fd = await _channel
          .invokeMethod<int>('getTunFd')
          .timeout(_kQuickOpBudget);
      return fd ?? -1;
    } on TimeoutException {
      return -1;
    } on PlatformException catch (_) {
      return -1;
    }
  }

  /// Start the iOS VPN tunnel.
  ///
  /// [configYaml] is written to the App Group container so the
  /// PacketTunnel extension can load it on startup.
  static Future<bool> startIosVpn({required String configYaml}) async {
    assert(Platform.isIOS);
    // Do NOT catch PlatformException here — let it propagate so _step
    // records the actual iOS error code (VPN_SAVE_ERROR, VPN_START_ERROR, etc.)
    // in the startup report instead of the opaque "returned false" message.
    // Native side caps at 20 s; the 30 s Dart budget is a hard safety net
    // that surfaces as TimeoutException → fed into _step error code path.
    final result = await _channel
        .invokeMethod<bool>('startVpn', configYaml)
        .timeout(_kStartTunnelBudget);
    return result ?? false;
  }

  /// Start the platform VPN tunnel (iOS / generic path).
  static Future<bool> startVpn() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('startVpn')
          .timeout(_kStartTunnelBudget);
      return result ?? false;
    } on TimeoutException {
      return false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Stop the platform VPN tunnel.
  static Future<bool> stopVpn() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('stopVpn')
          .timeout(_kQuickOpBudget);
      return result ?? false;
    } on TimeoutException {
      return false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Request VPN permission (Android only).
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel
          .invokeMethod<bool>('requestPermission')
          .timeout(_kPermissionDialogBudget);
      return result ?? false;
    } on TimeoutException {
      return false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Set system proxy (desktop fallback mode).
  static Future<bool> setSystemProxy({
    required String host,
    required int httpPort,
    required int socksPort,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('setSystemProxy', {
        'host': host,
        'httpPort': httpPort,
        'socksPort': socksPort,
      }).timeout(_kQuickOpBudget);
      return result ?? false;
    } on TimeoutException {
      return false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Clear system proxy settings.
  static Future<bool> clearSystemProxy() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('clearSystemProxy')
          .timeout(_kQuickOpBudget);
      return result ?? false;
    } on TimeoutException {
      return false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Remove all VPN profiles and reset state (iOS).
  /// Next startVpn will create a fresh profile and re-trigger the system prompt.
  static Future<bool> resetVpnProfile() async {
    if (!Platform.isIOS) return true; // Only needed on iOS
    try {
      final result = await _channel
          .invokeMethod<bool>('resetVpnProfile')
          .timeout(_kQuickOpBudget);
      return result ?? false;
    } on TimeoutException {
      return false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Delete all config/geo files from the App Group container (iOS).
  /// Forces a full config rebuild on next connection.
  static Future<bool> clearAppGroupConfig() async {
    if (!Platform.isIOS) return true;
    try {
      final result = await _channel
          .invokeMethod<bool>('clearAppGroupConfig')
          .timeout(_kQuickOpBudget);
      return result ?? false;
    } on TimeoutException {
      return false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Register callbacks for VPN lifecycle events (Android-focused).
  ///
  /// [onRevoked] fires when the system or another app revokes VPN permission.
  /// [onTransportChanged] fires when the underlying physical network flips
  /// (e.g. Wi-Fi dropped → cellular picked up on elevator entry); consumer
  /// should flush fake-ip cache + close stale connections + optionally
  /// re-test node latency for the new network.
  ///
  /// Call this once during app initialization. iOS does not emit
  /// `transportChanged` — Apple's NetworkExtension handles re-routing
  /// transparently and connections usually survive the switch.
  static void listenForRevocation(
    VoidCallback onRevoked, {
    void Function(String prev, String now)? onTransportChanged,
  }) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'vpnRevoked':
          debugPrint('[VpnService] VPN revoked by system');
          onRevoked();
          break;
        case 'transportChanged':
          final args = (call.arguments as Map?)?.cast<String, dynamic>();
          final prev = args?['prev'] as String? ?? 'unknown';
          final now = args?['now'] as String? ?? 'unknown';
          debugPrint('[VpnService] transport changed: $prev → $now');
          onTransportChanged?.call(prev, now);
          break;
      }
    });
  }

  /// Whether the user has whitelisted YueLink from battery optimizations.
  /// Pre-M devices return true (no Doze). iOS / desktop always return true
  /// (not applicable).
  static Future<bool> isBatteryOptimizationIgnored() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _channel
          .invokeMethod<bool>('isBatteryOptimizationIgnored')
          .timeout(_kQuickOpBudget);
      return ok ?? false;
    } on TimeoutException {
      return false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Surface the system battery-optimization whitelist dialog (Android only).
  /// Returns false if the OS has no settings UI for it (rare; very old ROMs).
  ///
  /// Users on Xiaomi/Huawei/OPPO need this — Doze kills VpnService after
  /// screen-off + ~30 min idle. Whitelisted apps keep the tunnel alive.
  static Future<bool> requestIgnoreBatteryOptimization() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _channel
          .invokeMethod<bool>('requestIgnoreBatteryOptimization')
          .timeout(_kPermissionDialogBudget);
      return ok ?? false;
    } on TimeoutException {
      return false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
