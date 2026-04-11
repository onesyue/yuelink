import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../constants.dart';

/// Manages mihomo as an external subprocess (desktop sidecar mode).
///
/// This follows the Clash Verge Rev pattern where mihomo runs as a
/// separate process and the UI communicates via REST API on :9090.
///
/// Used on desktop platforms (macOS, Windows, Linux) as an alternative
/// to embedding mihomo via FFI/CGO.
class ProcessManager {
  ProcessManager._();

  static ProcessManager? _instance;
  static ProcessManager get instance => _instance ??= ProcessManager._();

  Process? _process;
  bool _isRunning = false;
  final _logController = StreamController<String>.broadcast();

  bool get isRunning => _isRunning;
  Stream<String> get logStream => _logController.stream;

  /// Find the mihomo binary path.
  /// Looks in app bundle, app support dir, or PATH.
  Future<String?> findBinary() async {
    final candidates = <String>[];

    // App support directory
    final appDir = await getApplicationSupportDirectory();
    candidates.add('${appDir.path}/mihomo');

    // Platform-specific locations
    if (Platform.isMacOS) {
      // Inside .app bundle
      final execDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add('$execDir/mihomo');
      candidates.add('$execDir/../Resources/mihomo');
    } else if (Platform.isWindows) {
      final execDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add('$execDir\\mihomo.exe');
    } else {
      // Linux
      final execDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add('$execDir/mihomo');
    }

    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }

    // Try PATH
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['mihomo'],
      );
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (e) {
      debugPrint('[ProcessManager] PATH lookup failed: $e');
    }

    return null;
  }

  /// Start mihomo process with the given config file.
  Future<bool> start({
    required String configPath,
    String? binaryPath,
    int apiPort = 9090,
  }) async {
    if (_isRunning) return true;

    final binary = binaryPath ?? await findBinary();
    if (binary == null) return false;

    final appDir = await getApplicationSupportDirectory();

    try {
      _process = await Process.start(
        binary,
        [
          '-d', appDir.path,
          '-f', configPath,
          '-ext-ctl', '127.0.0.1:$apiPort',
        ],
      );

      _isRunning = true;

      // Forward stdout/stderr to log stream
      _process!.stdout.transform(const SystemEncoding().decoder).listen(
        (line) => _logController.add(line),
        onDone: () {
          // 进程意外退出或正常结束时，确保重置状态
          _isRunning = false;
          _process = null;
        },
      );
      _process!.stderr.transform(const SystemEncoding().decoder).listen(
        (line) => _logController.add('[ERROR] $line'),
      );

      // Wait a moment for process to initialize
      await Future.delayed(const Duration(milliseconds: 500));

      // Check if process is still running (might have crashed immediately)
      if (_process == null) {
        _isRunning = false;
        return false;
      }

      return true;
    } catch (e) {
      _logController.add('[ProcessManager] Failed to start: $e');
      _isRunning = false;
      _process = null;
      return false;
    }
  }

  /// Stop the mihomo process.
  Future<void> stop() async {
    // 强制先重置状态，防止后续代码抛出异常导致状态卡死
    final p = _process;
    _isRunning = false;
    _process = null;

    if (p == null) return;

    p.kill(ProcessSignal.sigterm);

    // Wait for graceful shutdown
    try {
      await p.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      p.kill(ProcessSignal.sigkill);
    } catch (e) {
      debugPrint('[ProcessManager] process exit error: $e');
    }
  }

  /// Write config and return the file path.
  static Future<String> writeConfig(String configYaml) async {
    final appDir = await getApplicationSupportDirectory();
    final configFile = File('${appDir.path}/${AppConstants.configFileName}');
    await configFile.writeAsString(configYaml);
    return configFile.path;
  }

  void dispose() {
    stop();
    _logController.close();
  }
}
