import 'dart:io' show Platform;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:hotkey_manager/hotkey_manager.dart';

/// Codec between the persisted "ctrl+alt+c" lowercase string used in
/// SettingsService and the runtime shapes that the rest of the app needs:
/// a [HotKey] for hotkey_manager, or a pretty label for UI display.
///
/// Extracted from settings_page.dart so main.dart's hotkey registration and
/// sub settings pages can call in without importing the page file.

/// Parse stored hotkey string to a [HotKey].
HotKey parseStoredHotkey(String stored) {
  final parts = stored.toLowerCase().split('+');
  final modifiers = <HotKeyModifier>[];
  LogicalKeyboardKey key = LogicalKeyboardKey.keyC;
  for (final p in parts) {
    switch (p) {
      case 'ctrl':
      case 'control':
        modifiers.add(HotKeyModifier.control);
      case 'shift':
        modifiers.add(HotKeyModifier.shift);
      case 'alt':
        modifiers.add(HotKeyModifier.alt);
      case 'meta':
      case 'cmd':
      case 'win':
        modifiers.add(HotKeyModifier.meta);
      default:
        key = _logicalKeyFromLabel(p);
    }
  }
  return HotKey(key: key, modifiers: modifiers, scope: HotKeyScope.system);
}

/// Format stored hotkey string to display label, e.g. "ctrl+alt+c" → "Ctrl+Alt+C".
String displayHotkey(String stored) {
  return stored.split('+').map((p) {
    switch (p.toLowerCase()) {
      case 'ctrl':
      case 'control':
        return 'Ctrl';
      case 'shift':
        return 'Shift';
      case 'alt':
        return 'Alt';
      case 'meta':
      case 'cmd':
      case 'win':
        return Platform.isMacOS ? '⌘' : 'Win';
      default:
        return p.toUpperCase();
    }
  }).join('+');
}

LogicalKeyboardKey _logicalKeyFromLabel(String label) {
  const map = {
    'a': LogicalKeyboardKey.keyA,
    'b': LogicalKeyboardKey.keyB,
    'c': LogicalKeyboardKey.keyC,
    'd': LogicalKeyboardKey.keyD,
    'e': LogicalKeyboardKey.keyE,
    'f': LogicalKeyboardKey.keyF,
    'g': LogicalKeyboardKey.keyG,
    'h': LogicalKeyboardKey.keyH,
    'i': LogicalKeyboardKey.keyI,
    'j': LogicalKeyboardKey.keyJ,
    'k': LogicalKeyboardKey.keyK,
    'l': LogicalKeyboardKey.keyL,
    'm': LogicalKeyboardKey.keyM,
    'n': LogicalKeyboardKey.keyN,
    'o': LogicalKeyboardKey.keyO,
    'p': LogicalKeyboardKey.keyP,
    'q': LogicalKeyboardKey.keyQ,
    'r': LogicalKeyboardKey.keyR,
    's': LogicalKeyboardKey.keyS,
    't': LogicalKeyboardKey.keyT,
    'u': LogicalKeyboardKey.keyU,
    'v': LogicalKeyboardKey.keyV,
    'w': LogicalKeyboardKey.keyW,
    'x': LogicalKeyboardKey.keyX,
    'y': LogicalKeyboardKey.keyY,
    'z': LogicalKeyboardKey.keyZ,
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
  };
  return map[label.toLowerCase()] ?? LogicalKeyboardKey.keyC;
}
