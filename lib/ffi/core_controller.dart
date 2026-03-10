import 'package:ffi/ffi.dart';

import 'core_bindings.dart';
import 'core_mock.dart';

/// High-level Dart wrapper around the mihomo Go core.
///
/// Automatically falls back to [CoreMock] when the native library
/// is not available (development mode without compiled Go core).
class CoreController {
  CoreController._() {
    try {
      _bindings = CoreBindings.instance;
      _useMock = false;
    } catch (_) {
      // Native library not found — use mock for UI development
      _useMock = true;
    }
  }

  static CoreController? _instance;
  static CoreController get instance => _instance ??= CoreController._();

  late final CoreBindings? _bindings;
  late final bool _useMock;
  final _mock = CoreMock.instance;

  /// Whether running in mock mode (no native library).
  bool get isMockMode => _useMock;

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  /// Initialize the core. Returns null on success, error message on failure.
  String? init(String homeDir) {
    if (_useMock) {
      _mock.init(homeDir);
      return null;
    }
    final ptr = homeDir.toNativeUtf8();
    try {
      final resultPtr = _bindings!.initCore(ptr);
      final result = resultPtr.toDartString();
      _bindings!.freeCString(resultPtr);
      return result.isEmpty ? null : result;
    } finally {
      calloc.free(ptr);
    }
  }

  bool start(String configYaml) {
    if (_useMock) return _mock.start(configYaml);
    final ptr = configYaml.toNativeUtf8();
    try {
      return _bindings!.startCore(ptr) == 0;
    } finally {
      calloc.free(ptr);
    }
  }

  void stop() {
    if (_useMock) return _mock.stop();
    _bindings!.stopCore();
  }

  void shutdown() {
    if (_useMock) return _mock.shutdown();
    _bindings!.shutdown();
  }

  bool get isRunning {
    if (_useMock) return _mock.isRunning;
    return _bindings!.isRunning() == 1;
  }

  // ------------------------------------------------------------------
  // Configuration
  // ------------------------------------------------------------------

  bool validateConfig(String configYaml) {
    if (_useMock) return _mock.validateConfig(configYaml);
    final ptr = configYaml.toNativeUtf8();
    try {
      return _bindings!.validateConfig(ptr) == 0;
    } finally {
      calloc.free(ptr);
    }
  }

  bool updateConfig(String configYaml) {
    if (_useMock) return _mock.updateConfig(configYaml);
    final ptr = configYaml.toNativeUtf8();
    try {
      return _bindings!.updateConfig(ptr) == 0;
    } finally {
      calloc.free(ptr);
    }
  }

  // ------------------------------------------------------------------
  // Mock-only data methods (used in mock mode for UI development).
  // In FFI mode, all data goes through MihomoApi REST API instead.
  // ------------------------------------------------------------------

  Map<String, dynamic> getProxies() => _mock.getProxies();
  bool changeProxy(String groupName, String proxyName) =>
      _mock.changeProxy(groupName, proxyName);
  int testDelay(String proxyName) => _mock.testDelay(proxyName);
  ({int up, int down}) getTraffic() => _mock.getTraffic();
}
