// Settings-related providers.
//
// The core settings state providers (routingMode, connectionMode, logLevel,
// systemProxyOnConnect, autoConnect) are defined in core_provider.dart because
// CoreActions reads them directly. They are re-exported here for convenience so
// settings widgets can import from this single location.
//
// proxyProvidersProvider + ProxyProvidersNotifier have moved here from
// lib/providers/proxy_provider_provider.dart.
//
// The seven "UI preference" StateProviders below (theme, language, accent,
// sub-sync interval, QUIC policy, desktop close behavior, toggle hotkey)
// were previously declared at the top of settings_page.dart. Externalising
// them so main.dart and subscription_sync_service can pull them without
// importing the page file.
//
// NOTE: `core/profile/subscription_sync_service.dart` imports this file
// from inside `core/`, i.e. still `core -> modules`. Fixing that reverse
// dependency is out of scope for this batch — tracked for a follow-up.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/settings_service.dart';

// Re-export core settings state providers (defined in core_provider.dart to
// avoid circular imports with CoreActions).
export '../../../core/providers/core_provider.dart'
    show
        routingModeProvider,
        connectionModeProvider,
        logLevelProvider,
        systemProxyOnConnectProvider,
        autoConnectProvider;

// Re-export split tunnel providers.
export 'split_tunnel_provider.dart';

// Proxy providers (remote provider management).
export 'proxy_providers_provider.dart';

// ── UI preference providers (moved from settings_page.dart) ──────────────────

final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final languageProvider = StateProvider<String>((ref) => 'zh');

/// Accent color stored as hex string (without '#'), e.g. '3B82F6'.
final accentColorProvider = StateProvider<String>((ref) => '3B82F6');

/// Subscription sync interval in hours (0 = disabled).
final subSyncIntervalProvider = StateProvider<int>((ref) => 6);

/// QUIC reject policy: off | googlevideo | all.
final quicPolicyProvider =
    StateProvider<String>((ref) => SettingsService.defaultQuicPolicy);

/// Desktop: close window behavior. Values: 'tray' (default) | 'exit'.
final closeBehaviorProvider = StateProvider<String>((ref) => 'tray');

/// Desktop: toggle connection hotkey stored as "ctrl+alt+c" lowercase.
final toggleHotkeyProvider = StateProvider<String>((ref) => 'ctrl+alt+c');
