import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../ffi/core_controller.dart';
import '../models/startup_report.dart';
import 'config_template.dart';
import 'geodata_service.dart';
import 'mihomo_api.dart';
import 'mihomo_stream.dart';
import 'overwrite_service.dart';
import 'process_manager.dart';
import 'vpn_service.dart' as vpn;

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

    final steps = <StartupStep>[];
    String? homeDir;

    try {
      // iOS: separate process, different path
      if (Platform.isIOS && !isMockMode) {
        return _startIos(configYaml, steps);
      }

      // ── Step 1: ensureGeo ──────────────────────────────────────────
      await _step(steps, 'ensureGeo', StartupError.geoFilesFailed, () async {
        final installed = await GeoDataService.ensureFiles();
        return 'installed=$installed';
      });

      // ── Step 2: initCore ───────────────────────────────────────────
      await _step(steps, 'initCore', StartupError.initCoreFailed, () async {
        if (_initialized || _mode == CoreMode.mock) {
          return 'skip (mode=$_mode, initialized=$_initialized)';
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
      });

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

      // ── Step 4: startVpn (Android only) ────────────────────────────
      int? tunFd;
      if (Platform.isAndroid && !isMockMode) {
        await _step(steps, 'startVpn', StartupError.vpnFdInvalid, () async {
          // Need mixedPort from raw config before full processing
          final rawMp = ConfigTemplate.getMixedPort(configYaml);
          tunFd = await vpn.VpnService.startAndroidVpn(mixedPort: rawMp);
          if (tunFd == null || tunFd! <= 0) {
            throw Exception('fd=$tunFd (expected > 0)');
          }
          return 'fd=$tunFd, mixedPort=$rawMp';
        });
      }

      // ── Step 5: buildConfig ────────────────────────────────────────
      // Single step: overwrite → template processing → TUN injection
      String processed = '';
      await _step(steps, 'buildConfig', StartupError.configBuildFailed,
          () async {
        // 5a. Apply user overwrite layer
        final overwrite = await OverwriteService.load();
        final withOverwrite = await Isolate.run(
            () => OverwriteService.apply(configYaml, overwrite));

        // 5b. Template processing (ports, DNS, sniffer, geo, TUN fd)
        final apiPort = _apiPort;
        final apiSecret = _apiSecret;
        processed = await Isolate.run(() => ConfigTemplate.process(
              withOverwrite,
              apiPort: apiPort,
              secret: apiSecret,
              tunFd: tunFd,
            ));

        // 5c. Extract ports/secret from final config
        _apiPort = ConfigTemplate.getApiPort(processed);
        _mixedPort = ConfigTemplate.getMixedPort(processed);
        _apiSecret ??= ConfigTemplate.getSecret(processed);
        _api = null;
        _stream = null;

        return 'input=${configYaml.length}b, '
            'output=${processed.length}b, '
            'apiPort=$_apiPort, mixedPort=$_mixedPort, '
            'tunFd=$tunFd';
      });

      // ── Step 6: startCore (Go hub.Parse) ───────────────────────────
      await _step(steps, 'startCore', StartupError.coreStartFailed, () async {
        // Write config to disk for debugging
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
            final error = await _core.startAsync(processed);
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
        for (var i = 1; i <= 50; i++) {
          if (await api.isAvailable()) {
            return 'ready after $i attempts';
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
        _running = false;
        _core.stop();
        throw Exception('API not available after 50 attempts (5s)');
      });

      // ── Step 8: verify ─────────────────────────────────────────────
      await _step(steps, 'verify', StartupError.coreDiedAfterStart, () async {
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
      await _finishReport(steps, true, null);
      return true;
    } catch (e) {
      final failedName =
          steps.where((s) => !s.success).firstOrNull?.name ?? 'unknown';
      await _finishReport(steps, false, failedName);

      // Clean up partial state
      if (_running) {
        _running = false;
        try {
          _core.stop();
        } catch (_) {}
      }
      if (Platform.isAndroid) {
        try {
          await vpn.VpnService.stopVpn();
        } catch (_) {}
      }

      rethrow;
    }
  }

  // ==================================================================
  // iOS start
  // ==================================================================

  Future<bool> _startIos(String configYaml, List<StartupStep> steps) async {
    String processed = configYaml;

    await _step(steps, 'buildConfig_ios', StartupError.configBuildFailed,
        () async {
      final overwrite = await OverwriteService.load();
      final withOverwrite = await Isolate.run(
          () => OverwriteService.apply(configYaml, overwrite));
      final apiPort = _apiPort;
      final apiSecret = _apiSecret;
      processed = await Isolate.run(() => ConfigTemplate.process(
            withOverwrite,
            apiPort: apiPort,
            secret: apiSecret,
          ));
      _apiPort = ConfigTemplate.getApiPort(processed);
      _mixedPort = ConfigTemplate.getMixedPort(processed);
      _apiSecret ??= ConfigTemplate.getSecret(processed);
      _api = null;
      _stream = null;
      return 'len=${processed.length}, apiPort=$_apiPort';
    });

    await _step(steps, 'startIosVpn', StartupError.coreStartFailed, () async {
      final ok = await vpn.VpnService.startIosVpn(configYaml: processed);
      if (!ok) throw Exception('startIosVpn returned false');
      _running = true;
      return 'ok';
    });

    await _finishReport(steps, true, null);
    return true;
  }

  // ==================================================================
  // Stop
  // ==================================================================

  Future<void> stop() async {
    if (!_running) return;

    switch (_mode) {
      case CoreMode.mock:
        _core.stop();

      case CoreMode.ffi:
        try {
          await api.closeAllConnections();
        } catch (e) {
          debugPrint('[CoreManager] closeAllConnections: $e');
        }
        _core.stop();

      case CoreMode.subprocess:
        try {
          await api.closeAllConnections();
        } catch (e) {
          debugPrint('[CoreManager] closeAllConnections: $e');
        }
        await ProcessManager.instance.stop();
    }

    _running = false;

    if (Platform.isAndroid || Platform.isIOS) {
      await vpn.VpnService.stopVpn();
    }
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
    } catch (_) {}

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
