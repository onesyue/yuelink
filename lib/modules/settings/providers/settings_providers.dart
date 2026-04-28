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
// The six "UI preference" StateProviders below (theme, language, accent,
// QUIC policy, desktop close behavior, toggle hotkey) were previously
// declared at the top of settings_page.dart.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/legacy.dart';

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
// back into modules/).
export '../../../core/providers/subscription_sync_providers.dart'
    show subSyncIntervalProvider;

// Re-export split tunnel providers.
export 'split_tunnel_provider.dart';

// Proxy providers (remote provider management).
export 'proxy_providers_provider.dart';

// ── UI preference providers (moved from settings_page.dart) ──────────────────

final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final languageProvider = StateProvider<String>((ref) => 'zh');

/// Accent color stored as hex string (without '#'), e.g. '3B82F6'.
final accentColorProvider = StateProvider<String>((ref) => '3B82F6');

/// Desktop: close window behavior. Values: 'tray' (default) | 'exit'.
final closeBehaviorProvider = StateProvider<String>((ref) => 'tray');

/// Desktop: toggle connection hotkey stored as "ctrl+alt+c" lowercase.
final toggleHotkeyProvider = StateProvider<String>((ref) => 'ctrl+alt+c');

/// Android-only: include current exit node ("🇭🇰 香港") in the Quick
/// Settings tile subtitle when connected. Default off — the QS panel is
/// visible to anyone who pulls down the shade. Lives here (not in
/// main.dart) so the tile controller and the settings UI both reach it
/// through the modules/settings path rather than reverse-importing the
/// app entry.
final tileShowNodeInfoProvider = StateProvider<bool>((ref) => false);
