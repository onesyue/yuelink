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

  /// Callback invoked when the user taps the Quick Settings tile.
  /// The app should toggle the VPN connection.
  static VoidCallback? onToggleRequested;

  /// Initialize the tile service listener.
  /// Call once during app startup (Android only).
  static void init() {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'toggle') {
        debugPrint('[TileService] Toggle requested from Quick Settings tile');
        onToggleRequested?.call();
      }
    });
  }

  /// Update the Quick Settings tile state to reflect VPN status.
  /// Called whenever core status changes.
  static Future<void> updateState({required bool active}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('updateTileState', {'active': active});
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
      final result = await _channel.invokeMethod<bool>('consumePendingToggle');
      return result == true;
    } catch (e) {
      debugPrint('[TileService] consumePendingToggle error: $e');
      return false;
    }
  }
}
