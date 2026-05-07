import 'package:flutter_riverpod/flutter_riverpod.dart';

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
//
// All providers below follow the same "value notifier" shape introduced
// in S3 batch3: constructor takes the initial value, `build()` returns it,
// `set()` writes through to `state`. The constructor-injected initial
// keeps `provider.overrideWith(() => N(v))` viable from main.dart.

/// Routing mode: "rule" | "global" | "direct"
final routingModeProvider = NotifierProvider<RoutingModeNotifier, String>(
  RoutingModeNotifier.new,
);

class RoutingModeNotifier extends Notifier<String> {
  RoutingModeNotifier([this._initial = 'rule']);
  final String _initial;

  @override
  String build() => _initial;

  void set(String value) => state = value;
}

/// Connection mode: "tun" | "systemProxy"
final connectionModeProvider = NotifierProvider<ConnectionModeNotifier, String>(
  ConnectionModeNotifier.new,
);

class ConnectionModeNotifier extends Notifier<String> {
  ConnectionModeNotifier([this._initial = 'systemProxy']);
  final String _initial;

  @override
  String build() => _initial;

  void set(String value) => state = value;
}

/// Desktop TUN stack: "mixed" | "system" | "gvisor"
final desktopTunStackProvider =
    NotifierProvider<DesktopTunStackNotifier, String>(
      DesktopTunStackNotifier.new,
    );

class DesktopTunStackNotifier extends Notifier<String> {
  DesktopTunStackNotifier([this._initial = 'mixed']);
  final String _initial;

  @override
  String build() => _initial;

  void set(String value) => state = value;
}

/// Log level: "info" | "debug" | "warning" | "error" | "silent"
/// Default is `error` to match SettingsService.getLogLevel(). mihomo logs
/// every L4 connection at warn, so anything below `error` produces tens of
/// thousands of lines per session and buries real failures.
final logLevelProvider = NotifierProvider<LogLevelNotifier, String>(
  LogLevelNotifier.new,
);

class LogLevelNotifier extends Notifier<String> {
  LogLevelNotifier([this._initial = 'error']);
  final String _initial;

  @override
  String build() => _initial;

  void set(String value) => state = value;
}

/// Whether to auto-set system proxy on connect (desktop only)
final systemProxyOnConnectProvider =
    NotifierProvider<SystemProxyOnConnectNotifier, bool>(
      SystemProxyOnConnectNotifier.new,
    );

class SystemProxyOnConnectNotifier extends Notifier<bool> {
  SystemProxyOnConnectNotifier([this._initial = true]);
  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}

/// Windows-only: when true, desktop TUN uses `strict-route: false` so apps
/// can reach LAN destinations (SMB / NAS web UI / 远程桌面 / 网络打印机).
/// Default `false` keeps the safer `strict-route: true`.
///
/// Read by [CoreManager] at start-time and threaded into
/// `ConfigTemplate.processInIsolate` so the resulting mihomo config carries
/// the flag (transformer is a pure function — no SettingsService access from
/// inside `tun_transformer.dart`).
final windowsLanCompatibilityModeProvider =
    NotifierProvider<WindowsLanCompatibilityModeNotifier, bool>(
      WindowsLanCompatibilityModeNotifier.new,
    );

class WindowsLanCompatibilityModeNotifier extends Notifier<bool> {
  WindowsLanCompatibilityModeNotifier([this._initial = false]);
  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}

/// Desktop only (D-⑤ P4-5): minutes the app sits in tray before
/// flipping `lightWeightModeProvider` true. 0 disables.
final autoLightWeightAfterMinutesProvider =
    NotifierProvider<AutoLightWeightAfterMinutesNotifier, int>(
      AutoLightWeightAfterMinutesNotifier.new,
    );

class AutoLightWeightAfterMinutesNotifier extends Notifier<int> {
  AutoLightWeightAfterMinutesNotifier([this._initial = 0]);
  final int _initial;

  @override
  int build() => _initial;

  void set(int value) => state = value;
}

/// `true` when the auto-light-weight controller has decided the app is
/// idle in tray and consumers should release heavy resources (chart
/// streams, webview frames, large in-memory caches). Cleared on app
/// resumed. Single source of truth — controller writes, anyone reads.
final lightWeightModeProvider =
    NotifierProvider<LightWeightModeNotifier, bool>(
      LightWeightModeNotifier.new,
    );

class LightWeightModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}

/// Whether to auto-connect on startup
final autoConnectProvider = NotifierProvider<AutoConnectNotifier, bool>(
  AutoConnectNotifier.new,
);

class AutoConnectNotifier extends Notifier<bool> {
  AutoConnectNotifier([this._initial = false]);
  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}

/// QUIC reject policy: "off" | "googlevideo" | "all".
/// Read by CoreLifecycleManager at start-time and passed into
/// ConfigTemplate.processInIsolate explicitly — there is no process-wide
/// default fallback anymore (see commit removing _runtimeQuicRejectPolicy).
final quicPolicyProvider = NotifierProvider<QuicPolicyNotifier, String>(
  QuicPolicyNotifier.new,
);

class QuicPolicyNotifier extends Notifier<String> {
  QuicPolicyNotifier([String? initial])
    : _initial = initial ?? ConfigTemplate.defaultQuicRejectPolicy;
  final String _initial;

  @override
  String build() => _initial;

  void set(String value) => state = value;
}
