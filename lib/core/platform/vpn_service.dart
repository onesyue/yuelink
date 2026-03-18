import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../storage/settings_service.dart';

/// Platform-specific VPN service abstraction.
///
/// Handles starting/stopping the OS-level VPN tunnel:
/// - Android: VpnService → returns TUN fd for injection into config YAML
/// - iOS: NEPacketTunnelProvider (Go core runs inside the extension)
/// - macOS: system proxy via networksetup
/// - Windows: system proxy via registry
class VpnService {
  static const _channel = MethodChannel('com.yueto.yuelink/vpn');

  /// Start the Android VPN service and obtain the TUN file descriptor.
  ///
  /// Returns the fd integer (> 0) on success, or -1 on failure.
  /// The fd must be injected into the mihomo config YAML as `tun.file-descriptor`
  /// before calling [CoreManager.start].
  static Future<int> startAndroidVpn({int mixedPort = 7890}) async {
    assert(Platform.isAndroid);
    try {
      // Load split-tunnel config and pass to native side
      final splitMode = await SettingsService.getSplitTunnelMode();
      final splitApps = await SettingsService.getSplitTunnelApps();
      final fd = await _channel.invokeMethod<int>('startVpn', {
        'mixedPort': mixedPort,
        'splitMode': splitMode,
        'splitApps': splitApps,
      });
      return fd ?? -1;
    } on PlatformException catch (_) {
      return -1;
    }
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
      );
      return (raw ?? [])
          .map((m) => {
                'packageName': m['packageName'] as String? ?? '',
                'appName': m['appName'] as String? ?? '',
              })
          .toList();
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
      final fd = await _channel.invokeMethod<int>('getTunFd');
      return fd ?? -1;
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
    final result = await _channel.invokeMethod<bool>('startVpn', configYaml);
    return result ?? false;
  }

  /// Start the platform VPN tunnel (iOS / generic path).
  static Future<bool> startVpn() async {
    try {
      final result = await _channel.invokeMethod<bool>('startVpn');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Stop the platform VPN tunnel.
  static Future<bool> stopVpn() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopVpn');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Request VPN permission (Android only).
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
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
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Clear system proxy settings.
  static Future<bool> clearSystemProxy() async {
    try {
      final result = await _channel.invokeMethod<bool>('clearSystemProxy');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
