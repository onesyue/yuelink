import 'package:flutter_riverpod/legacy.dart';

import '../kernel/config_template.dart';

// ──────────────────────────────────────────────────────────────────────────
// User preference providers (persisted to SettingsService on change)
// ──────────────────────────────────────────────────────────────────────────
//
// These providers hold user-configurable state that survives app restarts.
// Their initial values come from overrides set in main.dart after
// SettingsService resolves the persisted value.
//
// Keep this file free of infrastructure / modules imports — it is the
// preference layer, nothing else should creep in here.

/// Routing mode: "rule" | "global" | "direct"
final routingModeProvider = StateProvider<String>((ref) => 'rule');

/// Connection mode: "tun" | "systemProxy"
final connectionModeProvider = StateProvider<String>((ref) => 'systemProxy');

/// Desktop TUN stack: "mixed" | "system" | "gvisor"
final desktopTunStackProvider = StateProvider<String>((ref) => 'mixed');

/// Log level: "info" | "debug" | "warning" | "error" | "silent"
/// Default is `error` to match SettingsService.getLogLevel(). mihomo logs
/// every L4 connection at warn, so anything below `error` produces tens of
/// thousands of lines per session and buries real failures.
final logLevelProvider = StateProvider<String>((ref) => 'error');

/// Whether to auto-set system proxy on connect (desktop only)
final systemProxyOnConnectProvider = StateProvider<bool>((ref) => true);

/// Whether to auto-connect on startup
final autoConnectProvider = StateProvider<bool>((ref) => false);

/// QUIC reject policy: "off" | "googlevideo" | "all".
/// Read by CoreLifecycleManager at start-time and passed into
/// ConfigTemplate.processInIsolate explicitly — there is no process-wide
/// default fallback anymore (see commit removing _runtimeQuicRejectPolicy).
final quicPolicyProvider = StateProvider<String>(
  (ref) => ConfigTemplate.defaultQuicRejectPolicy,
);
