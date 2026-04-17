import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../../constants.dart';
import '../../shared/event_log.dart';
import '../storage/settings_service.dart';
import 'service_client.dart';
import 'service_models.dart';

class ServiceManager {
  ServiceManager._();

  static bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Expected service protocol version — loaded from the same file the Go
  /// helper embeds (`service/protocol_version.txt`). This is the IPC
  /// protocol revision, NOT the app version: bump it only on breaking
  /// changes to the endpoint contract so app upgrades don't force a
  /// service reinstall on every release.
  ///
  /// Cached after first read — the asset never changes at runtime.
  static String? _cachedExpectedVersion;
  static Future<String> expectedVersion() async {
    final cached = _cachedExpectedVersion;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('service/protocol_version.txt');
    return _cachedExpectedVersion = raw.trim();
  }

  static Future<DesktopServiceInfo> getInfo() async {
    if (!isSupported) {
      return DesktopServiceInfo.notInstalled();
    }

    final installed = await isInstalled();
    if (!installed) {
      return DesktopServiceInfo.notInstalled();
    }

    try {
      final status = await ServiceClient.status();
      // Version check: detect stale service binary after app update
      final remoteVersion = await ServiceClient.version();
      final expected = await expectedVersion();
      final versionMismatch =
          remoteVersion != null && remoteVersion != expected;
      return status.copyWith(
        serviceVersion: remoteVersion,
        needsReinstall: versionMismatch,
      );
    } catch (e) {
      return const DesktopServiceInfo(
        installed: true,
        reachable: false,
        mihomoRunning: false,
      ).copyWith(detail: e.toString().split('\n').first);
    }
  }

  static Future<bool> isInstalled() async {
    if (!isSupported) return false;

    // macOS / Linux: plist|systemd unit + helper + mihomo binary must all
    // exist AND the Dart-side socket path must be recorded. Same rationale
    // as the Windows token check — a partial uninstall that clears
    // SettingsService config but leaves files on disk (or vice-versa) used
    // to surface downstream as `ServiceClient` throwing "socket path is
    // missing" instead of a clean "not installed" state the UI can guide
    // the user out of.
    if (Platform.isMacOS) {
      if (!File(_macPlistPath).existsSync() ||
          !File(_macInstalledHelperPath).existsSync() ||
          !File(_macInstalledMihomoPath).existsSync()) {
        return false;
      }
      final socket = await SettingsService.getServiceSocketPath();
      return socket != null && socket.isNotEmpty;
    }

    if (Platform.isLinux) {
      if (!File(_linuxUnitPath).existsSync() ||
          !File(_linuxInstalledHelperPath).existsSync() ||
          !File(_linuxInstalledMihomoPath).existsSync()) {
        return false;
      }
      final socket = await SettingsService.getServiceSocketPath();
      return socket != null && socket.isNotEmpty;
    }

    // Windows: SCM must have the service AND the Dart side must have the
    // auth token. A stale SCM entry without a token (e.g. uninstall script
    // failed mid-way but the finally block still ran setServiceAuthToken
    // null) used to surface as startService throwing "auth token is
    // missing" 4ms into the startup pipeline. Treating that state as "not
    // installed" lets the UI offer a fresh install that recreates both.
    final result = await Process.run(
      'sc',
      ['query', AppConstants.desktopServiceName],
    );
    if (result.exitCode != 0) return false;
    final token = await SettingsService.getServiceAuthToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> install() async {
    if (!isSupported) {
      throw UnsupportedError(
          'Desktop service mode is only available on macOS, Windows and Linux');
    }

    // Resolve identity / paths captured at install time. The helper will
    // refuse any later request whose peer UID doesn't match this UID
    // (macOS/Linux) or that targets a path outside this allowlist.
    final ownerUid = _currentUid();
    final appSupport = await getApplicationSupportDirectory();
    final tempBase = Directory.systemTemp.path;
    final allowedHomeDirs = <String>[
      appSupport.path,
      tempBase,
    ];

    // Windows still needs a token for HTTP loopback. macOS/Linux don't.
    String? token;
    if (Platform.isWindows) {
      token = await SettingsService.getServiceAuthToken() ?? _generateToken();
      await SettingsService.setServiceAuthToken(token);
      await SettingsService.setServicePort(AppConstants.serviceListenPort);
    } else {
      // Clean up any legacy token from a previous install
      await SettingsService.setServiceAuthToken(null);
    }

    final binaries = await _resolveSourceBinaries();
    final tempDir = await Directory.systemTemp.createTemp('yuelink_service_');

    try {
      String mihomoInstallPath;
      String helperLogPath;
      String? socketPath;
      if (Platform.isMacOS) {
        mihomoInstallPath = _macInstalledMihomoPath;
        helperLogPath = _macInstalledHelperLogPath;
        socketPath = _macSocketPath;
      } else if (Platform.isLinux) {
        mihomoInstallPath = _linuxInstalledMihomoPath;
        helperLogPath = _linuxInstalledHelperLogPath;
        socketPath = _linuxSocketPath;
      } else {
        mihomoInstallPath = _windowsInstalledMihomoPath;
        helperLogPath = _windowsInstalledHelperLogPath;
      }

      // Persist socket path to settings so the Dart client can find it.
      if (socketPath != null) {
        await SettingsService.setServiceSocketPath(socketPath);
      }

      final configFile = File('${tempDir.path}/service-config.json');
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          if (token != null) 'token': token,
          if (Platform.isWindows) ...{
            'listen_host': AppConstants.serviceListenHost,
            'listen_port': AppConstants.serviceListenPort,
          },
          if (socketPath != null) 'socket_path': socketPath,
          'owner_uid': ownerUid,
          'allowed_home_dirs': allowedHomeDirs,
          'mihomo_path': mihomoInstallPath,
          'helper_log_path': helperLogPath,
        }),
      );

      if (Platform.isMacOS) {
        final script = File('${tempDir.path}/install_service.sh');
        await script.writeAsString(
          _macInstallScript(
            helperSource: binaries.helperPath,
            mihomoSource: binaries.mihomoPath,
            configSource: configFile.path,
          ),
        );
        await script.setLastModified(DateTime.now());
        await Process.run('chmod', ['700', script.path]);
        await _runMacElevated(script.path);
      } else if (Platform.isLinux) {
        final script = File('${tempDir.path}/install_service.sh');
        await script.writeAsString(
          _linuxInstallScript(
            helperSource: binaries.helperPath,
            mihomoSource: binaries.mihomoPath,
            configSource: configFile.path,
          ),
        );
        await Process.run('chmod', ['700', script.path]);
        await _runLinuxElevated(script.path);
      } else if (Platform.isWindows) {
        final script = File('${tempDir.path}/install_service.ps1');
        await script.writeAsString(
          _windowsInstallScript(
            helperSource: binaries.helperPath,
            mihomoSource: binaries.mihomoPath,
            configSource: configFile.path,
          ),
        );
        await _runWindowsElevated(script.path);
      }

      await _waitUntilReachable();
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Update the service in-place: stop → replace binaries → restart.
  /// Faster than uninstall+install — preserves token and config.
  static Future<void> update() async {
    if (!isSupported) return;
    if (!await isInstalled()) {
      // Not installed — do a fresh install instead
      await install();
      return;
    }

    final binaries = await _resolveSourceBinaries();

    if (Platform.isMacOS) {
      final script = '''
#!/bin/sh
set -eu
launchctl bootout system/${AppConstants.desktopServiceLabel} >/dev/null 2>&1 || true
sleep 1
cp ${_shellQuote(binaries.helperPath)} ${_shellQuote(_macInstalledHelperPath)}
cp ${_shellQuote(binaries.mihomoPath)} ${_shellQuote(_macInstalledMihomoPath)}
chmod 755 ${_shellQuote(_macInstalledHelperPath)} ${_shellQuote(_macInstalledMihomoPath)}
chown root:wheel ${_shellQuote(_macInstalledHelperPath)} ${_shellQuote(_macInstalledMihomoPath)}
launchctl bootstrap system ${_shellQuote(_macPlistPath)}
launchctl kickstart -k system/${AppConstants.desktopServiceLabel}
''';
      final tempDir = await Directory.systemTemp.createTemp('yuelink_update_');
      try {
        final scriptFile = File('${tempDir.path}/update_service.sh');
        await scriptFile.writeAsString(script);
        await Process.run('chmod', ['700', scriptFile.path]);
        await _runMacElevated(scriptFile.path);
      } finally {
        try { await tempDir.delete(recursive: true); } catch (_) {}
      }
    } else if (Platform.isLinux) {
      final script = '''
#!/bin/sh
set -eu
systemctl stop ${AppConstants.desktopServiceLabel} >/dev/null 2>&1 || true
cp ${_shellQuote(binaries.helperPath)} ${_shellQuote(_linuxInstalledHelperPath)}
cp ${_shellQuote(binaries.mihomoPath)} ${_shellQuote(_linuxInstalledMihomoPath)}
chmod 755 ${_shellQuote(_linuxInstalledHelperPath)} ${_shellQuote(_linuxInstalledMihomoPath)}
systemctl restart ${AppConstants.desktopServiceLabel}
''';
      final tempDir = await Directory.systemTemp.createTemp('yuelink_update_');
      try {
        final scriptFile = File('${tempDir.path}/update_service.sh');
        await scriptFile.writeAsString(script);
        await Process.run('chmod', ['700', scriptFile.path]);
        await _runLinuxElevated(scriptFile.path);
      } finally {
        try { await tempDir.delete(recursive: true); } catch (_) {}
      }
    } else if (Platform.isWindows) {
      final script = r'''
$ErrorActionPreference = "Stop"
$serviceName = '__SERVICE_NAME__'
Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Copy-Item -Force __HELPER_SRC__ __HELPER_DST__
Copy-Item -Force __MIHOMO_SRC__ __MIHOMO_DST__
Start-Service -Name $serviceName
'''
          .replaceAll('__SERVICE_NAME__', AppConstants.desktopServiceName)
          .replaceAll('__HELPER_SRC__', _powershellQuoted(binaries.helperPath))
          .replaceAll('__HELPER_DST__', _powershellQuoted(_windowsInstalledHelperPath))
          .replaceAll('__MIHOMO_SRC__', _powershellQuoted(binaries.mihomoPath))
          .replaceAll('__MIHOMO_DST__', _powershellQuoted(_windowsInstalledMihomoPath));
      final tempDir = await Directory.systemTemp.createTemp('yuelink_update_');
      try {
        final scriptFile = File('${tempDir.path}/update_service.ps1');
        await scriptFile.writeAsString(script);
        await _runWindowsElevated(scriptFile.path);
      } finally {
        try { await tempDir.delete(recursive: true); } catch (_) {}
      }
    }

    await _waitUntilReachable();
  }

  static Future<void> uninstall() async {
    if (!isSupported) return;

    final tempDir = await Directory.systemTemp.createTemp('yuelink_service_');
    try {
      if (Platform.isMacOS) {
        final script = File('${tempDir.path}/uninstall_service.sh');
        await script.writeAsString(_macUninstallScript());
        await Process.run('chmod', ['700', script.path]);
        await _runMacElevated(script.path);
      } else if (Platform.isLinux) {
        final script = File('${tempDir.path}/uninstall_service.sh');
        await script.writeAsString(_linuxUninstallScript());
        await Process.run('chmod', ['700', script.path]);
        await _runLinuxElevated(script.path);
      } else if (Platform.isWindows) {
        final script = File('${tempDir.path}/uninstall_service.ps1');
        await script.writeAsString(_windowsUninstallScript());
        await _runWindowsElevated(script.path);
      }
    } finally {
      // Clear every piece of client-side state unconditionally — even if
      // the elevated script failed. Mismatched state (e.g. SCM entry or
      // plist still present but settings.json has nothing) is what caused
      // the "Desktop service X is missing" cascade. Next install starts
      // from a known-clean settings baseline; the install scripts already
      // handle deleting residual OS-level registrations.
      await SettingsService.setServiceAuthToken(null);
      await SettingsService.setServiceSocketPath(null);
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<_ServiceBinaries> _resolveSourceBinaries() async {
    final execDir = File(Platform.resolvedExecutable).parent.path;
    final cwd = Directory.current.path;
    final helperCandidates = <String>[];
    final mihomoCandidates = <String>[];

    if (Platform.isMacOS) {
      helperCandidates.addAll([
        '$execDir/../Frameworks/yuelink-service-helper',
        '$execDir/../Resources/yuelink-service-helper',
        '$cwd/macos/Frameworks/yuelink-service-helper',
        '$cwd/service/build/macos-universal/yuelink-service-helper',
        '$cwd/service/build/macos-arm64/yuelink-service-helper',
        '$cwd/service/build/macos-amd64/yuelink-service-helper',
      ]);
      mihomoCandidates.addAll([
        '$execDir/../Frameworks/yuelink-mihomo',
        '$execDir/../Resources/yuelink-mihomo',
        '$cwd/macos/Frameworks/yuelink-mihomo',
        '$cwd/service/build/macos-universal/yuelink-mihomo',
        '$cwd/service/build/macos-arm64/yuelink-mihomo',
        '$cwd/service/build/macos-amd64/yuelink-mihomo',
      ]);
    } else if (Platform.isLinux) {
      helperCandidates.addAll([
        '$execDir/yuelink-service-helper',
        '$cwd/linux/libs/yuelink-service-helper',
        '$cwd/service/build/linux-amd64/yuelink-service-helper',
        '$cwd/service/build/linux-arm64/yuelink-service-helper',
      ]);
      mihomoCandidates.addAll([
        '$execDir/yuelink-mihomo',
        '$cwd/linux/libs/yuelink-mihomo',
        '$cwd/service/build/linux-amd64/yuelink-mihomo',
        '$cwd/service/build/linux-arm64/yuelink-mihomo',
      ]);
    } else if (Platform.isWindows) {
      helperCandidates.addAll([
        '$execDir\\yuelink-service-helper.exe',
        '$cwd\\windows\\libs\\amd64\\yuelink-service-helper.exe',
        '$cwd\\windows\\libs\\arm64\\yuelink-service-helper.exe',
        '$cwd\\service\\build\\windows-amd64\\yuelink-service-helper.exe',
        '$cwd\\service\\build\\windows-arm64\\yuelink-service-helper.exe',
      ]);
      mihomoCandidates.addAll([
        '$execDir\\yuelink-mihomo.exe',
        '$cwd\\windows\\libs\\amd64\\yuelink-mihomo.exe',
        '$cwd\\windows\\libs\\arm64\\yuelink-mihomo.exe',
        '$cwd\\service\\build\\windows-amd64\\yuelink-mihomo.exe',
        '$cwd\\service\\build\\windows-arm64\\yuelink-mihomo.exe',
      ]);
    }

    final helperPath = helperCandidates.firstWhere(
      (path) => File(path).existsSync(),
      orElse: () => '',
    );
    final mihomoPath = mihomoCandidates.firstWhere(
      (path) => File(path).existsSync(),
      orElse: () => '',
    );

    if (helperPath.isEmpty || mihomoPath.isEmpty) {
      // Log every candidate path we checked so next-time diagnosis doesn't
      // rely on the user guessing. Most common failures: Intel Mac DMG
      // shipped without amd64 build, or `flutter build macos` skipped the
      // "Bundle native libs" Xcode phase.
      EventLog.write('[Service] binaries missing. helper_tried=${helperCandidates.join("|")} '
          'mihomo_tried=${mihomoCandidates.join("|")}');
      final helperHint = helperPath.isEmpty ? 'yuelink-service-helper' : null;
      final mihomoHint = mihomoPath.isEmpty ? 'yuelink-mihomo' : null;
      final missing = [helperHint, mihomoHint].whereType<String>().join(' + ');
      throw FileSystemException(
        'Desktop service binary missing: $missing. '
        'This build was not packaged with desktop-service support — '
        'check Settings → Connection Repair → Export Diagnostic Logs.',
      );
    }

    return _ServiceBinaries(
      helperPath: helperPath,
      mihomoPath: mihomoPath,
    );
  }

  static Future<void> _waitUntilReachable() async {
    // 20 × 500ms = 10s. Helper binaries typically ping within ~1s; the long
    // cap covers slow Windows Service startup (driver init, AV scan) and
    // macOS launchd kickstart lag on first install.
    for (var i = 0; i < 20; i++) {
      if (await ServiceClient.ping()) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    // Ping never succeeded. Gather whatever we can so the user (and future
    // us) can tell "service failed to start" apart from "service started
    // but IPC auth / socket path wrong".
    final diag = await _collectUnreachableDiagnostics();
    EventLog.write('[Service] _waitUntilReachable timed out: $diag');
    throw ProcessException(
      'service',
      const [],
      'Service installed but IPC never came up (10s). $diag',
    );
  }

  /// Best-effort inspection of why the service isn't answering — runs after
  /// 10s of ping failures, just before we throw. Each probe has its own
  /// timeout so a stuck helper can't block the error path.
  static Future<String> _collectUnreachableDiagnostics() async {
    final parts = <String>[];

    // Is the service/daemon even registered?
    if (Platform.isWindows) {
      try {
        final r = await Process.run(
          'sc', ['query', AppConstants.desktopServiceName],
        ).timeout(const Duration(seconds: 2));
        final line = r.stdout.toString().split('\n')
            .firstWhere((l) => l.toUpperCase().contains('STATE'),
                orElse: () => '<no STATE line>');
        parts.add('sc=${line.trim()}');
      } catch (e) {
        parts.add('sc_probe_err=$e');
      }
    } else if (Platform.isMacOS) {
      try {
        final r = await Process.run('launchctl', [
          'print', 'system/${AppConstants.desktopServiceLabel}',
        ]).timeout(const Duration(seconds: 2));
        final state = r.stdout.toString().split('\n')
            .firstWhere((l) => l.contains('state ='),
                orElse: () => '<no state line>');
        parts.add('launchctl=${state.trim()}');
      } catch (e) {
        parts.add('launchctl_probe_err=$e');
      }
    } else if (Platform.isLinux) {
      try {
        final r = await Process.run('systemctl', [
          'is-active', AppConstants.desktopServiceName,
        ]).timeout(const Duration(seconds: 2));
        parts.add('systemctl=${r.stdout.toString().trim()}');
      } catch (e) {
        parts.add('systemctl_probe_err=$e');
      }
    }

    // Does the helper log file exist? If so, the tail tells us what
    // happened at startup.
    final logPath = Platform.isWindows
        ? _windowsInstalledHelperLogPath
        : Platform.isMacOS
            ? _macInstalledHelperLogPath
            : _linuxInstalledHelperLogPath;
    try {
      final logFile = File(logPath);
      if (logFile.existsSync()) {
        final content = await logFile.readAsString();
        final tail = content.length > 300
            ? content.substring(content.length - 300)
            : content;
        parts.add('helper_log_tail=${_truncateForLog(tail)}');
      } else {
        parts.add('helper_log=<missing>');
      }
    } catch (e) {
      parts.add('helper_log_err=$e');
    }

    return parts.join(' | ');
  }

  static String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  static Future<void> _runMacElevated(String scriptPath) async {
    final command =
        'do shell script "${_appleScriptEscape('/bin/sh ${_shellQuote(scriptPath)}')}" with administrator privileges';
    final result = await Process.run('osascript', ['-e', command]);
    EventLog.write('[Service] osascript exit=${result.exitCode} '
        'stdout=${_truncateForLog('${result.stdout}')} '
        'stderr=${_truncateForLog('${result.stderr}')}');
    if (result.exitCode != 0) {
      throw ProcessException(
        'osascript',
        ['-e', command],
        '${result.stderr}'.trim().isEmpty
            ? '${result.stdout}'.trim()
            : '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  static Future<void> _runWindowsElevated(String scriptPath) async {
    // `Start-Process -Verb RunAs` cannot be combined with
    // `-RedirectStandardOutput` / `-RedirectStandardError` — PowerShell
    // rejects that parameter set, which is why an earlier attempt at
    // capturing elevated output ended up with every install exiting 1
    // with empty stdout/stderr (the "auth token is missing" cascade users
    // reported). Instead we make the elevated child record itself via
    // Start-Transcript into a well-known path and read it back here.
    final transcriptPath =
        '${Directory.systemTemp.path}\\yuelink_elev_${DateTime.now().millisecondsSinceEpoch}.log';

    final launcher = r'''
$ErrorActionPreference = "Stop"
$scriptPath = __SCRIPT__
$transcriptPath = __TRANSCRIPT__

$inner = @"
try {
  Start-Transcript -Path `"$transcriptPath`" -Force | Out-Null
  & `"$scriptPath`"
  `$code = 0
} catch {
  Write-Error `$_.Exception.Message
  `$code = 1
} finally {
  try { Stop-Transcript | Out-Null } catch {}
}
exit `$code
"@

try {
  # -WindowStyle Hidden: keep the elevated PowerShell invisible. Without it,
  # on Windows 11 22H2+ the new console window gets captured by Windows
  # Terminal, which then tries to load its own settings.json — and a user
  # with a broken `defaultProfile` GUID sees a "加载用户设置时遇到错误"
  # dialog the moment they approve UAC. Hiding the window sidesteps
  # Windows Terminal entirely; the elevated process still runs and the
  # Start-Transcript below still captures its output to our temp file.
  $process = Start-Process PowerShell -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-Command', $inner
  )
  exit $process.ExitCode
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
'''
        .replaceAll('__SCRIPT__', _powershellQuoted(scriptPath))
        .replaceAll('__TRANSCRIPT__', _powershellQuoted(transcriptPath));

    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-Command', launcher],
    );

    // Read back transcript then delete it. Both launcher's own
    // stdout/stderr AND the elevated child's transcript go into event.log
    // for diagnosis — the launcher captures UAC-denial / parameter
    // mistakes, the transcript captures what happened inside the elevated
    // session.
    final transcript = _readAndDelete(transcriptPath);
    final launcherOut = '${result.stdout}';
    final launcherErr = '${result.stderr}';
    EventLog.write('[Service] elevated exit=${result.exitCode} '
        'launcher_err=${_truncateForLog(launcherErr)} '
        'launcher_out=${_truncateForLog(launcherOut)} '
        'transcript=${_truncateForLog(transcript)}');

    if (result.exitCode != 0) {
      final detail = launcherErr.trim().isNotEmpty
          ? launcherErr.trim()
          : (transcript.trim().isNotEmpty
              ? transcript.trim()
              : 'Elevated PowerShell exited ${result.exitCode} '
                  '(no transcript — UAC may have been cancelled)');
      throw ProcessException(
        'powershell',
        ['-NoProfile', '-Command', launcher],
        detail,
        result.exitCode,
      );
    }
  }

  static String _macInstallScript({
    required String helperSource,
    required String mihomoSource,
    required String configSource,
  }) {
    return '''
#!/bin/sh
set -eu

SERVICE_DIR=${_shellQuote(_macServiceDir)}
HELPER_SRC=${_shellQuote(helperSource)}
MIHOMO_SRC=${_shellQuote(mihomoSource)}
CONFIG_SRC=${_shellQuote(configSource)}

mkdir -p "${r'$'}SERVICE_DIR"
cp "${r'$'}HELPER_SRC" ${_shellQuote(_macInstalledHelperPath)}
cp "${r'$'}MIHOMO_SRC" ${_shellQuote(_macInstalledMihomoPath)}
cp "${r'$'}CONFIG_SRC" ${_shellQuote(_macInstalledConfigPath)}

chmod 755 ${_shellQuote(_macInstalledHelperPath)} ${_shellQuote(_macInstalledMihomoPath)}
chmod 600 ${_shellQuote(_macInstalledConfigPath)}
chown root:wheel ${_shellQuote(_macInstalledHelperPath)} ${_shellQuote(_macInstalledMihomoPath)} ${_shellQuote(_macInstalledConfigPath)}

cat > ${_shellQuote(_macPlistPath)} <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${AppConstants.desktopServiceLabel}</string>
  <key>ProgramArguments</key>
  <array>
    <string>$_macInstalledHelperPath</string>
    <string>-config</string>
    <string>$_macInstalledConfigPath</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$_macInstalledHelperLogPath</string>
  <key>StandardErrorPath</key>
  <string>$_macInstalledHelperLogPath</string>
</dict>
</plist>
PLIST

chmod 644 ${_shellQuote(_macPlistPath)}
chown root:wheel ${_shellQuote(_macPlistPath)}

launchctl bootout system/${AppConstants.desktopServiceLabel} >/dev/null 2>&1 || true
launchctl bootstrap system ${_shellQuote(_macPlistPath)}
launchctl kickstart -k system/${AppConstants.desktopServiceLabel}
''';
  }

  static String _macUninstallScript() {
    return '''
#!/bin/sh
set -eu

launchctl bootout system/${AppConstants.desktopServiceLabel} >/dev/null 2>&1 || true
rm -f ${_shellQuote(_macPlistPath)}
rm -rf ${_shellQuote(_macServiceDir)}
''';
  }

  static String _windowsInstallScript({
    required String helperSource,
    required String mihomoSource,
    required String configSource,
  }) {
    return r'''
$ErrorActionPreference = "Stop"

$serviceName = '__SERVICE_NAME__'
$serviceDir = __SERVICE_DIR__
$helperSrc = __HELPER_SRC__
$mihomoSrc = __MIHOMO_SRC__
$configSrc = __CONFIG_SRC__
$helperDst = __HELPER_DST__
$mihomoDst = __MIHOMO_DST__
$configDst = __CONFIG_DST__

# Stop and delete the existing service if present.
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
  Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
  sc.exe delete $serviceName | Out-Null
  # sc.exe delete is async — the service stays "marked for deletion" until
  # all open handles close. Poll for actual removal up to 15 s before
  # creating the new service, otherwise New-Service hits error 1072.
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    if (-not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
      break
    }
  }
  if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    Write-Warning "Service '$serviceName' still present after 15s — attempting New-Service anyway"
  }
}

New-Item -ItemType Directory -Force -Path $serviceDir | Out-Null
Copy-Item -Force $helperSrc $helperDst
Copy-Item -Force $mihomoSrc $mihomoDst
Copy-Item -Force $configSrc $configDst

$binPath = '"' + $helperDst + '" -config "' + $configDst + '"'

# Retry New-Service up to 3 times in case the previous deletion is still
# settling in the SCM database.
$created = $false
for ($i = 0; $i -lt 3; $i++) {
  try {
    New-Service -Name $serviceName -BinaryPathName $binPath `
      -DisplayName 'YueLink Service Helper' -StartupType Automatic `
      -Description 'Privileged YueLink desktop TUN helper' | Out-Null
    $created = $true
    break
  } catch {
    if ($i -eq 2) { throw }
    Start-Sleep -Seconds 2
  }
}
if (-not $created) { throw "Failed to create service after 3 attempts" }

# sc.exe description is redundant now (PowerShell New-Service supports it
# via -Description on PS 6+), but kept for older Win 10 hosts that ship
# Windows PowerShell 5.1 where -Description is silently ignored.
sc.exe description $serviceName "Privileged YueLink desktop TUN helper" | Out-Null

Start-Service -Name $serviceName
'''
        .replaceAll('__SERVICE_NAME__', AppConstants.desktopServiceName)
        .replaceAll('__SERVICE_DIR__', _powershellQuoted(_windowsServiceDir))
        .replaceAll('__HELPER_SRC__', _powershellQuoted(helperSource))
        .replaceAll('__MIHOMO_SRC__', _powershellQuoted(mihomoSource))
        .replaceAll('__CONFIG_SRC__', _powershellQuoted(configSource))
        .replaceAll(
            '__HELPER_DST__', _powershellQuoted(_windowsInstalledHelperPath))
        .replaceAll(
            '__MIHOMO_DST__', _powershellQuoted(_windowsInstalledMihomoPath))
        .replaceAll(
            '__CONFIG_DST__', _powershellQuoted(_windowsInstalledConfigPath));
  }

  static String _windowsUninstallScript() {
    return r'''
$ErrorActionPreference = "Stop"
$serviceName = '__SERVICE_NAME__'
$serviceDir = __SERVICE_DIR__

if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
  Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
  sc.exe delete $serviceName | Out-Null
  Start-Sleep -Seconds 1
}

if (Test-Path $serviceDir) {
  Remove-Item -Path $serviceDir -Recurse -Force
}
'''
        .replaceAll('__SERVICE_NAME__', AppConstants.desktopServiceName)
        .replaceAll('__SERVICE_DIR__', _powershellQuoted(_windowsServiceDir));
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  static String _appleScriptEscape(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  static String _powershellQuoted(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }

  static String get _macServiceDir =>
      '/Library/Application Support/YueLink/Service';
  static String get _macInstalledHelperPath =>
      '$_macServiceDir/yuelink-service-helper';
  static String get _macInstalledMihomoPath => '$_macServiceDir/yuelink-mihomo';
  static String get _macInstalledConfigPath =>
      '$_macServiceDir/service-config.json';
  static String get _macInstalledHelperLogPath => '$_macServiceDir/helper.log';
  static String get _macPlistPath =>
      '/Library/LaunchDaemons/${AppConstants.desktopServiceLabel}.plist';
  // Unix domain socket the helper binds to. Lives in /var/run because
  // /tmp is sometimes mode 1777 + auto-cleaned, while /var/run is the
  // canonical macOS daemon socket location.
  static String get _macSocketPath => '/var/run/yuelink-helper.sock';

  // ── Linux socket ────────────────────────────────────────────────────
  static String get _linuxSocketPath => '/run/yuelink-helper.sock';

  /// Current user's UID. On Unix-likes we read it via `id -u` (avoids the
  /// FFI dance for getuid()). On Windows we return -1 — the field is
  /// informational there since auth is bearer-token.
  static int _currentUid() {
    if (Platform.isWindows) return -1;
    try {
      final r = Process.runSync('id', ['-u']);
      if (r.exitCode == 0) {
        final uid = int.tryParse(r.stdout.toString().trim());
        if (uid != null) return uid;
      }
    } catch (_) {}
    return -1;
  }

  static String get _windowsProgramData =>
      Platform.environment['ProgramData'] ?? r'C:\ProgramData';
  static String get _windowsServiceDir =>
      '$_windowsProgramData\\YueLink\\Service';
  static String get _windowsInstalledHelperPath =>
      '$_windowsServiceDir\\yuelink-service-helper.exe';
  static String get _windowsInstalledMihomoPath =>
      '$_windowsServiceDir\\yuelink-mihomo.exe';
  static String get _windowsInstalledConfigPath =>
      '$_windowsServiceDir\\service-config.json';
  static String get _windowsInstalledHelperLogPath =>
      '$_windowsServiceDir\\helper.log';

  // ── Linux paths ────────────────────────────────────────────────────
  static const _linuxServiceDir = '/opt/yuelink-service';
  static String get _linuxInstalledHelperPath =>
      '$_linuxServiceDir/yuelink-service-helper';
  static String get _linuxInstalledMihomoPath =>
      '$_linuxServiceDir/yuelink-mihomo';
  static String get _linuxInstalledConfigPath =>
      '$_linuxServiceDir/service-config.json';
  static String get _linuxInstalledHelperLogPath =>
      '$_linuxServiceDir/helper.log';
  static String get _linuxUnitPath =>
      '/etc/systemd/system/${AppConstants.desktopServiceLabel}.service';

  static String _linuxInstallScript({
    required String helperSource,
    required String mihomoSource,
    required String configSource,
  }) {
    return '''
#!/bin/sh
set -eu

SERVICE_DIR=${_shellQuote(_linuxServiceDir)}
HELPER_SRC=${_shellQuote(helperSource)}
MIHOMO_SRC=${_shellQuote(mihomoSource)}
CONFIG_SRC=${_shellQuote(configSource)}

mkdir -p ${_shellQuote(_linuxServiceDir)}
cp "\$HELPER_SRC" ${_shellQuote(_linuxInstalledHelperPath)}
cp "\$MIHOMO_SRC" ${_shellQuote(_linuxInstalledMihomoPath)}
cp "\$CONFIG_SRC" ${_shellQuote(_linuxInstalledConfigPath)}

chmod 755 ${_shellQuote(_linuxInstalledHelperPath)} ${_shellQuote(_linuxInstalledMihomoPath)}
chmod 600 ${_shellQuote(_linuxInstalledConfigPath)}

cat > ${_shellQuote(_linuxUnitPath)} <<'UNIT'
[Unit]
Description=YueLink Service Helper
After=network.target

[Service]
Type=simple
ExecStart=$_linuxInstalledHelperPath -config $_linuxInstalledConfigPath
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable ${AppConstants.desktopServiceLabel}
systemctl restart ${AppConstants.desktopServiceLabel}
''';
  }

  static String _linuxUninstallScript() {
    return '''
#!/bin/sh
set -eu

systemctl stop ${AppConstants.desktopServiceLabel} >/dev/null 2>&1 || true
systemctl disable ${AppConstants.desktopServiceLabel} >/dev/null 2>&1 || true
rm -f ${_shellQuote(_linuxUnitPath)}
systemctl daemon-reload
rm -rf ${_shellQuote(_linuxServiceDir)}
''';
  }

  /// Read a file's contents then delete it. Returns empty string on any
  /// failure — callers treat "no output" as a diagnostic signal in itself.
  static String _readAndDelete(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return '';
      final content = f.readAsStringSync();
      try { f.deleteSync(); } catch (_) {}
      return content;
    } catch (_) {
      return '';
    }
  }

  /// Cap a potentially long subprocess output for event.log entries.
  /// Full content is still visible via the elevated child's own log path
  /// ($helperLogPath) once service is running.
  static String _truncateForLog(String s) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (one.isEmpty) return '<empty>';
    return one.length > 200 ? '${one.substring(0, 200)}…' : one;
  }

  static Future<void> _runLinuxElevated(String scriptPath) async {
    // Try pkexec first (graphical sudo), fallback to sudo
    for (final elevator in ['pkexec', 'sudo']) {
      try {
        final result =
            await Process.run(elevator, ['/bin/sh', scriptPath]);
        EventLog.write('[Service] $elevator exit=${result.exitCode} '
            'stdout=${_truncateForLog('${result.stdout}')} '
            'stderr=${_truncateForLog('${result.stderr}')}');
        if (result.exitCode == 0) return;
        if (elevator == 'pkexec') continue; // try sudo next
        throw ProcessException(
          elevator,
          ['/bin/sh', scriptPath],
          '${result.stderr}'.trim().isEmpty
              ? '${result.stdout}'.trim()
              : '${result.stderr}'.trim(),
          result.exitCode,
        );
      } catch (e) {
        if (elevator == 'pkexec') continue;
        rethrow;
      }
    }
  }
}

class _ServiceBinaries {
  final String helperPath;
  final String mihomoPath;

  const _ServiceBinaries({
    required this.helperPath,
    required this.mihomoPath,
  });
}
