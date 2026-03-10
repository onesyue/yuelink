import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../ffi/core_controller.dart';
import 'mihomo_api.dart';

/// Manages the mihomo core lifecycle and provides API access.
///
/// Architecture follows Clash Verge Rev / FlClash pattern:
/// - **Lifecycle** (start/stop): via FFI (embedded library) or subprocess
/// - **Data operations** (proxies, traffic, connections): via REST API on :9090
///
/// This separation means the UI layer always uses the same REST API interface,
/// regardless of whether the core is embedded (FFI) or external (subprocess).
class CoreManager {
  CoreManager._();

  static CoreManager? _instance;
  static CoreManager get instance => _instance ??= CoreManager._();

  final _core = CoreController.instance;
  MihomoApi? _api;
  Process? _process;
  bool _running = false;

  /// The REST API client for the running mihomo instance.
  MihomoApi get api => _api ??= MihomoApi(
        host: '127.0.0.1',
        port: _apiPort,
        secret: _apiSecret,
      );

  int _apiPort = 9090;
  String? _apiSecret;

  bool get isMockMode => _core.isMockMode;
  bool get isRunning => _running;

  /// Configure the API endpoint.
  void configure({int? port, String? secret}) {
    if (port != null) _apiPort = port;
    _apiSecret = secret;
    _api = null; // Reset so next access uses new config
  }

  /// Start the mihomo core with the given config.
  ///
  /// In mock mode, uses the FFI mock directly.
  /// In real mode, starts via FFI and connects the REST API.
  Future<bool> start(String configYaml) async {
    if (_running) return true;

    if (isMockMode) {
      final ok = _core.start(configYaml);
      _running = ok;
      return ok;
    }

    // Write config to a temp file for mihomo
    final appDir = await getApplicationSupportDirectory();
    final configFile = File('${appDir.path}/${AppConstants.configFileName}');
    await configFile.writeAsString(configYaml);

    // Inject external-controller settings into the config
    // so mihomo starts the REST API on the configured port
    final configWithApi = _ensureExternalController(configYaml);
    await configFile.writeAsString(configWithApi);

    // Start via FFI
    final ok = _core.start(configWithApi);
    if (!ok) return false;

    _running = true;

    // Wait for REST API to become available
    await _waitForApi();

    return true;
  }

  /// Stop the mihomo core.
  Future<void> stop() async {
    if (!_running) return;

    if (isMockMode) {
      _core.stop();
      _running = false;
      return;
    }

    // Close all connections before stopping
    try {
      await api.closeAllConnections();
    } catch (_) {}

    _core.stop();
    _process?.kill();
    _process = null;
    _running = false;
  }

  /// Ensure the config YAML has external-controller set.
  String _ensureExternalController(String yaml) {
    // Simple check: if external-controller is already set, keep it
    if (yaml.contains('external-controller:')) return yaml;

    // Append external-controller config
    final apiConfig = '\n'
        'external-controller: 127.0.0.1:$_apiPort\n'
        '${_apiSecret != null ? 'secret: $_apiSecret\n' : ''}';
    return yaml + apiConfig;
  }

  /// Wait for the REST API to become available after starting the core.
  Future<bool> _waitForApi({int maxRetries = 10}) async {
    for (var i = 0; i < maxRetries; i++) {
      if (await api.isAvailable()) return true;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }
}
