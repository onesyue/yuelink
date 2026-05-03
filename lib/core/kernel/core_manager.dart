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
import 'startup_config_builder.dart' as cfg;
import 'startup_diagnostics.dart' as diag;
import 'config_template.dart';
import 'geodata_service.dart';
import '../../infrastructure/datasources/mihomo_api.dart';
import '../../infrastructure/datasources/mihomo_stream.dart';
import '../relay/network_profile.dart';
import '../relay/network_profile_service.dart';
import '../relay/relay_candidate.dart';
import '../relay/relay_metrics.dart';
import '../relay/relay_probe_service.dart';
import '../relay/relay_selection.dart';
import '../relay/relay_telemetry.dart';
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

// Service-mode startup logic lives in a part file so it can mutate
// CoreManager's private state (`_apiPort`, `_running`,
// `_serviceModeActive`, `_pendingOperation`, …) without exposing those
// fields to the rest of the codebase. Logically the same class; physically
// split because the desktop helper-subprocess flow was 213 lines on its own.
part 'desktop_service_mode.dart';

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
    _instance?._relayMetrics.clear();
    _instance?._cachedNetworkProfile = null;
    _instance?._networkProfileCacheLoaded = false;
    _instance?._networkProfileService = null;
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

  /// True while [start] is mid-flight (between port remap and verify).
  /// Read by [markRunning] to skip the persistence-based port restore,
  /// which would otherwise stomp the just-remapped in-memory `_apiPort`
  /// with the previous run's persisted value if a resume event lands
  /// during startup. See macOS startup_fail report 2026-04-28 — port
  /// 9090 busy → remapped to 9091, resume mid-startup re-restored 9090
  /// from persistence, all subsequent api/stream traffic hit the wrong
  /// port → verify failed with E008.
  ///
  /// Also read by AppResumeController.run() to skip the entire resume
  /// handler. During start(), in-memory `userStoppedProvider` is the
  /// authoritative value (CoreLifecycleManager.start() sets it to
  /// `false` synchronously), but the matching `setManualStopped(false)`
  /// disk write is async. A resume event landing in that window would
  /// read the still-stale persisted `true`, hydrate userStoppedProvider
  /// back to true, and `displayCoreStatusProvider` would surface
  /// `stopped` after a successful start — UI showed "未连接" with
  /// mihomo actually running.
  bool _startInFlight = false;
  bool get isStartInFlight => _startInFlight;

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

  /// Singleton metrics buffer shared across every start in this process
  /// session. The cold-start selector reads it; the post-start
  /// background probe writes to it. Memory-only in Phase 1B — the
  /// SettingsService persistence layer is deferred. Final field cleared
  /// (not replaced) by [resetForTesting].
  final RelayMetrics _relayMetrics = RelayMetrics();

  @visibleForTesting
  RelayMetrics get relayMetricsForTest => _relayMetrics;

  /// Cached most-recent [NetworkProfile] sample. Lazy-loaded from
  /// SettingsService on first sample call; refreshed in the background
  /// after every successful start when older than [_kNetworkProfileTtl].
  /// Decisions never branch on this — it's pure telemetry input for the
  /// Super-Peer feasibility study.
  NetworkProfile? _cachedNetworkProfile;
  bool _networkProfileCacheLoaded = false;
  NetworkProfileService? _networkProfileService;
  static const _kNetworkProfileTtl = Duration(hours: 6);
  static const _kNetworkProfileCacheKey = 'networkProfileCache';

  @visibleForTesting
  NetworkProfile? get cachedNetworkProfileForTest => _cachedNetworkProfile;

  MihomoApi get api =>
      _api ??= MihomoApi(host: '127.0.0.1', port: _apiPort, secret: _apiSecret);

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
  ///
  /// If [start] is mid-flight (`_startInFlight == true`), the entire body
  /// is a no-op — the active start path is the authoritative state writer
  /// and `markRunning` would otherwise race it three different ways:
  ///   1. flipping `_running=true` between `_stopUnlocked` (sets false)
  ///      and `_startUnlocked` calling `manager.start()` would short-
  ///      circuit the start at `if (_running) return true;` — Dart
  ///      thinks core is up but no real start ran (TUN never installed
  ///      its routes, helper service never spawned mihomo);
  ///   2. recomputing `_serviceModeActive` from persisted settings would
  ///      override the in-flight start's just-decided value;
  ///   3. nulling `_api`/`_stream` mid-startup would force the next
  ///      ConfigTemplate.processInIsolate to rebuild against possibly
  ///      stale port discovery. The skip mirrors the existing
  ///      `_startInFlight` guard around port restore that fixed the
  ///      remapped-port-stomped-by-persisted-port bug.
  Future<void> markRunning() async {
    if (_startInFlight) return;

    _running = true;
    final savedConnectionMode = await SettingsService.getConnectionMode();
    // Mirror _shouldUseDesktopServiceMode platform list — Linux is now
    // a first-class service mode platform, not silently excluded.
    _serviceModeActive =
        ServiceManager.isSupported &&
        (Platform.isMacOS || Platform.isLinux || Platform.isWindows) &&
        savedConnectionMode == 'tun' &&
        await ServiceManager.isInstalled();
    // Restore ports from persisted settings (engine restart loses Dart state).
    final savedApiPort = await SettingsService.get<int>('lastApiPort');
    final savedMixedPort = await SettingsService.get<int>('lastMixedPort');
    if (savedApiPort != null) _apiPort = savedApiPort;
    if (savedMixedPort != null) _mixedPort = savedMixedPort;
    // Recreate API/stream clients with the restored ports.
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
    String quicRejectPolicy = ConfigTemplate.defaultQuicRejectPolicy,
  }) async {
    debugPrint('[CoreManager] ══════ START ══════');
    if (_running) return true;

    // Wait for any pending start/stop to complete before proceeding
    if (_pendingOperation != null) {
      await _pendingOperation!.future;
    }
    if (_running) return true; // re-check after waiting
    _pendingOperation = Completer<void>();
    _startInFlight = true;

    // Everything below must be inside the try so the catch handler always
    // completes _pendingOperation — even if SettingsService throws before
    // the first _step runs. Otherwise future start/stop calls await a
    // Completer that will never resolve and the app wedges (regression
    // guard added after a session that lost this invariant).
    final steps = <StartupStep>[];
    String? homeDir;

    try {
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

      // iOS: separate process, different path
      if (Platform.isIOS && !isMockMode) {
        return _startIos(
          configYaml,
          steps,
          connectionMode: connectionMode,
          desktopTunStack: desktopTunStack,
          tunBypassAddresses: tunBypassAddresses,
          tunBypassProcesses: tunBypassProcesses,
          quicRejectPolicy: quicRejectPolicy,
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
          quicRejectPolicy: quicRejectPolicy,
        );
      }
      _serviceModeActive = false;

      // ── Steps 1+2: ensureGeo + initCore (parallelized) ─────────────
      // These steps are independent — geo files don't need the core, and
      // core init doesn't need geo files. Running in parallel saves
      // 100-500ms on first launch or when CDN fallback is needed.
      await Future.wait([
        diag.runStartupStep(steps, 'ensureGeo', StartupError.geoFilesFailed, () async {
          final installed = await GeoDataService.ensureFiles();
          return 'installed=$installed';
        }),
        diag.runStartupStep(steps, 'initCore', StartupError.initCoreFailed, () async {
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
        await diag.runStartupStep(
          steps,
          'vpnPermission',
          StartupError.vpnPermissionDenied,
          () async {
            final granted = await vpn.VpnService.requestPermission();
            if (!granted) {
              throw Exception('user denied VPN permission');
            }
            return 'granted';
          },
        );
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
        await diag.runStartupStep(steps, 'startVpn', StartupError.vpnFdInvalid, () async {
          configFuture = prepareConfig();
          final rawMp = ConfigTemplate.getMixedPort(configYaml);
          tunFd = await vpn.VpnService.startAndroidVpn(mixedPort: rawMp);
          if (tunFd == null || tunFd! <= 0) {
            throw Exception('fd=$tunFd (expected > 0)');
          }
          return 'fd=$tunFd, mixedPort=$rawMp';
        });

        await diag.runStartupStep(
          steps,
          'buildConfig',
          StartupError.configBuildFailed,
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
              quicRejectPolicy: quicRejectPolicy,
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
          },
        );
      } else {
        // Non-Android: sequential (no VPN step)
        await diag.runStartupStep(
          steps,
          'buildConfig',
          StartupError.configBuildFailed,
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
              quicRejectPolicy: quicRejectPolicy,
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
          },
        );
      }

      // ── Step 6: startCore (Go hub.Parse) ───────────────────────────
      await diag.runStartupStep(steps, 'startCore', StartupError.coreStartFailed, () async {
        // Write config to disk for debugging (atomic tmp+rename)
        debugPrint('[CoreManager] startCore: writing config to disk...');
        final appDir = await getApplicationSupportDirectory();
        final configFile = File(
          '${appDir.path}/${AppConstants.configFileName}',
        );
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
              '[CoreManager] startCore: calling StartCore FFI (may take 1-3s)...',
            );
            final error = await _core.startAsync(processed);
            debugPrint('[CoreManager] startCore: StartCore returned: $error');
            if (error != null && error.isNotEmpty) throw Exception(error);
            _running = true;
            final goRunning = _core.isRunning;
            return 'ffi OK, isRunning=$goRunning';

          case CoreMode.subprocess:
            final path = await ProcessManager.writeConfig(processed);
            final ok = await ProcessManager.instance.start(
              configPath: path,
              apiPort: _apiPort,
            );
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
      await diag.runStartupStep(steps, 'waitApi', StartupError.apiTimeout, () async {
        if (isMockMode) return 'skip (mock)';
        for (var i = 1; i <= 100; i++) {
          // Fast-fail: if Go core died (panic / crash after StartCore returned),
          // stop polling immediately instead of waiting the full timeout.
          if (!_core.isRunning) {
            throw Exception(
              'Core is no longer running at attempt $i — check core.log for crash/parse details',
            );
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
        throw Exception(
          'API not available after 100 attempts (~14s): '
          'isRunning=$goRunning, $portState',
        );
      });

      // ── Step 7.5: waitProxies (v1.0.22 P0-2) ───────────────────────
      // /version answering is not enough — mihomo binds the REST
      // listener before parsing the config and stitching the proxy
      // graph. testGroupDelay landing in this window saw an empty
      // /proxies and painted everything red. See _waitProxiesReady.
      await diag.runStartupStep(steps, 'waitProxies', StartupError.apiTimeout, () async {
        if (isMockMode) return 'skip (mock)';
        return await _waitProxiesReady();
      });

      // ── Step 8: verify ─────────────────────────────────────────────
      await diag.runStartupStep(steps, 'verify', StartupError.coreDiedAfterStart, () async {
        if (isMockMode) return 'skip (mock)';
        final goRunning = _core.isRunning;
        final apiOk = await api.isAvailable();

        if (!goRunning) throw Exception('isRunning=false');
        if (!apiOk) throw Exception('API unavailable after startup');

        // Save known-good config
        final appDir = await getApplicationSupportDirectory();
        await File(
          '${appDir.path}/$_kLastWorkingConfig',
        ).writeAsString(processed);

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
      // A5b: kick off the background probe AFTER finishReport so the
      // current start's report is finalised first. Fire-and-forget by
      // design — probe results land in metrics for the NEXT start, not
      // this one.
      unawaited(_backgroundProbe());
      // A5c-2: sample the client-side network profile (IPv6/NAT/medium)
      // — also fire-and-forget. No-ops when the cached sample is younger
      // than 6h, so users restarting frequently don't get sampled
      // repeatedly.
      unawaited(_backgroundNetworkSample());
      return true;
    } catch (e) {
      final failedName =
          steps.where((s) => !s.success).firstOrNull?.name ?? 'unknown';
      // Wrap the report write so an exception inside finishReport (disk
      // full, JSON serialization edge case, settings IO failure) doesn't
      // bypass the cleanup-and-guard-clear path below.
      try {
        await _finishReport(steps, false, failedName);
      } catch (e2) {
        debugPrint('[CoreManager] _finishReport during catch failed: $e2');
      }

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
            '[CoreManager] cleanup core.stop() after failed start: $e',
          );
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

      rethrow;
    } finally {
      // Guard-clear must run even if _finishReport / cleanup throws —
      // otherwise the next caller awaits a Completer that never
      // resolves and the app wedges, AND AppResumeController's
      // `if (CoreManager.instance.isStartInFlight) return` blocks
      // every subsequent resume tick. finally is the only safe site.
      _pendingOperation?.complete();
      _pendingOperation = null;
      _startInFlight = false;
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
    String quicRejectPolicy = ConfigTemplate.defaultQuicRejectPolicy,
  }) async {
    String processed = configYaml;

    try {
      await diag.runStartupStep(
        steps,
        'buildConfig_ios',
        StartupError.configBuildFailed,
        () async {
          final overwrite = await OverwriteService.load();
          var withOverwrite = OverwriteService.apply(configYaml, overwrite);

          // [ModuleRuntime] inject enabled module rules (+ MITM routing if engine running)
          final mitmPort = CoreController.instance.getMitmEnginePort();
          withOverwrite = await ModuleRuleInjector.inject(
            withOverwrite,
            mitmPort: mitmPort,
          );

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
            quicRejectPolicy: quicRejectPolicy,
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
        },
      );

      await diag.runStartupStep(steps, 'ensureGeo', StartupError.geoFilesFailed, () async {
        final installed = await GeoDataService.ensureFiles();
        return 'installed=$installed';
      });

      await diag.runStartupStep(steps, 'startIosVpn', StartupError.coreStartFailed, () async {
        final ok = await vpn.VpnService.startIosVpn(configYaml: processed);
        // iOS PacketTunnel runs under a ~50 MB cap on iOS 15+ (Apple raised
        // it from the 14-era ~15 MB; Apple Dev Forums #106377). A 5 MB
        // subscription still becomes ~10 MB of UTF-16 Dart heap plus a
        // Swift copy plus a Go parse arena, so we keep the existing
        // amplification fix: once the extension has written its App Group
        // file, the Dart-side string is redundant — drop it immediately so
        // the next Isolate.run / YAML reparse doesn't re-amplify.
        // length-report captured for logs before clearing.
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
      await diag.runStartupStep(steps, 'waitApi', StartupError.apiTimeout, () async {
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

      // ── Step 3.5: waitProxies (v1.0.22 P0-2, iOS) ─────────────────
      // PacketTunnel-extension mihomo has the same /version-vs-/proxies
      // gap. See _waitProxiesReady.
      await diag.runStartupStep(steps, 'waitProxies', StartupError.apiTimeout, () async {
        return await _waitProxiesReady();
      });

      await _persistPorts();
      await _finishReport(steps, true, null);
      // A5b: kick off the background probe AFTER finishReport so the
      // current start's report is finalised first. Fire-and-forget by
      // design — probe results land in metrics for the NEXT start, not
      // this one.
      unawaited(_backgroundProbe());
      // A5c-2: sample the client-side network profile (IPv6/NAT/medium)
      // — also fire-and-forget. No-ops when the cached sample is younger
      // than 6h, so users restarting frequently don't get sampled
      // repeatedly.
      unawaited(_backgroundNetworkSample());
      return true;
    } catch (e) {
      final failedName =
          steps.where((s) => !s.success).firstOrNull?.name ?? 'unknown';
      // Wrap the report write — see outer start() for the same rationale.
      try {
        await _finishReport(steps, false, failedName);
      } catch (e2) {
        debugPrint('[CoreManager] _finishReport during iOS catch failed: $e2');
      }

      if (_running) {
        _running = false;
      }
      try {
        await vpn.VpnService.stopVpn();
      } catch (e) {
        debugPrint('[CoreManager] cleanup stopVpn after failed iOS start: $e');
      }

      rethrow;
    } finally {
      // See outer start()'s finally for rationale: the resume-controller
      // path checks `isStartInFlight` and is silently blocked until this
      // flag clears, so any code path that bypasses it (an exception in
      // _finishReport / persistPorts) wedges resume permanently.
      _pendingOperation?.complete();
      _pendingOperation = null;
      _startInFlight = false;
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
              await api.closeAllConnections().timeout(
                const Duration(seconds: 2),
              );
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
              await api.closeAllConnections().timeout(
                const Duration(seconds: 2),
              );
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
      // A5b: pass the singleton metrics so probe results from prior
      // starts actually influence the current selection. Empty on first
      // start of the session → selector falls back to direct, same as
      // A5a behaviour.
      metrics: _relayMetrics,
    );
    lastSelectedKind = outcome.selectedKind;
    lastSelectedReason = outcome.selectedReason;
    // A5c-1: emit one selected event per start path. Always fires —
    // direct selection still produces a row so the dashboard sees the
    // baseline distribution, not a sampling skewed toward relay picks.
    Telemetry.event(
      TelemetryEvents.relaySelected,
      props: RelayTelemetry.selected(
        outcome.selectedKind,
        outcome.selectedReason,
      ),
    );
    return (
      profile: outcome.profile,
      bypassHosts: outcome.profile?.bypassHosts ?? const <String>[],
    );
  }

  /// A5b: probes the persisted commercial relay (if any) and writes the
  /// outcome to [_relayMetrics] so the NEXT cold-start can see it.
  /// Fire-and-forget from a successful start — never blocks return,
  /// never affects this start. Only persisted commercial profiles get
  /// probed; direct candidates use placeholder host/port that would
  /// produce garbage data, so they stay unprobed (their absence from
  /// metrics keeps the selector's conservative bias on direct, which is
  /// the right default when there's nothing real to compare against).
  Future<void> _backgroundProbe() async {
    try {
      final persisted = await RelayProfileService.load();
      if (persisted == null || !persisted.isValid) return;
      final candidate = RelayCandidate.commercial(persisted);
      final svc = DefaultRelayProbeService();
      final result = await svc.probe(candidate);
      _relayMetrics.record(candidate.id, result);
      // A5c-1: emit one probe event per actual probe run. Skipped probes
      // (no persisted profile) deliberately produce no event — silence
      // means "nothing to measure", which the dashboard reads correctly.
      Telemetry.event(
        TelemetryEvents.relayProbe,
        props: RelayTelemetry.probe(candidate, result),
      );
    } catch (e) {
      debugPrint('[CoreManager] background probe failed: $e');
    }
  }

  /// A5c-2: samples client-side network profile once per [_kNetworkProfileTtl]
  /// window, persists to SettingsService, emits a network_profile_sample
  /// event. Lazy-loads the cache on first call so cold-start latency
  /// isn't impacted; subsequent starts within the TTL do nothing.
  Future<void> _backgroundNetworkSample() async {
    try {
      // Lazy-load cache on first call this session.
      if (!_networkProfileCacheLoaded) {
        _networkProfileCacheLoaded = true;
        try {
          final settings = await SettingsService.load();
          final raw = settings[_kNetworkProfileCacheKey];
          if (raw is Map) {
            _cachedNetworkProfile = NetworkProfile.fromJson(
              Map<String, dynamic>.from(raw),
            );
          }
        } catch (_) {
          // Cache corruption isn't fatal — just resample.
        }
      }

      // Skip if cache is fresh.
      final cached = _cachedNetworkProfile;
      if (cached != null) {
        final age = DateTime.now().difference(cached.sampledAt);
        if (age < _kNetworkProfileTtl) return;
      }

      _networkProfileService ??= NetworkProfileService.production();
      final profile = await _networkProfileService!.sample();
      _cachedNetworkProfile = profile;

      Telemetry.event(
        TelemetryEvents.networkProfileSample,
        props: RelayTelemetry.networkProfileSample(profile),
      );

      // Persist for cross-restart cache hits within the TTL.
      try {
        await SettingsService.set(_kNetworkProfileCacheKey, profile.toJson());
      } catch (_) {
        // Persistence failure is non-fatal — telemetry already fired,
        // and the next start will just sample again.
      }
    } catch (e) {
      debugPrint('[CoreManager] background network sample failed: $e');
    }
  }

  /// Run the config-build pipeline (overwrite → MITM rules → upstream
  /// proxy → relay injector → port rebind) and capture the relay result
  /// onto [lastRelayResult]. The actual logic lives in
  /// `lib/core/kernel/startup_config_builder.dart`; this delegate
  /// keeps the CoreManager state side-effects (port invalidation,
  /// `_apiPort`, `_api` / `_stream` / `_clashCore` reset, `lastRelayResult`)
  /// next to the rest of CoreManager's bookkeeping.
  Future<String> _prepareConfig(
    String configYaml, {
    RelayProfile? relayProfile,
  }) async {
    final result = await cfg.buildStartConfig(
      configYaml: configYaml,
      currentApiPort: _apiPort,
      isMockMode: isMockMode,
      relayProfile: relayProfile,
    );
    lastRelayResult = result.relayResult;
    if (result.apiPort != _apiPort) {
      _apiPort = result.apiPort;
      _api = null;
      _stream = null;
      _clashCore = null;
    }
    return result.yaml;
  }

  Future<String?> loadLastWorkingConfig() async {
    final appDir = await getApplicationSupportDirectory();
    final file = File('${appDir.path}/$_kLastWorkingConfig');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  // _step / _finishReport / _relayReportFields / _errorCodeFor moved to
  // lib/core/kernel/startup_diagnostics.dart. Call sites use
  // `diag.runStartupStep(...)` directly; report finalisation now goes
  // through [_finishReport] below as a thin delegate that hydrates the
  // relay-block from CoreManager state.

  /// Poll `/proxies` until the proxy graph is materialised (not just
  /// `/version` answering). v1.0.22 P0-2 root fix for "测速全红": the
  /// previous startup gated only on `/version`, but mihomo binds the
  /// REST listener before it finishes parsing the config and building
  /// the selector groups. A `testGroupDelay` call landing in that
  /// window saw an empty `/proxies` and returned every node as
  /// timed-out, painting the whole group red.
  ///
  /// Polls 100 ms × 150 attempts = 15 s cap. Larger than `/version`'s
  /// readiness window because parse-and-graph-build dominates on huge
  /// subscriptions; subscriptions with `proxy-providers` that fetch
  /// from the network can legitimately take 5–10 s before the graph
  /// is materialised. On mock mode, the caller skips this step entirely.
  ///
  /// Soft timeout: if 15 s passes and the graph is still empty, this
  /// returns `'slow'` instead of throwing. The API is up (otherwise
  /// `waitApi` would have failed earlier), so the core IS running —
  /// only the provider sync is pending. Failing startup here was a
  /// regression: users with valid configs saw `[E007] waitProxies`
  /// red banners while the app actually worked. The dashboard's own
  /// async refreshers fill in the graph as soon as it lands.
  Future<String> _waitProxiesReady() async {
    final sw = Stopwatch()..start();
    for (var i = 1; i <= 150; i++) {
      try {
        final payload = await api.getProxies();
        if (isProxiesPayloadReady(payload)) {
          return 'ready (${sw.elapsedMilliseconds}ms, $i attempts)';
        }
      } catch (_) {
        // /proxies may 404/5xx during early init — keep polling.
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    debugPrint(
      '[CoreManager] waitProxies: graph still empty after 15s — '
      'continuing anyway (likely slow proxy-providers / rule-providers)',
    );
    return 'slow (provider sync pending after 15s)';
  }

  // _findAvailablePort moved to lib/core/kernel/startup_config_builder.dart
  // (now `cfg.findAvailablePort`); used by _prepareConfig's port-rebind path.

  /// Thin delegate to [diag.buildAndPersistStartupReport] that hydrates
  /// the relay-block from CoreManager's relay-state fields, captures the
  /// returned report onto [lastReport] for the UI, and emits the
  /// success / failure telemetry. Body lives in startup_diagnostics.dart.
  Future<void> _finishReport(
    List<StartupStep> steps,
    bool success,
    String? failedStep,
  ) async {
    final report = await diag.buildAndPersistStartupReport(
      steps: steps,
      success: success,
      failedStep: failedStep,
      relayReportFields: diag.buildRelayReportFields(
        lastRelayResult: lastRelayResult,
        lastSelectedKind: lastSelectedKind,
        lastSelectedReason: lastSelectedReason,
      ),
    );
    lastReport = report;
  }
}

/// True iff the `/proxies` payload represents a fully-built proxy graph,
/// not just an empty shell mihomo returns while the config is still
/// being parsed. Top-level pure function so the readiness rule can be
/// unit-tested without spinning up a real CoreManager.
///
/// "Ready" means:
///   - `proxies` map exists and is non-empty
///   - AND either:
///       * `GLOBAL` group exists with a non-empty `all` list (the
///         primary signal — mihomo materialises GLOBAL last, so a
///         populated GLOBAL is the strongest "graph done" indicator), OR
///       * at least one non-GLOBAL entry has a non-empty `all` list
///         (the fallback — some configs strip GLOBAL outright).
///
/// Just `containsKey('GLOBAL')` is NOT enough: mihomo briefly emits
/// `'GLOBAL': {}` or `'GLOBAL': {'all': []}` early in the build window,
/// and the original predicate's existence-only check let a `/proxies`
/// payload through before the graph was actually populated.
bool isProxiesPayloadReady(Map<String, dynamic>? payload) {
  if (payload == null) return false;
  final proxies = payload['proxies'];
  if (proxies is! Map || proxies.isEmpty) return false;

  final global = proxies['GLOBAL'];
  if (global is Map) {
    final all = global['all'];
    if (all is List && all.isNotEmpty) return true;
    // GLOBAL exists but `all` is empty / missing / wrong-type — fall
    // through to the fallback rather than declaring ready. The
    // GLOBAL-empty window is exactly when the rest of the graph is
    // still being stitched.
  }

  for (final entry in proxies.entries) {
    if (entry.key == 'GLOBAL') continue; // already considered above
    final v = entry.value;
    if (v is Map) {
      final all = v['all'];
      if (all is List && all.isNotEmpty) return true;
    }
  }
  return false;
}
