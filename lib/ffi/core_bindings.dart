import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Low-level FFI bindings to the mihomo Go core (libclash).
///
/// All C strings returned by the core must be freed via [freeCString].
class CoreBindings {
  CoreBindings._();

  static CoreBindings? _instance;
  static CoreBindings get instance => _instance ??= CoreBindings._();

  late final DynamicLibrary _lib = _loadLibrary();

  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libclash.so');
    } else if (Platform.isMacOS) {
      // Search order:
      // 1. App bundle Frameworks (production + flutter run)
      // 2. Bare name via @rpath (when properly embedded)
      // 3. Arch-specific fallback
      final exe = Platform.resolvedExecutable;
      final bundleFrameworks = '${File(exe).parent.parent.path}/Frameworks';
      for (final path in [
        '$bundleFrameworks/libclash.dylib',
        '$bundleFrameworks/libclash-${_getMacArch()}.dylib',
        'libclash.dylib',
        'libclash-${_getMacArch()}.dylib',
      ]) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {}
      }
      throw Exception('Cannot load libclash.dylib — run: dart setup.dart build -p macos');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('libclash.dll');
    } else if (Platform.isIOS) {
      // iOS: statically linked, symbols are in the process itself
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  static String _getMacArch() {
    // Detect host architecture
    final result = Process.runSync('uname', ['-m']);
    final arch = (result.stdout as String).trim();
    return arch == 'x86_64' ? 'amd64' : 'arm64';
  }

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  /// int InitCore(char* homeDir)
  late final int Function(Pointer<Utf8>) initCore = _lib
      .lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
    'InitCore',
  );

  /// int StartCore(char* configStr)
  late final int Function(Pointer<Utf8>) startCore = _lib
      .lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
    'StartCore',
  );

  /// void StopCore()
  late final void Function() stopCore =
      _lib.lookupFunction<Void Function(), void Function()>('StopCore');

  /// void Shutdown()
  late final void Function() shutdown =
      _lib.lookupFunction<Void Function(), void Function()>('Shutdown');

  /// int IsRunning()
  late final int Function() isRunning =
      _lib.lookupFunction<Int32 Function(), int Function()>('IsRunning');

  // ------------------------------------------------------------------
  // Configuration
  // ------------------------------------------------------------------

  /// int ValidateConfig(char* configStr)
  late final int Function(Pointer<Utf8>) validateConfig = _lib
      .lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
    'ValidateConfig',
  );

  /// int UpdateConfig(char* configStr)
  late final int Function(Pointer<Utf8>) updateConfig = _lib
      .lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
    'UpdateConfig',
  );

  // ------------------------------------------------------------------
  // Proxies
  // ------------------------------------------------------------------

  /// char* GetProxies()
  late final Pointer<Utf8> Function() getProxies =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'GetProxies',
  );

  /// int ChangeProxy(char* groupName, char* proxyName)
  late final int Function(Pointer<Utf8>, Pointer<Utf8>) changeProxy = _lib
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)
      >('ChangeProxy');

  /// int TestDelay(char* proxyName, char* url, int timeoutMs)
  late final int Function(Pointer<Utf8>, Pointer<Utf8>, int) testDelay = _lib
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, Pointer<Utf8>, int)
      >('TestDelay');

  // ------------------------------------------------------------------
  // Traffic & Connections
  // ------------------------------------------------------------------

  /// char* GetTraffic()
  late final Pointer<Utf8> Function() getTraffic =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'GetTraffic',
  );

  /// char* GetConnections()
  late final Pointer<Utf8> Function() getConnections =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'GetConnections',
  );

  /// int CloseConnection(char* connId)
  late final int Function(Pointer<Utf8>) closeConnection = _lib
      .lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
    'CloseConnection',
  );

  /// void CloseAllConnections()
  late final void Function() closeAllConnections =
      _lib.lookupFunction<Void Function(), void Function()>(
    'CloseAllConnections',
  );

  // ------------------------------------------------------------------
  // Memory management
  // ------------------------------------------------------------------

  /// void FreeCString(char* s)
  late final void Function(Pointer<Utf8>) freeCString = _lib
      .lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
    'FreeCString',
  );
}
