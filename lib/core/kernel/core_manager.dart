import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../constants.dart';
import '../ffi/core_controller.dart';
import '../../domain/models/startup_report.dart';
import 'config_template.dart';
import 'geodata_service.dart';
import '../../infrastructure/datasources/mihomo_api.dart';
import '../../infrastructure/datasources/mihomo_stream.dart';
import '../../services/overwrite_service.dart';
import '../../services/process_manager.dart';
import '../storage/settings_service.dart';
import '../platform/vpn_service.dart' as vpn;

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

  late final CoreController _core;
  late CoreMode _mode;
  MihomoApi? _api;
  MihomoStream? _stream;
  bool _running = false;
  bool _initialized = false;

  /// Guards against concurrent start/stop calls.
  Completer<void>? _pendingOperation;

  /// The most recent startup report (kept in memory for UI).
  StartupReport? lastReport;

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
    if (isMockMode) return _running;
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
    // Restore ports from persisted settings (engine restart loses Dart state)
    final savedApiPort = await SettingsService.get<int>('lastApiPort');
    final savedMixedPort = await SettingsService.get<int>('lastMixedPort');
    if (savedApiPort != null) _apiPort = savedApiPort;
    if (savedMixedPort != null) _mixedPort = savedMixedPort;
    // Recreate API/stream clients with restored ports
    _api = null;
    _stream = null;
  }

  /// Persist current ports so they can be restored after engine restart.
  Future<void> _persistPorts() async {
    await SettingsService.set('lastApiPort', _apiPort);
    await SettingsService.set('lastMixedPort', _mixedPort);
  }
  int _mixedPort = 7890;

  void configure({int? port, String? secret, CoreMode? mode}) {
    if (port != null) _apiPort = port;
    _apiSecret = secret;
    if (mode != null) _mode = mode;
    _api = null;
    _stream = null;
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

  Future<bool> start(String configYaml) async {
    debugPrint('[CoreManager] ══════ START ══════');
    if (_running) return true;

    // Wait for any pending start/stop to complete before proceeding
    if (_pendingOperation != null) {
      await _pendingOperation!.future;
    }
    if (_running) return true; // re-check after waiting
    _pendingOperation = Completer<void>();

    final steps = <StartupStep>[];
    String? homeDir;

    try {
      // iOS: separate process, different path
      if (Platform.isIOS && !isMockMode) {
        return _startIos(configYaml, steps);
      }

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

      // Pre-compute config overwrite layer while VPN fd is being obtained.
      Future<String> prepareConfig() async {
        final overwrite = await OverwriteService.load();
        var withOverwrite = OverwriteService.apply(configYaml, overwrite);

        final upstream = await SettingsService.getUpstreamProxy();
        if (upstream != null && (upstream['server'] as String).isNotEmpty) {
          withOverwrite = ConfigTemplate.injectUpstreamProxy(
            withOverwrite,
            upstream['type'] as String,
            upstream['server'] as String,
            upstream['port'] as int,
          );
        }

        if ((Platform.isMacOS || Platform.isWindows) && !isMockMode) {
          final preferredMixed = ConfigTemplate.getMixedPort(withOverwrite);
          final ports = await Future.wait([
            _findAvailablePort(preferredMixed),
            _findAvailablePort(_apiPort),
          ]);
          final freeMixed = ports[0];
          final freeApi = ports[1];
          if (freeMixed != preferredMixed) {
            debugPrint('[CoreManager] mixed-port $preferredMixed busy → remapped to $freeMixed');
            withOverwrite = ConfigTemplate.setMixedPort(withOverwrite, freeMixed);
          }
          if (freeApi != _apiPort) {
            debugPrint('[CoreManager] apiPort $_apiPort busy → remapped to $freeApi');
            _apiPort = freeApi;
            _api = null;
            _stream = null;
          }
        }
        return withOverwrite;
      }

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
          processed = ConfigTemplate.process(
            withOverwrite,
            apiPort: _apiPort,
            secret: _apiSecret,
            tunFd: tunFd,
          );
          _apiPort = ConfigTemplate.getApiPort(processed);
          _mixedPort = ConfigTemplate.getMixedPort(processed);
          _apiSecret ??= ConfigTemplate.getSecret(processed);
          _api = null;
          _stream = null;
          return 'output=${processed.length}b, apiPort=$_apiPort, mixedPort=$_mixedPort, tunFd=$tunFd';
        });
      } else {
        // Non-Android: sequential (no VPN step)
        await _step(steps, 'buildConfig', StartupError.configBuildFailed,
            () async {
          final withOverwrite = await prepareConfig();
          processed = ConfigTemplate.process(
            withOverwrite,
            apiPort: _apiPort,
            secret: _apiSecret,
            tunFd: tunFd,
          );
          _apiPort = ConfigTemplate.getApiPort(processed);
          _mixedPort = ConfigTemplate.getMixedPort(processed);
          _apiSecret ??= ConfigTemplate.getSecret(processed);
          _api = null;
          _stream = null;
          return 'output=${processed.length}b, apiPort=$_apiPort, mixedPort=$_mixedPort';
        });
      }

      // ── Step 6: startCore (Go hub.Parse) ───────────────────────────
      await _step(steps, 'startCore', StartupError.coreStartFailed, () async {
        // Write config to disk for debugging
        debugPrint('[CoreManager] startCore: writing config to disk...');
        final appDir = await getApplicationSupportDirectory();
        await File('${appDir.path}/${AppConstants.configFileName}')
            .writeAsString(processed);

        switch (_mode) {
          case CoreMode.mock:
            final error = _core.start(processed);
            if (error != null && error.isNotEmpty) throw Exception(error);
            _running = true;
            return 'mock started';

          case CoreMode.ffi:
            debugPrint('[CoreManager] startCore: calling StartCore FFI (may take 1-3s)...');
            final error = await _core.startAsync(processed);
            debugPrint('[CoreManager] startCore: StartCore returned: $error');
            if (error != null && error.isNotEmpty) throw Exception(error);
            _running = true;
            final goRunning = _core.isRunning;
            return 'ffi OK, isRunning=$goRunning';

          case CoreMode.subprocess:
            final path = await ProcessManager.writeConfig(processed);
            final ok = await ProcessManager.instance.start(
                configPath: path, apiPort: _apiPort);
            if (!ok) throw Exception('subprocess start failed');
            _running = true;
            return 'subprocess OK';
        }
      });

      // ── Step 7: waitApi ────────────────────────────────────────────
      await _step(steps, 'waitApi', StartupError.apiTimeout, () async {
        if (isMockMode) return 'skip (mock)';
        for (var i = 1; i <= 50; i++) {
          // Fast-fail: if Go core died (panic / crash after StartCore returned),
          // stop polling immediately instead of waiting the full 5s.
          if (!_core.isRunning) {
            throw Exception(
                'Core is no longer running at attempt $i — check core.log for crash/parse details');
          }
          if (await api.isAvailable()) {
            return 'ready after $i attempts';
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
        // All 50 attempts exhausted. Gather diagnostics before throwing.
        final goRunning = _core.isRunning;
        String portState;
        try {
          final sock = await Socket.connect(
            '127.0.0.1', _apiPort,
            timeout: const Duration(milliseconds: 300),
          );
          sock.destroy();
          portState = 'port $_apiPort IS listening (HTTP not responding — secret mismatch or non-200?)';
        } on SocketException catch (e) {
          portState = 'port $_apiPort NOT listening (${e.osError?.message ?? e.message}) '
              '— external-controller may not have started (config parse failed/fallback?)';
        } catch (e) {
          portState = 'port $_apiPort probe error: $e';
        }
        _running = false;
        _core.stop();
        throw Exception(
            'API not available after 50 attempts (5s): '
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
          if (!Platform.isIOS) _core.stop();
        } catch (e) {
          debugPrint('[CoreManager] cleanup core.stop() after failed start: $e');
        }
      }
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

  Future<bool> _startIos(String configYaml, List<StartupStep> steps) async {
    String processed = configYaml;

    try {
      await _step(steps, 'buildConfig_ios', StartupError.configBuildFailed,
          () async {
        final overwrite = await OverwriteService.load();
        var withOverwrite = OverwriteService.apply(configYaml, overwrite);

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

        processed = ConfigTemplate.process(
              withOverwrite,
              apiPort: _apiPort,
              secret: _apiSecret,
            );
        _apiPort = ConfigTemplate.getApiPort(processed);
        _mixedPort = ConfigTemplate.getMixedPort(processed);
        _apiSecret ??= ConfigTemplate.getSecret(processed);
        _api = null;
        _stream = null;
        return 'len=${processed.length}, apiPort=$_apiPort';
      });

      await _step(steps, 'ensureGeo', StartupError.geoFilesFailed, () async {
        final installed = await GeoDataService.ensureFiles();
        return 'installed=$installed';
      });

      await _step(steps, 'startIosVpn', StartupError.coreStartFailed, () async {
        final ok = await vpn.VpnService.startIosVpn(configYaml: processed);
        if (!ok) throw Exception('startIosVpn returned false');
        _running = true;
        return 'ok';
      });

      // ── Step 3: waitApi (iOS) ──────────────────────────────────────
      // The Go core runs inside the PacketTunnel extension process.
      // Its REST API on 127.0.0.1:apiPort may take a moment to bind
      // after the VPN reports .connected. Poll until reachable.
      await _step(steps, 'waitApi', StartupError.apiTimeout, () async {
        for (var i = 1; i <= 50; i++) {
          if (await api.isAvailable()) {
            return 'ready after $i attempts';
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
        _running = false;
        throw Exception('API not available after 50 attempts (5s)');
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
      switch (_mode) {
        case CoreMode.mock:
          _core.stop();

        case CoreMode.ffi:
          // Close active connections with a timeout — the REST API may already
          // be unresponsive if the core is in a bad state.
          try {
            await api.closeAllConnections()
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
            await api.closeAllConnections()
                .timeout(const Duration(seconds: 2));
          } catch (e) {
            debugPrint('[CoreManager] closeAllConnections: $e');
          }
          await ProcessManager.instance.stop();
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
          InternetAddress.loopbackIPv4, port,
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
        coreLogs = lines.length > 100 ? lines.sublist(lines.length - 100) : lines;
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
    );

    lastReport = report;
    debugPrint(report.toDebugString());

    // Save to disk (fire-and-forget)
    StartupReport.save(report);
  }
}
