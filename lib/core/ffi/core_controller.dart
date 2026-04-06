import 'dart:convert';
import 'dart:ffi';

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
      final bindings = CoreBindings.instance;
      // On iOS, DynamicLibrary.process() always succeeds but the Go symbols
      // may not exist (e.g. simulator or Runner without static lib).
      // Probe a symbol to verify the core is actually linked.
      final _ = bindings.isRunning; // probe symbol to verify core is linked
      _bindings = bindings;
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

  /// Call an FFI function that returns a C string.
  /// Handles: nullptr (treated as success), empty string (success),
  /// non-empty string (error message). Frees the C string after reading.
  String? _callStringFn(Pointer<Utf8> Function(Pointer<Utf8>) fn, String arg) {
    final ptr = arg.toNativeUtf8();
    try {
      final resultPtr = fn(ptr);
      if (resultPtr.address == 0) return null; // NULL => success
      final result = resultPtr.toDartString();
      _bindings!.freeCString(resultPtr);
      return result.isEmpty ? null : result;
    } finally {
      calloc.free(ptr);
    }
  }

  /// Initialize the core. Returns null on success, error message on failure.
  String? init(String homeDir) {
    if (_useMock) {
      _mock.init(homeDir);
      return null;
    }
    return _callStringFn(_bindings!.initCore, homeDir);
  }

  /// Async init — wraps sync FFI call in a Future.
  /// InitCore typically takes 100-500ms (directory setup, config init).
  Future<String?> initAsync(String homeDir) async {
    return init(homeDir);
  }

  /// Start the core. Returns null on success, error message on failure.
  String? start(String configYaml) {
    if (_useMock) {
      final ok = _mock.start(configYaml);
      return ok ? null : 'mock start failed (not initialized)';
    }
    return _callStringFn(_bindings!.startCore, configYaml);
  }

  /// Async start — wraps sync FFI call in a Future.
  /// StartCore calls hub.Parse() which takes 500ms-2s.
  Future<String?> startAsync(String configYaml) async {
    return start(configYaml);
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

  /// Update config (hot reload). Returns null on success, error message on failure.
  String? updateConfig(String configYaml) {
    if (_useMock) {
      _mock.updateConfig(configYaml);
      return null;
    }
    return _callStringFn(_bindings!.updateConfig, configYaml);
  }

  // ------------------------------------------------------------------
  // MITM Engine
  // ------------------------------------------------------------------

  /// Call a no-argument FFI function that returns a C string error/success.
  /// Returns null on success (NULL or empty), non-null = error message.
  String? _callNoArgStringFn(Pointer<Utf8> Function() fn) {
    final resultPtr = fn();
    if (resultPtr.address == 0) return null;
    final result = resultPtr.toDartString();
    _bindings!.freeCString(resultPtr);
    return result.isEmpty ? null : result;
  }

  /// Call a no-argument FFI function that returns a JSON C string.
  /// NULL → '{}', empty → '{}', otherwise the JSON string.
  String _callNoArgJsonFn(Pointer<Utf8> Function() fn) {
    final resultPtr = fn();
    if (resultPtr.address == 0) return '{}';
    final result = resultPtr.toDartString();
    _bindings!.freeCString(resultPtr);
    return result.isEmpty ? '{}' : result;
  }

  /// Start the MITM engine. Returns null on success, error message on failure.
  String? startMitmEngine() {
    if (_useMock) return null;
    return _callNoArgStringFn(_bindings!.startMitmEngine);
  }

  /// Stop the MITM engine. Returns null on success, error message on failure.
  String? stopMitmEngine() {
    if (_useMock) return null;
    return _callNoArgStringFn(_bindings!.stopMitmEngine);
  }

  /// Get MITM engine status as a JSON string.
  String getMitmEngineStatusJson() {
    if (_useMock) {
      return '{"running":false,"port":9091,"address":"","healthy":false}';
    }
    return _callNoArgJsonFn(_bindings!.getMitmEngineStatus);
  }

  /// Generate Root CA. Returns JSON of RootCAStatus on success,
  /// or '{}' on failure.
  String generateRootCaJson() {
    if (_useMock) return '{"exists":false}';
    return _callNoArgJsonFn(_bindings!.generateRootCA);
  }

  /// Get Root CA status as JSON. Returns '{}' if CA doesn't exist.
  String getRootCaStatusJson() {
    if (_useMock) return '{}';
    return _callNoArgJsonFn(_bindings!.getRootCAStatus);
  }

  /// Convenience: returns the actual bound MITM engine port (0 = not running).
  int getMitmEnginePort() {
    try {
      final map = jsonDecode(getMitmEngineStatusJson()) as Map<String, dynamic>;
      if (map['running'] == true) {
        return (map['port'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
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
