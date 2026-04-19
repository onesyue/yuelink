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
    } else if (Platform.isLinux) {
      return _loadLinuxLibrary();
    } else if (Platform.isIOS) {
      // iOS: statically linked, symbols are in the process itself
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  static DynamicLibrary _loadWindowsLibrary() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    // Search order: next to exe, then bare name (system PATH).
    final candidates = ['$exeDir\\libclash.dll', 'libclash.dll'];
    return _tryOpen(
      candidates,
      missingLibName: 'libclash.dll',
      exeDir: exeDir,
      installHint:
          'dart setup.dart build -p windows && dart setup.dart install -p windows',
    );
  }

  static DynamicLibrary _loadLinuxLibrary() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    // Flutter Linux bundle: executable is in bundle/, .so files in bundle/lib/.
    final candidates = [
      '$exeDir/lib/libclash.so',
      '$exeDir/libclash.so',
      'libclash.so',
    ];
    return _tryOpen(
      candidates,
      missingLibName: 'libclash.so',
      exeDir: exeDir,
      installHint:
          'dart setup.dart build -p linux && dart setup.dart install -p linux',
    );
  }

  /// Try each candidate path in order. Silent on success. On total failure,
  /// throws a single Exception whose message lists every attempt and the
  /// reason it didn't work (missing / open-failed + error). Callers never
  /// see the normal-path prints that used to fire on every startup.
  ///
  /// Path-shaped candidates (contain `/` or `\`) get an `existsSync()`
  /// pre-check so we skip obviously-absent files without invoking the
  /// loader. Bare-name candidates (e.g. `libclash.dll`, `libclash.so`)
  /// skip that check and go straight to `DynamicLibrary.open` — the OS
  /// loader resolves them against its own search list (Windows PATH,
  /// Linux LD_LIBRARY_PATH + system paths) and our cwd `existsSync()`
  /// would falsely mark a system-resident library as missing.
  static DynamicLibrary _tryOpen(
    List<String> candidates, {
    required String missingLibName,
    required String exeDir,
    required String installHint,
  }) {
    final attempts = <String>[];
    for (final path in candidates) {
      final isBareName = !path.contains('/') && !path.contains('\\');
      if (!isBareName && !File(path).existsSync()) {
        attempts.add('$path — missing');
        continue;
      }
      try {
        return DynamicLibrary.open(path);
      } catch (e) {
        attempts.add(isBareName
            ? '$path — loader search failed: $e'
            : '$path — open failed: $e');
      }
    }
    throw Exception(
      'Cannot load $missingLibName\n'
      'exe directory: $exeDir\n'
      'Attempts:\n  - ${attempts.join("\n  - ")}\n'
      'Run: $installHint',
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
  // MITM Engine
  // ------------------------------------------------------------------

  /// char* StartMITMEngine() — returns "" on success, error message on failure.
  late final Pointer<Utf8> Function() startMitmEngine =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'StartMITMEngine',
  );

  /// char* StopMITMEngine() — returns "" on success, error message on failure.
  late final Pointer<Utf8> Function() stopMitmEngine =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'StopMITMEngine',
  );

  /// char* GetMITMEngineStatus() — returns JSON of MitmEngineStatus.
  late final Pointer<Utf8> Function() getMitmEngineStatus =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'GetMITMEngineStatus',
  );

  /// char* GenerateRootCA() — returns JSON of RootCAStatus on success,
  /// or error message on failure.
  late final Pointer<Utf8> Function() generateRootCA =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'GenerateRootCA',
  );

  /// char* GetRootCAStatus() — returns JSON of RootCAStatus, or "{}" if absent.
  late final Pointer<Utf8> Function() getRootCAStatus =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'GetRootCAStatus',
  );

  /// char* UpdateMITMConfig(char* configJSON) — applies Phase-2 interception
  /// config (hostnames + URL/Header rewrites) to the running MITM engine.
  /// Returns "" on success, error message on failure.
  late final Pointer<Utf8> Function(Pointer<Utf8>) updateMitmConfig = _lib
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>), Pointer<Utf8> Function(Pointer<Utf8>)>(
    'UpdateMITMConfig',
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
