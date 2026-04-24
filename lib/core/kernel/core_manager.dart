import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../constants.dart';
import '../clash_core.dart';
import '../clash_core_mock.dart';
import '../clash_core_real.dart';
import '../ffi/core_controller.dart';
import '../../domain/models/relay_profile.dart';
import '../../domain/models/startup_report.dart';
import 'config_template.dart';
import 'geodata_service.dart';
import '../../infrastructure/datasources/mihomo_api.dart';
import '../../infrastructure/datasources/mihomo_stream.dart';
import '../relay/relay_candidate.dart';
import '../relay/relay_selection.dart';
import '../service/service_client.dart';
import '../service/service_manager.dart';
import '../service/service_models.dart';
import 'overwrite_service.dart';
import 'process_manager.dart';
import 'relay_injector.dart';
import '../storage/relay_profile_service.dart';
import '../storage/settings_service.dart';
import '../platform/vpn_service.dart' as vpn;
import '../../infrastructure/surge_modules/module_rule_injector.dart';
import '../../shared/telemetry.dart';

/// How mihomo is managed.
enum CoreMode { ffi, subprocess, mock }

/// Manages the mihomo core lifecycle and provides API access.
class CoreManager {
  CoreManager._() {
    _core = CoreController.instance;
    _mode = _core.isMockMode ? CoreMode.mock : CoreMode.ffi;
  }

  static CoreManager? _instance;
  static CoreManager get instance => _instance ??= CoreManager._();

  /// Reset singleton state for testing. Never call in production.
  @visibleForTesting
  static void resetForTesting() {
    _instance?._running = false;
    _instance?._initialized = false;
    _instance?._serviceModeActive = false;
    _instance?._pendingOperation = null;
    _instance?.lastReport = null;
    _instance?.lastRelayResult = null;
    _instance?.lastSelectedKind = null;
    _instance?.lastSelectedReason = null;
    // Clear cached secret + API clients so tests can observe a clean
    // cold-start resolution path (persisted-read → generate → persist).
    _instance?._apiSecret = null;
    _instance?._api = null;
    _instance?._stream = null;
    _instance?._clashCore = null;
  }

  late final CoreController _core;
  late CoreMode _mode;
  MihomoApi? _api;
  MihomoStream? _stream;
  ClashCore? _clashCore;

  /// Unified clash interface — same surface in mock and real mode.
  /// Lifecycle delegates to FFI (real) or [CoreMock] (mock); data delegates
  /// to [MihomoApi] (real) or [CoreMock] (mock). Created lazily so the
  /// `_api` getter has a chance to bind to the right port first.
  ///
  /// Prefer this in new code over reaching into [CoreController] /
  /// [MihomoApi] / [CoreMock] directly. The `if (isMockMode) ... else ...`
  /// dispatch sites in providers and pages should use `core.X()` instead.
  ClashCore get core =>
      _clashCore ??= isMockMode ? MockClashCore() : RealClashCore(api);
  bool _running = false;
  bool _initialized = false;
  bool _serviceModeActive = false;

  /// Guards against concurrent start/stop calls.
  Completer<void>? _pendingOperation;

  /// The most recent startup report (kept in memory for UI).
  StartupReport? lastReport;

  /// Structured outcome of the most recent `RelayInjector.apply` call.
  /// Null until the first `start()`. Surfaced on StartupReport.relay so
  /// dashboards can distinguish "configured but skipped" from "actually
  /// injected", without logging any PII.
  RelayApplyResult? lastRelayResult;

  /// Which candidate kind the relay selector picked for the most recent
  /// start. Always set after a start runs (selector always returns a
  /// candidate). Null only before the first start. Phase 1B A5a: this is
  /// almost always [RelayCandidateKind.direct] because metrics are empty
  /// (probes land in A5b).
  RelayCandidateKind? lastSelectedKind;

  /// Why the selector picked what it picked — sourced from
  /// [LowestLatencySelector.lastReason]. Null when the selector
  /// implementation doesn't expose a reason (only happens in tests).
  String? lastSelectedReason;

  MihomoApi get api => _api ??= MihomoApi(
        host: '127.0.0.1',
        port: _apiPort,
        secret: _apiSecret,
      );

  int _apiPort = 9090;
  String? _apiSecret;

  MihomoStream get stream => _stream ??= MihomoStream(
        host: '127.0.0.1',
        port: _apiPort,
        secret: _apiSecret,
      );

  CoreMode get mode => _mode;
  bool get isMockMode => _mode == CoreMode.mock;
  bool get isRunning => _running;
  int get mixedPort => _mixedPort;

  /// Check Go core's actual running state via FFI (not the Dart _running flag).
  /// Use this to detect if the core is still alive after Flutter engine restart.
  bool get isCoreActuallyRunning {
    if (isMockMode || _serviceModeActive) return _running;
    try {
      return _core.isRunning;
    } catch (e) {
      debugPrint('[CoreManager] isCoreActuallyRunning check failed: $e');
      return false;
    }
  }

  /// Restore the Dart _running flag and port config after detecting that the
  /// Go core survived a Flutter engine restart. Called from _onAppResumed.
  Future<void> markRunning() async {
    _running = true;
    final savedConnectionMode = await SettingsService.getConnectionMode();
    // Mirror _shouldUseDesktopServiceMode platform list — Linux is now
    // a first-class service mode platform, not silently excluded.
    _serviceModeActive = ServiceManager.isSupported &&
        (Platform.isMacOS || Platform.isLinux || Platform.isWindows) &&
        savedConnectionMode == 'tun' &&
        await ServiceManager.isInstalled();
    // Restore ports from persisted settings (engine restart loses Dart state)
    final savedApiPort = await SettingsService.get<int>('lastApiPort');
    final savedMixedPort = await SettingsService.get<int>('lastMixedPort');
    if (savedApiPort != null) _apiPort = savedApiPort;
    if (savedMixedPort != null) _mixedPort = savedMixedPort;
    // Recreate API/stream clients with restored ports
    _api = null;
    _stream = null;
    _clashCore = null;
  }

  /// Persist current ports so they can be restored after engine restart.
  Future<void> _persistPorts() async {
    await SettingsService.set('lastApiPort', _apiPort);
    await SettingsService.set('lastMixedPort', _mixedPort);
  }

  int _mixedPort = 7890;

  void configure({int? port, String? secret, CoreMode? mode}) {
    if (port != null) _apiPort = port;
    // Only replace cached secret when the caller actually supplies one.
    // Previously `_apiSecret = secret` unconditionally wiped the cached
    // value if called with `secret: null`, breaking the API client for
    // the rest of the session.
    if (secret != null) _apiSecret = secret;
    if (mode != null) _mode = mode;
    _api = null;
    _stream = null;
    _clashCore = null;
  }

  // ==================================================================
  // Start — 7 observable steps with errorCodes
  // ==================================================================
  //
  //  Step       | errorCode                  | What it checks
  //  -----------|----------------------------|-----------------------------
  //  ensureGeo  | E009_GEO_FILES_FAILED      | Geo files copied from assets
  //  initCore   | E002_INIT_CORE_FAILED      | Go InitCore(homeDir)
  //  vpnPerm    | E003_VPN_PERMISSION_DENIED  | Android VPN permission
  //  startVpn   | E004_VPN_FD_INVALID        | Android TUN fd
  //  buildConfig| E005_CONFIG_BUILD_FAILED    | Overwrite + template + TUN inject
  //  startCore  | E006_CORE_START_FAILED      | Go hub.Parse()
  //  waitApi    | E007_API_TIMEOUT            | REST API readiness
  //  verify     | E008_CORE_DIED_AFTER_START  | isRunning + API recheck

  Future<bool> start(
    String configYaml, {
    String connectionMode = 'systemProxy',
    String desktopTunStack = AppConstants.defaultDesktopTunStack,
    List<String> tunBypassAddresses = const [],
    List<String> tunBypassProcesses = const [],
  }) async {
    debugPrint('[CoreManager] ══════ START ══════');
    if (_running) return true;

    // Wait for any pending start/stop to complete before proceeding
    if (_pendingOperation != null) {
      await _pendingOperation!.future;
    }
    if (_running) return true; // re-check after waiting
    _pendingOperation = Completer<void>();

    // Resolve the external-controller secret BEFORE building config.
    //   1. If we already have one cached this session, keep it.
    //   2. Otherwise load the persisted secret from SettingsService.
    //   3. Otherwise generate a fresh one and persist it — once.
    // A subscription YAML that already declares its own `secret:` will
    // override whatever we pass; CoreManager picks that value up via
    // ConfigTemplate.getSecret(processed) and it flows through unchanged.
    _apiSecret ??= await SettingsService.getClashApiSecret();
    if (_apiSecret == null || _apiSecret!.isEmpty) {
      _apiSecret = _generateApiSecret();
      await SettingsService.setClashApiSecret(_apiSecret!);
    }

    final steps = <StartupStep>[];
    String? homeDir;

    try {
      // iOS: separate process, different path
      if (Platform.isIOS && !isMockMode) {
        return _startIos(
          configYaml,
          steps,
          connectionMode: connectionMode,
          desktopTunStack: desktopTunStack,
          tunBypassAddresses: tunBypassAddresses,
          tunBypassProcesses: tunBypassProcesses,
        );
      }

      if (await _shouldUseDesktopServiceMode(connectionMode)) {
        return _startDesktopServiceMode(
          configYaml,
          steps,
          connectionMode: connectionMode,
          desktopTunStack: desktopTunStack,
          tunBypassAddresses: tunBypassAddresses,
          tunBypassProcesses: tunBypassProcesses,
        );
      }
      _serviceModeActive = false;

      // ── Steps 1+2: ensureGeo + initCore (parallelized) ─────────────
      // These steps are independent — geo files don't need the core, and
      // core init doesn't need geo files. Running in parallel saves
      // 100-500ms on first launch or when CDN fallback is needed.
      await Future.wait([
        _step(steps, 'ensureGeo', StartupError.geoFilesFailed, () async {
          final installed = await GeoDataService.ensureFiles();
          return 'installed=$installed';
        }),
        _step(steps, 'initCore', StartupError.initCoreFailed, () async {
          if (_initialized) {
            return 'skip (already initialized)';
          }
          if (_mode == CoreMode.mock) {
            // Mock mode: call init so CoreMock._isInit = true (required for
            // mock start/getProxies to return data).
            final appDir = await getApplicationSupportDirectory();
            homeDir = appDir.path;
            _core.init(homeDir!);
            _initialized = true;
            return 'mock init, homeDir=$homeDir';
          }
          final appDir = await getApplicationSupportDirectory();
          homeDir = appDir.path;

          // Verify writable
          final testFile = File('$homeDir/.write_test');
          await testFile.writeAsString('ok');
          await testFile.delete();

          final error = await _core.initAsync(homeDir!);
          if (error != null && error.isNotEmpty) {
            throw Exception(error);
          }
          _initialized = true;
          return 'homeDir=$homeDir';
        }),
      ]); // end Future.wait(ensureGeo, initCore)

      // ── Step 3: vpnPermission (Android only) ───────────────────────
      if (Platform.isAndroid && !isMockMode) {
        await _step(steps, 'vpnPermission', StartupError.vpnPermissionDenied,
            () async {
          final granted = await vpn.VpnService.requestPermission();
          if (!granted) {
            throw Exception('user denied VPN permission');
          }
          return 'granted';
        });
      }

      // ── Step 4+5: startVpn + buildConfig (parallelized on Android) ──
      // On Android, VPN fd retrieval and config preprocessing (overwrite +
      // upstream proxy + port scan) are independent. Run them in parallel
      // to shave 100-200ms off startup.
      int? tunFd;
      String processed = '';

      // A5a relay wiring: cold-start selector decides per-start whether
      // we inject the persisted relay profile or run direct. Empty
      // metrics today → selector returns direct, profile passed through
      // is null, RelayInjector becomes a no-op, persisted profile stays
      // intact for the next start (no clear() — see _resolveRelay docs).
      final relay = await _resolveRelay();

      // Pre-compute config overwrite layer while VPN fd is being obtained.
      Future<String> prepareConfig() =>
          _prepareConfig(configYaml, relayProfile: relay.profile);

      if (Platform.isAndroid && !isMockMode) {
        // Run VPN fd + config prep in parallel
        late final Future<String> configFuture;
        await _step(steps, 'startVpn', StartupError.vpnFdInvalid, () async {
          configFuture = prepareConfig();
          final rawMp = ConfigTemplate.getMixedPort(configYaml);
          tunFd = await vpn.VpnService.startAndroidVpn(mixedPort: rawMp);
          if (tunFd == null || tunFd! <= 0) {
            throw Exception('fd=$tunFd (expected > 0)');
          }
          return 'fd=$tunFd, mixedPort=$rawMp';
        });

        await _step(steps, 'buildConfig', StartupError.configBuildFailed,
            () async {
          final withOverwrite = await configFuture;
          processed = await ConfigTemplate.processInIsolate(
            withOverwrite,
            apiPort: _apiPort,
            secret: _apiSecret,
            connectionMode: connectionMode,
            desktopTunStack: desktopTunStack,
            tunBypassAddresses: tunBypassAddresses,
            tunBypassProcesses: tunBypassProcesses,
            tunFd: tunFd,
            relayHostWhitelist: relay.bypassHosts,
          );
          _apiPort = ConfigTemplate.getApiPort(processed);
          _mixedPort = ConfigTemplate.getMixedPort(processed);
          final parsedSecret = ConfigTemplate.getSecret(processed);
          if (parsedSecret != null && parsedSecret.isNotEmpty) {
            _apiSecret = parsedSecret;
          }
          _api = null;
          _stream = null;
          _clashCore = null;
          return 'output=${processed.length}b, apiPort=$_apiPort, mixedPort=$_mixedPort, tunFd=$tunFd';
        });
      } else {
        // Non-Android: sequential (no VPN step)
        await _step(steps, 'buildConfig', StartupError.configBuildFailed,
            () async {
          final withOverwrite = await prepareConfig();
          processed = await ConfigTemplate.processInIsolate(
            withOverwrite,
            apiPort: _apiPort,
            secret: _apiSecret,
            connectionMode: connectionMode,
            desktopTunStack: desktopTunStack,
            tunBypassAddresses: tunBypassAddresses,
            tunBypassProcesses: tunBypassProcesses,
            tunFd: tunFd,
            relayHostWhitelist: relay.bypassHosts,
          );
          _apiPort = ConfigTemplate.getApiPort(processed);
          _mixedPort = ConfigTemplate.getMixedPort(processed);
          final parsedSecret = ConfigTemplate.getSecret(processed);
          if (parsedSecret != null && parsedSecret.isNotEmpty) {
            _apiSecret = parsedSecret;
          }
          _api = null;
          _stream = null;
          _clashCore = null;
          return 'output=${processed.length}b, apiPort=$_apiPort, mixedPort=$_mixedPort';
        });
      }

      // ── Step 6: startCore (Go hub.Parse) ───────────────────────────
      await _step(steps, 'startCore', StartupError.coreStartFailed, () async {
        // Write config to disk for debugging (atomic tmp+rename)
        debugPrint('[CoreManager] startCore: writing config to disk...');
        final appDir = await getApplicationSupportDirectory();
        final configFile =
            File('${appDir.path}/${AppConstants.configFileName}');
        final tmpFile = File('${configFile.path}.tmp');
        await tmpFile.writeAsString(processed);
        await tmpFile.rename(configFile.path);

        switch (_mode) {
          case CoreMode.mock:
            final error = _core.start(processed);
            if (error != null && error.isNotEmpty) throw Exception(error);
            _running = true;
            return 'mock started';

          case CoreMode.ffi:
            debugPrint(
                '[CoreManager] startCore: calling StartCore FFI (may take 1-3s)...');
            final error = await _core.startAsync(processed);
            debugPrint('[CoreManager] startCore: StartCore returned: $error');
            if (error != null && error.isNotEmpty) throw Exception(error);
            _running = true;
            final goRunning = _core.isRunning;
            return 'ffi OK, isRunning=$goRunning';

          case CoreMode.subprocess:
            final path = await ProcessManager.writeConfig(processed);
            final ok = await ProcessManager.instance
                .start(configPath: path, apiPort: _apiPort);
            if (!ok) throw Exception('subprocess start failed');
            _running = true;
            return 'subprocess OK';
        }
      });

      // ── Step 7: waitApi ────────────────────────────────────────────
      // Progressive backoff: fast polling (50ms) for the first second to
      // catch the common ~200-500ms startup, then slower (100-200ms) to
      // avoid burning CPU on laggy devices / large subscriptions where the
      // API can take 5-10s to bind. Total ceiling 14s — covers the 2-user
      // startup_fail cases observed at the original 5s cap.
      await _step(steps, 'waitApi', StartupError.apiTimeout, () async {
        if (isMockMode) return 'skip (mock)';
        for (var i = 1; i <= 100; i++) {
          // Fast-fail: if Go core died (panic / crash after StartCore returned),
          // stop polling immediately instead of waiting the full timeout.
          if (!_core.isRunning) {
            throw Exception(
                'Core is no longer running at attempt $i — check core.log for crash/parse details');
          }
          if (await api.isAvailable()) {
            return 'ready after $i attempts';
          }
          final waitMs = i <= 20 ? 50 : (i <= 50 ? 100 : 200);
          await Future.delayed(Duration(milliseconds: waitMs));
        }
        // All 100 attempts exhausted (~14s). Gather diagnostics before throwing.
        final goRunning = _core.isRunning;
        String portState;
        try {
          final sock = await Socket.connect(
            '127.0.0.1',
            _apiPort,
            timeout: const Duration(milliseconds: 300),
          );
          sock.destroy();
          portState =
              'port $_apiPort IS listening (HTTP not responding — secret mismatch or non-200?)';
        } on SocketException catch (e) {
          portState =
              'port $_apiPort NOT listening (${e.osError?.message ?? e.message}) '
              '— external-controller may not have started (config parse failed/fallback?)';
        } catch (e) {
          portState = 'port $_apiPort probe error: $e';
        }
        _running = false;
        _core.stop();
        throw Exception('API not available after 100 attempts (~14s): '
            'isRunning=$goRunning, $portState');
      });

      // ── Step 8: verify ─────────────────────────────────────────────
      await _step(steps, 'verify', StartupError.coreDiedAfterStart, () async {
        if (isMockMode) return 'skip (mock)';
        final goRunning = _core.isRunning;
        final apiOk = await api.isAvailable();

        if (!goRunning) throw Exception('isRunning=false');
        if (!apiOk) throw Exception('API unavailable after startup');

        // Save known-good config
        final appDir = await getApplicationSupportDirectory();
        await File('${appDir.path}/$_kLastWorkingConfig')
            .writeAsString(processed);

        String info = 'goRunning=$goRunning, apiOk=$apiOk';

        // DNS diagnostic (non-blocking)
        try {
          final dns = await api.queryDns('google.com');
          final answers = dns['Answer'] as List?;
          info += ', dns=${answers?.length ?? 0}answers';
        } catch (e) {
          info += ', dnsErr=$e';
        }

        return info;
      });

      // ── Success ────────────────────────────────────────────────────
      await _persistPorts();
      await _finishReport(steps, true, null);
      _pendingOperation?.complete();
      _pendingOperation = null;
      return true;
    } catch (e) {
      final failedName =
          steps.where((s) => !s.success).firstOrNull?.name ?? 'unknown';
      await _finishReport(steps, false, failedName);

      // Clean up partial state
      if (_running) {
        _running = false;
        try {
          if (_serviceModeActive) {
            await ServiceClient.stop();
          } else if (!Platform.isIOS) {
            _core.stop();
          }
        } catch (e) {
          debugPrint(
              '[CoreManager] cleanup core.stop() after failed start: $e');
        }
      }
      _serviceModeActive = false;
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          await vpn.VpnService.stopVpn();
        } catch (e) {
          debugPrint('[CoreManager] cleanup stopVpn after failed start: $e');
        }
      }

      _pendingOperation?.complete();
      _pendingOperation = null;
      rethrow;
    }
  }

  // ==================================================================
  // iOS start
  // ==================================================================

  Future<bool> _startIos(
    String configYaml,
    List<StartupStep> steps, {
    String connectionMode = 'systemProxy',
    String desktopTunStack = AppConstants.defaultDesktopTunStack,
    List<String> tunBypassAddresses = const [],
    List<String> tunBypassProcesses = const [],
  }) async {
    String processed = configYaml;

    try {
      await _step(steps, 'buildConfig_ios', StartupError.configBuildFailed,
          () async {
        final overwrite = await OverwriteService.load();
        var withOverwrite = OverwriteService.apply(configYaml, overwrite);

        // [ModuleRuntime] inject enabled module rules (+ MITM routing if engine running)
        final mitmPort = CoreController.instance.getMitmEnginePort();
        withOverwrite =
            await ModuleRuleInjector.inject(withOverwrite, mitmPort: mitmPort);

        // Inject upstream proxy if configured
        final upstream = await SettingsService.getUpstreamProxy();
        if (upstream != null && (upstream['server'] as String).isNotEmpty) {
          withOverwrite = ConfigTemplate.injectUpstreamProxy(
            withOverwrite,
            upstream['type'] as String,
            upstream['server'] as String,
            upstream['port'] as int,
          );
        }

        // A5a relay wiring on iOS path. Same semantics as main start:
        // selector decides per-start; bypassHosts is iOS-critical because
        // fake-ip would otherwise hand the relay host a 198.18.x.x and
        // route it back into the packet tunnel (classic self-loop).
        final relay = await _resolveRelay();
        final relayResult = RelayInjector.apply(withOverwrite, relay.profile);
        lastRelayResult = relayResult;
        withOverwrite = relayResult.config;

        processed = await ConfigTemplate.processInIsolate(
          withOverwrite,
          apiPort: _apiPort,
          secret: _apiSecret,
          connectionMode: connectionMode,
          desktopTunStack: desktopTunStack,
          tunBypassAddresses: tunBypassAddresses,
          tunBypassProcesses: tunBypassProcesses,
          relayHostWhitelist: relay.bypassHosts,
        );
        _apiPort = ConfigTemplate.getApiPort(processed);
        _mixedPort = ConfigTemplate.getMixedPort(processed);
        final parsedSecret = ConfigTemplate.getSecret(processed);
        if (parsedSecret != null && parsedSecret.isNotEmpty) {
          _apiSecret = parsedSecret;
        }
        _api = null;
        _stream = null;
        _clashCore = null;
        return 'len=${processed.length}, apiPort=$_apiPort';
      });

      await _step(steps, 'ensureGeo', StartupError.geoFilesFailed, () async {
        final installed = await GeoDataService.ensureFiles();
        return 'installed=$installed';
      });

      await _step(steps, 'startIosVpn', StartupError.coreStartFailed, () async {
        final ok = await vpn.VpnService.startIosVpn(configYaml: processed);
        // iOS 15 MB PacketTunnel cap: a 5 MB subscription becomes ~10 MB of
        // UTF-16 Dart heap plus a Swift copy plus a Go parse arena. Once the
        // extension has written its App Group file, the Dart-side string is
        // redundant — drop it immediately so the next Isolate.run / YAML
        // reparse doesn't re-amplify. length-report captured for logs before
        // clearing.
        final len = processed.length;
        processed = '';
        if (!ok) throw Exception('startIosVpn returned false');
        _running = true;
        return 'ok (freed ${len}B dart heap)';
      });

      // ── Step 3: waitApi (iOS) ──────────────────────────────────────
      // The Go core runs inside the PacketTunnel extension process.
      // Its REST API on 127.0.0.1:apiPort may take a moment to bind
      // after the VPN reports .connected. Poll until reachable.
      await _step(steps, 'waitApi', StartupError.apiTimeout, () async {
        // Same progressive backoff as the Android/desktop path — caps at
        // ~14s to accommodate slow extension starts on older iPhones.
        for (var i = 1; i <= 100; i++) {
          if (await api.isAvailable()) {
            return 'ready after $i attempts';
          }
          final waitMs = i <= 20 ? 50 : (i <= 50 ? 100 : 200);
          await Future.delayed(Duration(milliseconds: waitMs));
        }
        _running = false;
        throw Exception('API not available after 100 attempts (~14s)');
      });

      await _persistPorts();
      await _finishReport(steps, true, null);
      _pendingOperation?.complete();
      _pendingOperation = null;
      return true;
    } catch (e) {
      final failedName =
          steps.where((s) => !s.success).firstOrNull?.name ?? 'unknown';
      await _finishReport(steps, false, failedName);

      if (_running) {
        _running = false;
      }
      try {
        await vpn.VpnService.stopVpn();
      } catch (e) {
        debugPrint('[CoreManager] cleanup stopVpn after failed iOS start: $e');
      }

      _pendingOperation?.complete();
      _pendingOperation = null;
      rethrow;
    }
  }

  Future<bool> _startDesktopServiceMode(
    String configYaml,
    List<StartupStep> steps, {
    required String connectionMode,
    required String desktopTunStack,
    List<String> tunBypassAddresses = const [],
    List<String> tunBypassProcesses = const [],
  }) async {
    String processed = configYaml;
    String? homeDir;

    try {
      await _step(steps, 'ensureGeo', StartupError.geoFilesFailed, () async {
        final installed = await GeoDataService.ensureFiles();
        return 'installed=$installed';
      });

      await _step(steps, 'buildConfig', StartupError.configBuildFailed,
          () async {
        final appDir = await getApplicationSupportDirectory();
        homeDir = appDir.path;

        // A5a relay wiring on desktop service-mode path.
        final relay = await _resolveRelay();
        final withOverwrite =
            await _prepareConfig(configYaml, relayProfile: relay.profile);
        processed = await ConfigTemplate.processInIsolate(
          withOverwrite,
          apiPort: _apiPort,
          secret: _apiSecret,
          connectionMode: connectionMode,
          desktopTunStack: desktopTunStack,
          tunBypassAddresses: tunBypassAddresses,
          tunBypassProcesses: tunBypassProcesses,
          relayHostWhitelist: relay.bypassHosts,
        );
        _apiPort = ConfigTemplate.getApiPort(processed);
        _mixedPort = ConfigTemplate.getMixedPort(processed);
        final parsedSecret = ConfigTemplate.getSecret(processed);
        if (parsedSecret != null && parsedSecret.isNotEmpty) {
          _apiSecret = parsedSecret;
        }
        _api = null;
        _stream = null;
        _clashCore = null;
        return 'output=${processed.length}b, apiPort=$_apiPort, mixedPort=$_mixedPort, homeDir=$homeDir';
      });

      // Two-factor readiness: SCM registered (isInstalled) + HTTP listener
      // actually answering. Without the second factor, install() can return
      // success while the helper's listener is still binding, causing the
      // subsequent POST /v1/start to race and fail — the classic "user has
      // to refresh once before it connects" symptom. Matches FlClash's
      // `sc query RUNNING && ping` and CVR's `wait_for_service_ipc`.
      await _step(steps, 'waitService', StartupError.coreStartFailed, () async {
        for (var i = 0; i < 50; i++) {
          if (await ServiceClient.ping()) {
            return 'ready after ${i + 1} ping(s)';
          }
          await Future.delayed(const Duration(milliseconds: 200));
        }
        throw Exception(
            'service helper not answering ping after 10s — likely a cold '
            'install + Windows Defender / TUN driver init. Retry usually '
            'works once the helper has bound its listener.');
      });

      await _step(steps, 'startService', StartupError.coreStartFailed,
          () async {
        // Write the processed config to a file in homeDir BEFORE calling
        // the helper. The helper no longer accepts raw YAML over IPC — it
        // reads from the file path we hand it (which it validates against
        // its install-time path allowlist). This eliminates the previous
        // "client → root file write" attack surface.
        final configFile = File('$homeDir/yuelink-service.yaml');
        await configFile.parent.create(recursive: true);
        await configFile.writeAsString(processed);

        // One silent retry on first start — the helper may have passed
        // ping but mihomo subprocess spawn can still lose a race against
        // Windows' TUN driver registration on the very first connect.
        DesktopServiceInfo status;
        try {
          status = await ServiceClient.start(
            configPath: configFile.path,
            homeDir: homeDir!,
          );
        } catch (e) {
          debugPrint('[CoreManager] startService attempt-1 failed: $e — '
              'retrying once after 1.5 s warmup');
          await Future.delayed(const Duration(milliseconds: 1500));
          status = await ServiceClient.start(
            configPath: configFile.path,
            homeDir: homeDir!,
          );
        }
        _running = true;
        _serviceModeActive = true;
        return 'service OK, pid=${status.pid ?? 0}';
      });

      await _step(steps, 'waitApi', StartupError.apiTimeout, () async {
        // Windows cold-start budget: wintun.dll first-load + Defender scan
        // + mihomo process start + external-controller bind can push past
        // 10 s on older machines. Previous 5 s cap caused "install OK,
        // first connect fails, second connect works" — users had to click
        // twice because the app was racing the TUN driver. 150 × 100 ms
        // = 15 s matches the service install _waitUntilReachable ceiling
        // so the whole install→run flow has a consistent window.
        for (var i = 1; i <= 150; i++) {
          if (await api.isAvailable()) {
            return 'ready after $i attempts';
          }
          try {
            final status = await ServiceClient.status();
            if (!status.mihomoRunning) {
              throw Exception(
                  'service child stopped before API ready: ${status.lastError ?? status.lastExit ?? 'unknown'}');
            }
          } catch (e) {
            throw Exception('service helper unavailable while waiting API: $e');
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
        throw Exception('API not available after 150 attempts (15s)');
      });

      await _step(steps, 'verify', StartupError.coreDiedAfterStart, () async {
        final status = await ServiceClient.status();
        final apiOk = await api.isAvailable();

        if (!status.mihomoRunning) {
          throw Exception('service child is not running');
        }
        if (!apiOk) {
          throw Exception('API unavailable after startup');
        }

        final appDir = await getApplicationSupportDirectory();
        await File('${appDir.path}/$_kLastWorkingConfig')
            .writeAsString(processed);

        var info = 'serviceRunning=${status.mihomoRunning}, apiOk=$apiOk';
        try {
          final dns = await api.queryDns('google.com');
          final answers = dns['Answer'] as List?;
          info += ', dns=${answers?.length ?? 0}answers';
        } catch (e) {
          info += ', dnsErr=$e';
        }
        return info;
      });

      await _persistPorts();
      await _finishReport(steps, true, null);
      _pendingOperation?.complete();
      _pendingOperation = null;
      return true;
    } catch (e) {
      final failedName =
          steps.where((s) => !s.success).firstOrNull?.name ?? 'unknown';
      await _finishReport(steps, false, failedName);

      if (_running || _serviceModeActive) {
        _running = false;
        try {
          await ServiceClient.stop();
        } catch (stopError) {
          debugPrint(
              '[CoreManager] cleanup ServiceClient.stop() after failed desktop start: $stopError');
        }
      }
      _serviceModeActive = false;
      _pendingOperation?.complete();
      _pendingOperation = null;
      rethrow;
    }
  }

  // ==================================================================
  // Stop
  // ==================================================================

  Future<void> stop() async {
    if (!_running) return;

    // Wait for any pending start to complete before stopping
    if (_pendingOperation != null) {
      await _pendingOperation!.future;
    }
    if (!_running) return; // re-check after waiting
    _pendingOperation = Completer<void>();

    // Mark as stopped FIRST to prevent re-entry and ensure consistent state
    // even if the shutdown steps below crash or throw.
    _running = false;

    try {
      if (_serviceModeActive) {
        try {
          await api.closeAllConnections().timeout(const Duration(seconds: 2));
        } catch (e) {
          debugPrint('[CoreManager] closeAllConnections: $e');
        }
        await ServiceClient.stop();
        _serviceModeActive = false;
      } else {
        switch (_mode) {
          case CoreMode.mock:
            _core.stop();

          case CoreMode.ffi:
            // Close active connections with a timeout — the REST API may already
            // be unresponsive if the core is in a bad state.
            try {
              await api
                  .closeAllConnections()
                  .timeout(const Duration(seconds: 2));
            } catch (e) {
              debugPrint('[CoreManager] closeAllConnections: $e');
            }
            // On iOS, Go core runs in the PacketTunnel extension — FFI StopCore
            // only affects the main process (no-op). VPN stop is handled below.
            if (!Platform.isIOS) {
              try {
                _core.stop();
              } catch (e) {
                // FFI call can throw if Go runtime is in a bad state.
                // Catch to ensure VPN cleanup still happens below.
                debugPrint('[CoreManager] core.stop() error: $e');
              }
            }

          case CoreMode.subprocess:
            try {
              await api
                  .closeAllConnections()
                  .timeout(const Duration(seconds: 2));
            } catch (e) {
              debugPrint('[CoreManager] closeAllConnections: $e');
            }
            await ProcessManager.instance.stop();
        }
      }
    } catch (e) {
      debugPrint('[CoreManager] stop error: $e');
    }

    // Always stop VPN regardless of core stop result — the VPN service must
    // be cleaned up (notification removed, TUN fd closed) even if FFI crashed.
    if (Platform.isAndroid || Platform.isIOS) {
      // Small delay on Android to let Go runtime finish closing TUN fd
      // via executor.Shutdown() before we tear down the VPN service.
      if (Platform.isAndroid) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      try {
        await vpn.VpnService.stopVpn();
      } catch (e) {
        debugPrint('[CoreManager] stopVpn error: $e');
      }
    }

    _pendingOperation?.complete();
    _pendingOperation = null;
  }

  // ==================================================================
  // Helpers
  // ==================================================================

  static const _kLastWorkingConfig = 'last_working_config.yaml';

  /// Cryptographically random 256-bit token, URL-safe base64, no padding.
  /// Used once per install for the external-controller secret, then
  /// persisted via SettingsService.setClashApiSecret.
  static String _generateApiSecret() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<bool> _shouldUseDesktopServiceMode(String connectionMode) async {
    if (!ServiceManager.isSupported || isMockMode) return false;
    // ServiceManager.isSupported already gates by platform (mac/linux/win).
    // The previous extra `Platform.isMacOS || isWindows` clause silently
    // excluded Linux even though the install UI showed it as supported,
    // leaving Linux users with a "Service Mode installed" badge that did
    // nothing. Linux + Unix-socket helper is now first-class.
    if (!(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      return false;
    }
    if (connectionMode != 'tun') return false;
    return ServiceManager.isInstalled();
  }

  /// Phase 1B A5a: load persisted relay profile, run the cold-start
  /// selector, record what was picked. Returns the profile to actually
  /// inject for THIS start (null when direct was chosen) plus the
  /// fake-ip-filter bypass hosts the DNS template needs.
  ///
  /// Critically does NOT call [RelayProfileService.clear] when direct is
  /// selected — empty metrics (the default in 1B before probes land in
  /// A5b) makes the selector return direct unconditionally, so clearing
  /// would silently wipe the user's saved relay every cold-start.
  Future<({RelayProfile? profile, List<String> bypassHosts})>
      _resolveRelay() async {
    final outcome = await selectRelayForColdStart(
      persistedProfile: await RelayProfileService.load(),
    );
    lastSelectedKind = outcome.selectedKind;
    lastSelectedReason = outcome.selectedReason;
    return (
      profile: outcome.profile,
      bypassHosts: outcome.profile?.bypassHosts ?? const <String>[],
    );
  }

  Future<String> _prepareConfig(String configYaml,
      {RelayProfile? relayProfile}) async {
    final overwrite = await OverwriteService.load();
    var withOverwrite = OverwriteService.apply(configYaml, overwrite);

    final mitmPort = CoreController.instance.getMitmEnginePort();
    withOverwrite =
        await ModuleRuleInjector.inject(withOverwrite, mitmPort: mitmPort);

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
    // the soft-router `_upstream` still fronts everything else. The result
    // is captured for StartupReport / telemetry regardless of outcome.
    final relayResult = RelayInjector.apply(withOverwrite, relayProfile);
    lastRelayResult = relayResult;
    withOverwrite = relayResult.config;

    // Port-conflict check applies to all desktop platforms — Linux is now
    // a first-class desktop target via .deb / .rpm / AppImage releases.
    if ((Platform.isMacOS || Platform.isLinux || Platform.isWindows) &&
        !isMockMode) {
      final preferredMixed = ConfigTemplate.getMixedPort(withOverwrite);
      final ports = await Future.wait([
        _findAvailablePort(preferredMixed),
        _findAvailablePort(_apiPort),
      ]);
      final freeMixed = ports[0];
      final freeApi = ports[1];
      if (freeMixed != preferredMixed) {
        debugPrint(
            '[CoreManager] mixed-port $preferredMixed busy → remapped to $freeMixed');
        withOverwrite = ConfigTemplate.setMixedPort(withOverwrite, freeMixed);
      }
      if (freeApi != _apiPort) {
        debugPrint(
            '[CoreManager] apiPort $_apiPort busy → remapped to $freeApi');
        _apiPort = freeApi;
        _api = null;
        _stream = null;
        _clashCore = null;
      }
    }
    return withOverwrite;
  }

  Future<String?> loadLastWorkingConfig() async {
    final appDir = await getApplicationSupportDirectory();
    final file = File('${appDir.path}/$_kLastWorkingConfig');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// Run a single step with timing, errorCode, and structured recording.
  Future<void> _step(
    List<StartupStep> steps,
    String name,
    String errorCode,
    Future<String> Function() action,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final detail = await action();
      sw.stop();
      steps.add(StartupStep(
        name: name,
        success: true,
        detail: detail,
        durationMs: sw.elapsedMilliseconds,
      ));
      debugPrint('[CoreManager] ✓ $name (${sw.elapsedMilliseconds}ms) $detail');
    } catch (e) {
      sw.stop();
      steps.add(StartupStep(
        name: name,
        success: false,
        errorCode: errorCode,
        error: e.toString(),
        durationMs: sw.elapsedMilliseconds,
      ));
      debugPrint(
          '[CoreManager] ✗ $name [$errorCode] (${sw.elapsedMilliseconds}ms) $e');
      rethrow;
    }
  }

  /// Find a free TCP port starting from [preferred], trying up to 20 ports.
  /// Returns [preferred] if all attempts fail (let mihomo surface the error).
  static Future<int> _findAvailablePort(int preferred) async {
    for (var port = preferred; port < preferred + 20; port++) {
      try {
        final server = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
          shared: false,
        );
        await server.close();
        return port;
      } on SocketException {
        continue;
      }
    }
    return preferred;
  }

  /// Build the final report, read Go core logs, save to disk.
  Future<void> _finishReport(
    List<StartupStep> steps,
    bool success,
    String? failedStep,
  ) async {
    // Read Go-side core.log (written by logrus in InitCore)
    List<String> coreLogs = [];
    try {
      final appDir = await getApplicationSupportDirectory();
      final logFile = File('${appDir.path}/core.log');
      if (logFile.existsSync()) {
        final lines = await logFile.readAsLines();
        // Keep last 100 lines to avoid huge reports
        coreLogs =
            lines.length > 100 ? lines.sublist(lines.length - 100) : lines;
      }
    } catch (e) {
      debugPrint('[CoreManager] failed to read core.log: $e');
    }

    final report = StartupReport(
      timestamp: DateTime.now(),
      platform: Platform.operatingSystem,
      overallSuccess: success,
      steps: steps,
      failedStep: failedStep,
      coreLogs: coreLogs,
      relay: _relayReportFields(),
    );

    lastReport = report;
    debugPrint(report.toDebugString());

    // Telemetry — record aggregate outcome + which step failed.
    if (success) {
      final totalMs = steps.fold<int>(0, (a, s) => a + s.durationMs);
      Telemetry.event(
        TelemetryEvents.startupOk,
        props: {'total_ms': totalMs, 'steps': steps.length},
      );
    } else {
      Telemetry.event(
        TelemetryEvents.startupFail,
        priority: true,
        props: {
          'step': failedStep ?? 'unknown',
          'code': _errorCodeFor(failedStep),
        },
      );
    }

    // Save to disk (fire-and-forget)
    StartupReport.save(report);
  }

  /// Build the relay block for StartupReport.
  /// Returns null only when the selector has never run (e.g. before the
  /// first start). Once A5a wired the selector into every start path,
  /// every successful or failed start records its selectedKind /
  /// selectedReason here — telemetry sees the consistent shape.
  Map<String, dynamic>? _relayReportFields() {
    final r = lastRelayResult;
    final kind = lastSelectedKind;
    if (r == null && kind == null) return null;
    return {
      if (r != null) 'injected': r.injected,
      if (r != null && r.targetCount > 0) 'targetCount': r.targetCount,
      if (r != null && r.skipReason != null) 'skipReason': r.skipReason,
      if (kind != null) 'selectedKind': kind.name,
      if (lastSelectedReason != null) 'selectedReason': lastSelectedReason,
    };
  }

  /// Stable error codes for dashboard grouping. Mirrors the E002–E009
  /// constants rendered in StartupErrorBanner.
  static String _errorCodeFor(String? step) {
    switch (step) {
      case 'initCore':
        return 'E002';
      case 'vpnPermission':
        return 'E003';
      case 'startVpn':
        return 'E004';
      case 'buildConfig':
        return 'E005';
      case 'startCore':
        return 'E006';
      case 'waitApi':
        return 'E007';
      case 'verify':
        return 'E008';
      case 'ensureGeo':
        return 'E009';
      default:
        return 'Exx';
    }
  }
}
