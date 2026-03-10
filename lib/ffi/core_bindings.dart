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
      return _loadWindowsLibrary();
    } else if (Platform.isIOS) {
      // iOS: statically linked, symbols are in the process itself
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  static DynamicLibrary _loadWindowsLibrary() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    // ignore: avoid_print
    print('[CoreBindings] exe directory: $exeDir');

    // Search order: next to exe, then bare name (system PATH)
    final candidates = [
      '$exeDir\\libclash.dll',
      'libclash.dll',
    ];

    for (final path in candidates) {
      final file = File(path);
      final exists = file.existsSync();
      // ignore: avoid_print
      print('[CoreBindings] trying: $path (exists: $exists)');
      if (exists) {
        try {
          return DynamicLibrary.open(path);
        } catch (e) {
          // ignore: avoid_print
          print('[CoreBindings] load failed for $path: $e');
        }
      }
    }

    throw Exception(
      'Cannot load libclash.dll\n'
      'exe directory: $exeDir\n'
      'Searched: ${candidates.join(", ")}\n'
      'Run: dart setup.dart build -p windows && dart setup.dart install -p windows',
    );
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

  /// char* InitCore(char* homeDir) — returns "" on success, error message on failure.
  /// Caller must free the returned string via freeCString.
  late final Pointer<Utf8> Function(Pointer<Utf8>) initCore = _lib
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>), Pointer<Utf8> Function(Pointer<Utf8>)>(
    'InitCore',
  );

  /// char* StartCore(char* configStr) — returns "" on success, error message on failure.
  /// Caller must free the returned string via freeCString.
  late final Pointer<Utf8> Function(Pointer<Utf8>) startCore = _lib
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>), Pointer<Utf8> Function(Pointer<Utf8>)>(
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

  /// char* UpdateConfig(char* configStr) — returns "" on success, error message on failure.
  /// Caller must free the returned string via freeCString.
  late final Pointer<Utf8> Function(Pointer<Utf8>) updateConfig = _lib
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>), Pointer<Utf8> Function(Pointer<Utf8>)>(
    'UpdateConfig',
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
