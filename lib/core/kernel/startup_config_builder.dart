import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/models/relay_profile.dart';
import '../../infrastructure/surge_modules/module_rule_injector.dart';
import '../ffi/core_controller.dart';
import '../storage/settings_service.dart';
import 'config_template.dart';
import 'overwrite_service.dart';
import 'relay_injector.dart';

/// Pure-ish config-build pipeline used by `CoreManager.start()`.
///
/// Was inlined in `core_manager.dart` (~60 lines across `_prepareConfig`
/// + `_findAvailablePort`). Pulling it out:
///   * isolates the YAML / overwrite / module / relay / port-rebinding
///     pipeline from CoreManager's lifecycle bookkeeping;
///   * lets the port-conflict logic be unit-tested without booting a
///     real CoreManager;
///   * keeps the `RelayApplyResult` capture local — caller stores it on
///     CoreManager state from the returned [BuildConfigResult].
///
/// Stateless on purpose. CoreManager threads its current `_apiPort`
/// in and reads back the (possibly remapped) port from
/// [BuildConfigResult.apiPort]. Port-rebinding decisions never branch
/// on internal CoreManager fields — the caller owns the resulting
/// `_api` / `_stream` / `_clashCore` invalidation.

/// Outcome of [buildStartConfig]:
///   * [yaml] — final config string ready to hand to mihomo.
///   * [apiPort] — possibly-remapped external-controller port. When
///     this differs from the input, the caller must drop its cached
///     `MihomoApi` / `MihomoStream` / `ClashCore` so the next access
///     binds to the new port.
///   * [relayResult] — outcome of `RelayInjector.apply`, captured
///     verbatim so `CoreManager.lastRelayResult` reflects the same
///     value `StartupReport.relay` will see.
class BuildConfigResult {
  final String yaml;
  final int apiPort;
  final RelayApplyResult relayResult;

  const BuildConfigResult({
    required this.yaml,
    required this.apiPort,
    required this.relayResult,
  });
}

/// Build the final config YAML for a start. Runs the full pipeline:
/// overwrite → MITM module rules → upstream proxy → relay injector →
/// (desktop) port-conflict rebind.
///
/// `isMockMode` is taken explicitly so callers (CoreManager) don't
/// drag their CoreController instance through this surface.
Future<BuildConfigResult> buildStartConfig({
  required String configYaml,
  required int currentApiPort,
  required bool isMockMode,
  RelayProfile? relayProfile,
}) async {
  final overwrite = await OverwriteService.load();
  var withOverwrite = OverwriteService.apply(configYaml, overwrite);

  final mitmPort = CoreController.instance.getMitmEnginePort();
  withOverwrite = await ModuleRuleInjector.inject(
    withOverwrite,
    mitmPort: mitmPort,
  );

  final upstream = await SettingsService.getUpstreamProxy();
  if (upstream != null && (upstream['server'] as String).isNotEmpty) {
    withOverwrite = ConfigTemplate.injectUpstreamProxy(
      withOverwrite,
      upstream['type'] as String,
      upstream['server'] as String,
      upstream['port'] as int,
    );
  }

  // Commercial dialer-proxy (Phase 1A). Pure additive: no-op when the
  // profile is absent or invalid. Applied after upstream proxy so a user
  // who sets both gets the relay wrapping their chosen exit nodes while
  // the soft-router `_upstream` still fronts everything else.
  final relayResult = RelayInjector.apply(withOverwrite, relayProfile);
  withOverwrite = relayResult.config;

  // Port-conflict check applies to all desktop platforms — Linux is now
  // a first-class desktop target via .deb / .rpm / AppImage releases.
  // Mobile skips this (handled at OS level via VpnService).
  var apiPort = currentApiPort;
  if ((Platform.isMacOS || Platform.isLinux || Platform.isWindows) &&
      !isMockMode) {
    final preferredMixed = ConfigTemplate.getMixedPort(withOverwrite);
    final ports = await Future.wait([
      findAvailablePort(preferredMixed),
      findAvailablePort(currentApiPort),
    ]);
    final freeMixed = ports[0];
    final freeApi = ports[1];
    if (freeMixed != preferredMixed) {
      debugPrint(
        '[CoreManager] mixed-port $preferredMixed busy → remapped to $freeMixed',
      );
      withOverwrite = ConfigTemplate.setMixedPort(withOverwrite, freeMixed);
    }
    if (freeApi != currentApiPort) {
      debugPrint(
        '[CoreManager] apiPort $currentApiPort busy → remapped to $freeApi',
      );
      apiPort = freeApi;
    }
  }
  return BuildConfigResult(
    yaml: withOverwrite,
    apiPort: apiPort,
    relayResult: relayResult,
  );
}

/// Find a free TCP port starting from [preferred], trying up to 20
/// adjacent ports. Returns [preferred] if every probe fails — let
/// mihomo surface the eventual bind error rather than throwing here.
///
/// `bind(0)` would be cheaper but loses the "stable port across
/// restarts" property users rely on (custom firewall rules, browser
/// PAC files, etc.). The +20 slack is enough to dodge a single rival
/// proxy client (v2rayN / Clash Verge) without wandering into
/// unrelated ranges.
///
/// Probes BOTH `127.0.0.1` and `0.0.0.0` because a port is busy if
/// either address space claims it, and macOS lets a specific-address
/// `bind(127.0.0.1:7890)` succeed alongside an existing wildcard
/// `*:7890` (BSD allows the specific bind to shadow the wildcard for
/// that address). With `allow-lan: true` mihomo binds `*:port` and a
/// loopback-only probe false-passes — handing the same port to a
/// service-mode mihomo restart, which then crashes with
/// `bind: address already in use`. A loopback-only listener (e.g. a
/// stale FFI core's external-controller on 127.0.0.1:9090) conversely
/// fails the loopback probe but passes the wildcard probe; we need
/// both to fail-clean either way.
Future<int> findAvailablePort(int preferred) async {
  for (var port = preferred; port < preferred + 20; port++) {
    if (await _portIsFree(port)) return port;
  }
  return preferred;
}

Future<bool> _portIsFree(int port) async {
  for (final addr in [
    InternetAddress.loopbackIPv4,
    InternetAddress.anyIPv4,
  ]) {
    try {
      final server = await ServerSocket.bind(addr, port, shared: false);
      await server.close();
    } on SocketException {
      return false;
    }
  }
  return true;
}
