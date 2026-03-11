import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../ffi/core_controller.dart';
import 'config_template.dart';
import 'geodata_service.dart';
import 'mihomo_api.dart';
import 'mihomo_stream.dart';
import 'overwrite_service.dart';
import 'process_manager.dart';
import 'vpn_service.dart' as vpn;

/// How mihomo is managed.
enum CoreMode {
  /// Embedded via dart:ffi (FlClash pattern).
  ffi,
  /// External subprocess (Clash Verge Rev pattern).
  subprocess,
  /// Mock mode for development without Go core.
  mock,
}

/// Manages the mihomo core lifecycle and provides API access.
///
/// Architecture follows Clash Verge Rev / FlClash pattern:
/// - **Lifecycle** (start/stop): via FFI, subprocess, or mock
/// - **Data operations** (proxies, traffic, connections): via REST API on :9090
///
/// This separation means the UI layer always uses the same REST API interface,
/// regardless of whether the core is embedded (FFI) or external (subprocess).
class CoreManager {
  CoreManager._() {
    _core = CoreController.instance;
    if (_core.isMockMode) {
      _mode = CoreMode.mock;
    } else {
      _mode = CoreMode.ffi;
    }
  }

  static CoreManager? _instance;
  static CoreManager get instance => _instance ??= CoreManager._();

  late final CoreController _core;
  late CoreMode _mode;
  MihomoApi? _api;
  MihomoStream? _stream;
  bool _running = false;
  bool _initialized = false;

  /// The REST API client for the running mihomo instance.
  MihomoApi get api => _api ??= MihomoApi(
        host: '127.0.0.1',
        port: _apiPort,
        secret: _apiSecret,
      );

  int _apiPort = 9090;
  String? _apiSecret;

  /// The WebSocket stream client for real-time data.
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

  /// Configure the API endpoint.
  void configure({int? port, String? secret, CoreMode? mode}) {
    if (port != null) _apiPort = port;
    _apiSecret = secret;
    if (mode != null) _mode = mode;
    _api = null; // Reset so next access uses new config
    _stream = null;
  }

  /// Ensure the Go core is initialized (homeDir set).
  /// Uses async FFI to avoid blocking the UI thread.
  Future<void> _ensureInit() async {
    if (_initialized || _mode == CoreMode.mock) return;
    final appDir = await getApplicationSupportDirectory();
    final error = await _core.initAsync(appDir.path);
    if (error != null) throw Exception('InitCore: $error');
    _initialized = true;
  }

  /// Start the mihomo core with the given config.
  ///
  /// Automatically processes the config template (replaces `$app_name`,
  /// ensures external-controller, extracts port/secret settings).
  ///
  /// On Android, also starts the VpnService to obtain the TUN fd and injects
  /// it into the config so mihomo uses the OS-managed TUN interface.
  Future<bool> start(String configYaml) async {
    debugPrint('[CoreManager] start() called, running=$_running, mode=$_mode');
    if (_running) return true;

    // Apply overwrite layer on top of base config (heavy regex — use Isolate)
    final overwrite = await OverwriteService.load();
    final withOverwrite = await Isolate.run(
        () => OverwriteService.apply(configYaml, overwrite));

    // iOS: Go core runs inside the PacketTunnel extension process.
    // Skip _ensureInit() — the extension calls InitCore in its own process.
    if (Platform.isIOS && !isMockMode) {
      final apiPort = _apiPort;
      final apiSecret = _apiSecret;
      final processed = await Isolate.run(() => ConfigTemplate.process(
            withOverwrite,
            apiPort: apiPort,
            secret: apiSecret,
          ));
      _apiPort = ConfigTemplate.getApiPort(processed);
      _mixedPort = ConfigTemplate.getMixedPort(processed);
      _apiSecret ??= ConfigTemplate.getSecret(processed);
      _api = null;
      _stream = null;

      final ok = await vpn.VpnService.startIosVpn(configYaml: processed);
      if (ok) _running = true;
      return ok;
    }

    // Non-iOS: initialize Go core in this process
    await _ensureInit();
    debugPrint('[CoreManager] init done, initialized=$_initialized');

    // Ensure GeoIP/GeoSite files exist before starting core.
    // Primary: copy from bundled assets (instant).
    // Fallback: download from CDN mirrors (if assets not bundled).
    // Without these files, mihomo's parseRules fails on GEOIP/GEOSITE rules.
    await GeoDataService.ensureFiles();

    // On Android, start VpnService first to get the TUN fd
    int? tunFd;
    if (Platform.isAndroid && !isMockMode) {
      final mp = ConfigTemplate.getMixedPort(withOverwrite);
      tunFd = await vpn.VpnService.startAndroidVpn(mixedPort: mp);
      if (tunFd <= 0) {
        return false;
      }
    }

    // Process template variables, ensure API access, inject TUN fd
    // Heavy regex operations — run in background Isolate to prevent ANR
    final apiPort = _apiPort;
    final apiSecret = _apiSecret;
    final processed = await Isolate.run(() => ConfigTemplate.process(
          withOverwrite,
          apiPort: apiPort,
          secret: apiSecret,
          tunFd: tunFd,
        ));

    // Extract actual port/secret from processed config
    _apiPort = ConfigTemplate.getApiPort(processed);
    _mixedPort = ConfigTemplate.getMixedPort(processed);
    _apiSecret ??= ConfigTemplate.getSecret(processed);
    _api = null; // Reset API client with new settings
    _stream = null;

    debugPrint('[CoreManager] processed config: '
        'apiPort=$_apiPort, mixedPort=$_mixedPort, '
        'hasSecret=${_apiSecret != null}, '
        'tunFd=$tunFd, configLen=${processed.length}');
    // Log first 500 chars and last 300 chars for debugging config issues
    debugPrint('[CoreManager] config head: '
        '${processed.substring(0, processed.length.clamp(0, 500))}');
    if (processed.length > 500) {
      debugPrint('[CoreManager] config tail: '
          '...${processed.substring(processed.length - 300.clamp(0, processed.length))}');
    }

    switch (_mode) {
      case CoreMode.mock:
        final error = _core.start(processed);
        if (error != null) {
          debugPrint('[CoreManager] mock start failed: $error');
          return false;
        }
        _running = true;
        return true;

      case CoreMode.ffi:
        return _startFfi(processed);

      case CoreMode.subprocess:
        return _startSubprocess(processed);
    }
  }

  /// Stop the mihomo core.
  Future<void> stop() async {
    if (!_running) return;

    switch (_mode) {
      case CoreMode.mock:
        _core.stop();

      case CoreMode.ffi:
        try { await api.closeAllConnections(); } catch (_) {}
        // Stop Go core FIRST (shuts down TUN listener cleanly),
        // then close VPN fd. Reverse order causes Go to read from
        // an invalid fd → potential panic.
        _core.stop();

      case CoreMode.subprocess:
        try { await api.closeAllConnections(); } catch (_) {}
        await ProcessManager.instance.stop();
    }

    _running = false;

    // Tear down OS VPN tunnel AFTER core is stopped.
    // On Android, this closes the TUN fd and calls stopSelf().
    if (Platform.isAndroid || Platform.isIOS) {
      await vpn.VpnService.stopVpn();
    }
  }

  // ------------------------------------------------------------------
  // FFI mode
  // ------------------------------------------------------------------

  static const _kLastWorkingConfig = 'last_working_config.yaml';

  /// Load the last known-good config (for rollback).
  Future<String?> loadLastWorkingConfig() async {
    final appDir = await getApplicationSupportDirectory();
    final file = File('${appDir.path}/$_kLastWorkingConfig');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> _saveLastWorkingConfig(String configYaml) async {
    final appDir = await getApplicationSupportDirectory();
    await File('${appDir.path}/$_kLastWorkingConfig').writeAsString(configYaml);
  }

  Future<bool> _startFfi(String configYaml) async {
    // Write config file
    final appDir = await getApplicationSupportDirectory();
    final configFile = File('${appDir.path}/${AppConstants.configFileName}');
    await configFile.writeAsString(configYaml);
    debugPrint('[CoreManager] config written to: ${configFile.path}');

    // Use async FFI to avoid blocking the UI thread during hub.Parse()
    final error = await _core.startAsync(configYaml);
    if (error != null) {
      debugPrint('[CoreManager] StartCore failed: $error');
      throw Exception('StartCore: $error');
    }

    _running = true;

    // Wait for the external-controller HTTP server to be ready.
    // It starts in a goroutine, so there's a brief delay after hub.Parse().
    // Without waiting, API calls (routing mode, proxy refresh) fail silently.
    final apiOk = await _waitForApi();
    debugPrint('[CoreManager] API ${apiOk ? "ready" : "NOT available"}');
    if (!apiOk) {
      _running = false;
      _core.stop();
      throw Exception('mihomo API not available after startup');
    }
    _saveLastWorkingConfig(configYaml);

    // Post-startup DNS diagnostic (non-blocking)
    _runDnsDiagnostic();

    return true;
  }

  /// Test DNS resolution after startup to verify the resolver works.
  /// Non-blocking — logs result but doesn't affect startup.
  Future<void> _runDnsDiagnostic() async {
    try {
      final result = await api.queryDns('google.com');
      final status = result['Status'];
      final answers = result['Answer'] as List?;
      if (status == 0 && answers != null && answers.isNotEmpty) {
        debugPrint('[CoreManager] DNS diagnostic OK: google.com → '
            '${answers.map((a) => a['data']).join(', ')}');
      } else {
        debugPrint('[CoreManager] DNS diagnostic FAILED: status=$status, '
            'answers=${answers?.length ?? 0}');
      }
    } catch (e) {
      debugPrint('[CoreManager] DNS diagnostic ERROR: $e');
    }
  }

  // ------------------------------------------------------------------
  // Subprocess mode (desktop sidecar)
  // ------------------------------------------------------------------

  Future<bool> _startSubprocess(String configYaml) async {
    final configPath = await ProcessManager.writeConfig(configYaml);

    final ok = await ProcessManager.instance.start(
      configPath: configPath,
      apiPort: _apiPort,
    );
    if (!ok) return false;

    _running = true;
    final apiOk = await _waitForApi();
    if (apiOk) await _saveLastWorkingConfig(configYaml);
    return apiOk;
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  /// Wait for the REST API to become available.
  /// The external-controller HTTP server starts in a goroutine after
  /// hub.Parse() returns, typically ready within 100-300ms.
  /// Retries for up to ~5 seconds to accommodate slow devices.
  Future<bool> _waitForApi({int maxRetries = 50}) async {
    for (var i = 0; i < maxRetries; i++) {
      if (await api.isAvailable()) {
        debugPrint('[CoreManager] API available after ${i + 1} attempts');
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('[CoreManager] API not available after $maxRetries attempts');
    return false;
  }
}
