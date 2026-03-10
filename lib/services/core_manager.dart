import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../ffi/core_controller.dart';
import 'config_template.dart';
import 'mihomo_api.dart';
import 'mihomo_stream.dart';
import 'process_manager.dart';

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

  /// Configure the API endpoint.
  void configure({int? port, String? secret, CoreMode? mode}) {
    if (port != null) _apiPort = port;
    _apiSecret = secret;
    if (mode != null) _mode = mode;
    _api = null; // Reset so next access uses new config
    _stream = null;
  }

  /// Start the mihomo core with the given config.
  ///
  /// Automatically processes the config template (replaces `$app_name`,
  /// ensures external-controller, extracts port/secret settings).
  Future<bool> start(String configYaml) async {
    if (_running) return true;

    // Process template variables and ensure API access
    final processed = ConfigTemplate.process(
      configYaml,
      apiPort: _apiPort,
      secret: _apiSecret,
    );

    // Extract actual port/secret from processed config
    _apiPort = ConfigTemplate.getApiPort(processed);
    _apiSecret ??= ConfigTemplate.getSecret(processed);
    _api = null; // Reset API client with new settings
    _stream = null;

    switch (_mode) {
      case CoreMode.mock:
        final ok = _core.start(processed);
        _running = ok;
        return ok;

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
        _core.stop();

      case CoreMode.subprocess:
        try { await api.closeAllConnections(); } catch (_) {}
        await ProcessManager.instance.stop();
    }

    _running = false;
  }

  // ------------------------------------------------------------------
  // FFI mode
  // ------------------------------------------------------------------

  Future<bool> _startFfi(String configYaml) async {
    // Write config file
    final appDir = await getApplicationSupportDirectory();
    final configFile = File('${appDir.path}/${AppConstants.configFileName}');
    await configFile.writeAsString(configYaml);

    final ok = _core.start(configYaml);
    if (!ok) return false;

    _running = true;
    await _waitForApi();
    return true;
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
    await _waitForApi();
    return true;
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  /// Wait for the REST API to become available.
  Future<bool> _waitForApi({int maxRetries = 10}) async {
    for (var i = 0; i < maxRetries; i++) {
      if (await api.isAvailable()) return true;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }
}
