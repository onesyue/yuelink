// Settings-related providers.
//
// The core settings state providers (routingMode, connectionMode, logLevel,
// systemProxyOnConnect, autoConnect) are defined in core_provider.dart because
// CoreActions reads them directly. They are re-exported here for convenience so
// settings widgets can import from this single location.
//
// `subSyncIntervalProvider` lives in `core/providers/subscription_sync_providers.dart`
// for the same reason (consumed by `core/profile/subscription_sync_service.dart`),
// and is re-exported here so settings-side imports stay stable.
//
// proxyProvidersProvider + ProxyProvidersNotifier have moved here from
// lib/providers/proxy_provider_provider.dart.
//
// The six "UI preference" providers below (theme, language, accent, close
// behavior, toggle hotkey, tile show node info) were previously
// `StateProvider`s; they're now `NotifierProvider`s with constructor-
// injected initial values so the existing `provider.overrideWith((ref) =>
// savedValue)` boot pattern in main.dart still has a one-liner equivalent
// (`provider.overrideWith(() => XNotifier(savedValue))`).

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Re-export core settings state providers (defined in core_provider.dart to
// avoid circular imports with CoreActions).
export '../../../core/providers/core_provider.dart'
    show
        routingModeProvider,
        connectionModeProvider,
        logLevelProvider,
        systemProxyOnConnectProvider,
        autoConnectProvider,
        quicPolicyProvider;

// Re-export subscription-sync interval (now defined under core/providers/
// so that core/profile/subscription_sync_service doesn't have to import
// back into modules/). The notifier class is included so settings-side
// callers (`main.dart` bootstrap, snapshot test) can pass an override
// without reaching into the `core/providers/` path.
export '../../../core/providers/subscription_sync_providers.dart'
    show subSyncIntervalProvider, SubSyncIntervalNotifier;

// Re-export split tunnel providers.
export 'split_tunnel_provider.dart';

// Proxy providers (remote provider management).
export 'proxy_providers_provider.dart';

// ── UI preference providers ──────────────────────────────────────────────────
//
// All six follow the same "value notifier" shape: constructor takes the
// initial value, `build()` returns it, `set()` writes through to `state`.
// The constructor-injected initial keeps `provider.overrideWith(() => N(v))`
// working as a one-liner from main.dart's preload step.

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);

class ThemeNotifier extends Notifier<ThemeMode> {
  ThemeNotifier([this._initial = ThemeMode.system]);
  final ThemeMode _initial;

  @override
  ThemeMode build() => _initial;

  void set(ThemeMode value) => state = value;
}

final languageProvider = NotifierProvider<LanguageNotifier, String>(
  LanguageNotifier.new,
);

class LanguageNotifier extends Notifier<String> {
  LanguageNotifier([this._initial = 'zh']);
  final String _initial;

  @override
  String build() => _initial;

  void set(String value) => state = value;
}

/// Accent color stored as hex string (without '#'), e.g. '3B82F6'.
final accentColorProvider = NotifierProvider<AccentColorNotifier, String>(
  AccentColorNotifier.new,
);

class AccentColorNotifier extends Notifier<String> {
  AccentColorNotifier([this._initial = '3B82F6']);
  final String _initial;

  @override
  String build() => _initial;

  void set(String value) => state = value;
}

/// Desktop: close window behavior. Values: 'tray' (default) | 'exit'.
final closeBehaviorProvider = NotifierProvider<CloseBehaviorNotifier, String>(
  CloseBehaviorNotifier.new,
);

class CloseBehaviorNotifier extends Notifier<String> {
  CloseBehaviorNotifier([this._initial = 'tray']);
  final String _initial;

  @override
  String build() => _initial;

  void set(String value) => state = value;
}

/// Desktop: toggle connection hotkey stored as "ctrl+alt+c" lowercase.
final toggleHotkeyProvider = NotifierProvider<ToggleHotkeyNotifier, String>(
  ToggleHotkeyNotifier.new,
);

class ToggleHotkeyNotifier extends Notifier<String> {
  ToggleHotkeyNotifier([this._initial = 'ctrl+alt+c']);
  final String _initial;

  @override
  String build() => _initial;

  void set(String value) => state = value;
}

/// Android-only: include current exit node ("🇭🇰 香港") in the Quick
/// Settings tile subtitle when connected. Default off — the QS panel is
/// visible to anyone who pulls down the shade. Lives here (not in
/// main.dart) so the tile controller and the settings UI both reach it
/// through the modules/settings path rather than reverse-importing the
/// app entry.
final tileShowNodeInfoProvider =
    NotifierProvider<TileShowNodeInfoNotifier, bool>(
      TileShowNodeInfoNotifier.new,
    );

class TileShowNodeInfoNotifier extends Notifier<bool> {
  TileShowNodeInfoNotifier([this._initial = false]);
  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}
