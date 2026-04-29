import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android Quick Settings tile integration.
///
/// Provides two-way communication between Flutter and the native ProxyTileService:
/// - Flutter -> Native: updates tile state when VPN connects/disconnects
/// - Native -> Flutter: receives toggle requests from the Quick Settings tile
class TileService {
  static const _channel = MethodChannel('com.yueto.yuelink/tile');
  static const _channelTimeout = Duration(milliseconds: 900);

  /// Callback invoked when the user taps the Quick Settings tile.
  /// The app should toggle the VPN connection.
  static VoidCallback? onToggleRequested;

  /// Callback invoked when the user long-presses the Quick Settings tile.
  /// The system routes this via ACTION_QS_TILE_PREFERENCES to MainActivity,
  /// which forwards `openPreferences` through the tile channel. The app
  /// should navigate to the node-selection page.
  static VoidCallback? onOpenPreferences;

  /// Initialize the tile service listener.
  /// Call once during app startup (Android only).
  static void init() {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'toggle':
          debugPrint('[TileService] Toggle requested from Quick Settings tile');
          onToggleRequested?.call();
          return null;
        case 'openPreferences':
          debugPrint('[TileService] Long-press requested — open preferences');
          onOpenPreferences?.call();
          return null;
      }
      return null;
    });
  }

  /// Update the Quick Settings tile state to reflect VPN status.
  /// Called whenever core status changes.
  ///
  /// - [active]: true when the core is running, false otherwise.
  /// - [transition]: "starting" or "stopping" during the in-flight VPN
  ///   handshake. While set, the tile renders STATE_UNAVAILABLE with
  ///   a "连接中..." / "断开中..." subtitle so the user sees instant
  ///   feedback during the 2–5s mihomo bring-up.
  /// - [subtitle]: optional display override (e.g. "🇭🇰 香港") shown when
  ///   the active-and-no-transition case would otherwise read "已连接".
  ///   Only set when the user opts in to "show node in tile".
  static Future<void> updateState({
    required bool active,
    String? transition,
    String? subtitle,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel
          .invokeMethod('updateTileState', {
            'active': active,
            'transition': transition,
            'subtitle': subtitle,
          })
          .timeout(_channelTimeout);
    } on TimeoutException {
      debugPrint('[TileService] updateTileState timed out');
    } on PlatformException catch (e) {
      debugPrint('[TileService] updateTileState failed: $e');
    } catch (e) {
      debugPrint('[TileService] updateTileState error: $e');
    }
  }

  /// Drain any toggle queued by ProxyTileService while the Flutter engine
  /// was still booting (cold-start tile click). Returns true if there was
  /// a pending toggle that was consumed; the caller should then trigger
  /// the toggle action.
  ///
  /// Backed by the same SharedPreferences (`yuelink_tile_prefs`) the
  /// native tile service writes to — atomic flip via getAndClear so we
  /// can't double-fire if init runs twice.
  static Future<bool> consumePendingToggle() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel
          .invokeMethod<bool>('consumePendingToggle')
          .timeout(_channelTimeout, onTimeout: () => false);
      return result == true;
    } catch (e) {
      debugPrint('[TileService] consumePendingToggle error: $e');
      return false;
    }
  }
}
