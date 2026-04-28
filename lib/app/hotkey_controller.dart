import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../modules/settings/hotkey_codec.dart';
import '../modules/settings/providers/settings_providers.dart'
    show toggleHotkeyProvider;

/// Owns the desktop global hotkey lifecycle (register / re-register on
/// settings change / cleanup on dispose).
///
/// Previously inlined in `_YueLinkAppState` (lib/main.dart) across
/// `_registerHotkeys`, `_reregisterHotkeys`, `_hotkeySub`, and the
/// `hotKeyManager.unregisterAll()` call in `dispose()`. Pulling them out
/// keeps main.dart's lifecycle code focused on widget concerns and lets
/// the hotkey state machine (parse stored string → register → listen for
/// settings changes → re-register) live in one file.
///
/// Linux is a no-op — global hotkeys are unreliable under Wayland and
/// every entry point silently skips registration on that platform.
///
/// Wiring:
///   1. `init(onTriggered: ...)` once in initState (after the tray
///      controller exists, since `onTriggered` is normally
///      `tray.handleToggle`).
///   2. `dispose()` from the widget's dispose.
///
/// `onTriggered` is invoked synchronously on the platform thread the
/// hotkey fired on; do not block.
class HotkeyController {
  HotkeyController({
    required this.ref,
    required this.onTriggered,
  });

  final WidgetRef ref;
  final VoidCallback onTriggered;

  ProviderSubscription? _settingsSub;

  /// Wire up the hotkey: parse the persisted shortcut string, register
  /// it with the OS, and start listening for setting changes (so the
  /// user editing the shortcut in Settings re-registers without an
  /// app restart).
  ///
  /// Idempotent — safe to call once per `initState`. Failure to register
  /// (another app holds the chord) is logged at debug level and dropped;
  /// the user is told via the Settings UI itself, not here.
  void init() {
    if (Platform.isLinux) {
      debugPrint('[Hotkey] skipped on Linux (Wayland not supported)');
      return;
    }
    if (!(Platform.isMacOS || Platform.isWindows)) return;

    _registerInitial();
    _settingsSub = ref.listenManual(toggleHotkeyProvider, (prev, next) {
      if (prev != null && prev != next) _reregister(next);
    });
  }

  /// Cleanup: unregister all global hotkeys and drop the settings
  /// listener. Mirrors the previous inline code in `_YueLinkAppState`'s
  /// `dispose()`. Idempotent.
  Future<void> dispose() async {
    _settingsSub?.close();
    _settingsSub = null;
    if (Platform.isMacOS || Platform.isWindows) {
      try {
        await hotKeyManager.unregisterAll();
      } catch (e) {
        debugPrint('[Hotkey] unregisterAll on dispose: $e');
      }
    }
  }

  Future<void> _registerInitial() async {
    try {
      final stored = ref.read(toggleHotkeyProvider);
      final toggleKey = parseStoredHotkey(stored);
      await hotKeyManager.register(
        toggleKey,
        keyDownHandler: (_) => onTriggered(),
      );
    } catch (e) {
      // Most common failure: another app already holds the chord.
      // Surface in debug logs only — the user already knows nothing
      // happens when they press it, and the Settings UI is the right
      // place to explain.
      debugPrint('[Hotkey] register: $e');
    }
  }

  Future<void> _reregister(String newHotkeyStr) async {
    try {
      await hotKeyManager.unregisterAll();
      final toggleKey = parseStoredHotkey(newHotkeyStr);
      await hotKeyManager.register(
        toggleKey,
        keyDownHandler: (_) => onTriggered(),
      );
    } catch (e) {
      debugPrint('[Hotkey] re-register: $e');
    }
  }
}
