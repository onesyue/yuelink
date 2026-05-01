import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../infrastructure/datasources/mihomo_api.dart';
import '../managers/system_proxy_manager.dart';
import '../service/service_manager.dart';
import 'desktop_tun_state.dart';

typedef DesktopTunProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      Duration timeout,
    );

typedef DesktopTunInterfaceLister = Future<List<NetworkInterface>> Function();

class DesktopTunDiagnostics {
  DesktopTunDiagnostics({
    DesktopTunProcessRunner? processRunner,
    DesktopTunInterfaceLister? interfaceLister,
  }) : _processRunner = processRunner ?? _runProcess,
       _interfaceLister = interfaceLister ?? NetworkInterface.list;

  static final instance = DesktopTunDiagnostics();

  final DesktopTunProcessRunner _processRunner;
  final DesktopTunInterfaceLister _interfaceLister;

  @visibleForTesting
  static bool looksLikeWindowsTunInterfaceName(String value) {
    final normalized = value.toLowerCase().trim();
    if (normalized.isEmpty) return false;
    if (normalized == 'meta') return true;
    return normalized.contains('meta tunnel') ||
        normalized.contains('wintun') ||
        normalized.contains('yuelink') ||
        normalized.contains('mihomo') ||
        normalized.contains('clash');
  }

  @visibleForTesting
  static bool windowsRouteOutputHasTun(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('meta tunnel')) return true;
    if (RegExp(r'\bmeta\b').hasMatch(normalized)) return true;
    return normalized.contains('wintun') ||
        normalized.contains('yuelink') ||
        normalized.contains('mihomo') ||
        normalized.contains('clash');
  }

  Future<DesktopTunSnapshot> inspect({
    required MihomoApi api,
    required int mixedPort,
    required String mode,
    required String tunStack,
    String? coreVersion,
    bool proxyGuardActive = false,
    double sampleRate = 1.0,
  }) async {
    final sw = Stopwatch()..start();
    final platform = _platformName();
    final results = await Future.wait<Object>([
      _hasPrivilege(),
      _driverPresent(),
      _tunInterfacePresent(),
      _routeOk(),
      _dnsOk(api),
      api.healthSnapshot(),
      _systemProxyEnabled(mixedPort),
      _ipv6Enabled(),
      _httpsReachable('https://www.gstatic.com/generate_204'),
      _httpsReachable('https://github.com/'),
    ]);
    sw.stop();

    final controller = results[5] as ({bool ok, String reason});
    final googleOk = results[8] as bool;
    final githubOk = results[9] as bool;
    final transportOk = controller.ok && (googleOk || githubOk);

    return DesktopTunStateMachine.evaluate(
      platform: platform,
      mode: _normalizeMode(mode),
      tunStack: tunStack,
      hasAdmin: results[0] as bool,
      driverPresent: results[1] as bool,
      interfacePresent: results[2] as bool,
      routeOk: results[3] as bool,
      dnsOk: results[4] as bool,
      ipv6Enabled: results[7] as bool,
      controllerOk: controller.ok,
      systemProxyEnabled: results[6] as bool,
      proxyGuardActive: proxyGuardActive,
      transportOk: transportOk,
      googleOk: googleOk,
      githubOk: githubOk,
      coreVersion: coreVersion,
      elapsedMs: sw.elapsedMilliseconds,
      sampleRate: sampleRate,
      detail: controller.reason == 'ok' ? null : controller.reason,
    );
  }

  Future<DesktopTunSnapshot> cleanupSnapshot({
    required int mixedPort,
    required String mode,
    required String tunStack,
    String? coreVersion,
  }) async {
    final platform = _platformName();
    final interfacePresent = await _tunInterfacePresent();
    final systemProxyEnabled = await _systemProxyEnabled(mixedPort);
    final cleanupOk = !interfacePresent && !systemProxyEnabled;
    final state = cleanupOk
        ? DesktopTunState.off
        : DesktopTunState.cleanupFailed;
    return DesktopTunSnapshot(
      state: state,
      platform: platform,
      mode: _normalizeMode(mode),
      tunStack: tunStack,
      hasAdmin: await _hasPrivilege(),
      driverPresent: await _driverPresent(),
      interfacePresent: interfacePresent,
      routeOk: !interfacePresent,
      dnsOk: !systemProxyEnabled,
      ipv6Enabled: await _ipv6Enabled(),
      controllerOk: false,
      systemProxyEnabled: systemProxyEnabled,
      proxyGuardActive: false,
      transportOk: false,
      googleOk: false,
      githubOk: false,
      errorClass: cleanupOk ? 'ok' : 'cleanup_failed',
      userMessage: cleanupOk ? 'TUN 已停止' : 'TUN 停止后仍有路由/DNS/代理残留',
      repairAction: cleanupOk ? 'none' : 'cleanup_and_restart',
      coreVersion: coreVersion,
    );
  }

  Future<bool> _hasPrivilege() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return false;
    }
    try {
      if (Platform.isWindows) {
        final r = await _processRunner('net', const [
          'session',
        ], const Duration(seconds: 3));
        return r.exitCode == 0;
      }
      // The privileged helper is the privilege boundary on macOS/Linux.
      return await ServiceManager.isInstalled();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _driverPresent() async {
    try {
      if (Platform.isWindows) return _findWindowsWintunDll().isNotEmpty;
      if (Platform.isLinux) return File('/dev/net/tun').existsSync();
      if (Platform.isMacOS) return await ServiceManager.isInstalled();
      return false;
    } catch (_) {
      return false;
    }
  }

  List<String> _findWindowsWintunDll() {
    if (!Platform.isWindows) return const [];
    final execDir = File(Platform.resolvedExecutable).parent.path;
    final cwd = Directory.current.path;
    final candidates = [
      '$execDir\\wintun.dll',
      '$cwd\\windows\\libs\\amd64\\wintun.dll',
      '$cwd\\windows\\libs\\arm64\\wintun.dll',
      '$cwd\\service\\build\\windows-amd64\\wintun.dll',
      '$cwd\\service\\build\\windows-arm64\\wintun.dll',
    ];
    return candidates.where((p) => File(p).existsSync()).toList();
  }

  Future<bool> _tunInterfacePresent() async {
    try {
      final interfaces = await _interfaceLister().timeout(
        const Duration(seconds: 2),
      );
      return interfaces.any((iface) {
        final name = iface.name.toLowerCase();
        if (Platform.isMacOS) return name.startsWith('utun');
        if (Platform.isLinux) {
          return name.startsWith('tun') ||
              name.contains('mihomo') ||
              name.contains('yuelink');
        }
        if (Platform.isWindows) {
          return looksLikeWindowsTunInterfaceName(name);
        }
        return false;
      });
    } catch (_) {
      return false;
    }
  }

  Future<bool> _routeOk() async {
    try {
      if (Platform.isMacOS) {
        final r = await _processRunner('netstat', const [
          '-rn',
        ], const Duration(seconds: 4));
        final out = '${r.stdout}\n${r.stderr}'.toLowerCase();
        return r.exitCode == 0 && out.contains('utun');
      }
      if (Platform.isLinux) {
        final r = await _processRunner('ip', const [
          'route',
        ], const Duration(seconds: 4));
        final out = '${r.stdout}\n${r.stderr}'.toLowerCase();
        return r.exitCode == 0 &&
            (out.contains(' tun') ||
                out.contains('dev tun') ||
                out.contains('mihomo') ||
                out.contains('yuelink'));
      }
      if (Platform.isWindows) {
        final r = await _processRunner('route', const [
          'print',
        ], const Duration(seconds: 6));
        final out = '${r.stdout}\n${r.stderr}'.toLowerCase();
        return r.exitCode == 0 && windowsRouteOutputHasTun(out);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _dnsOk(MihomoApi api) async {
    try {
      final dns = await api
          .queryDns('www.gstatic.com')
          .timeout(const Duration(seconds: 4));
      final answers = dns['Answer'];
      if (answers is List && answers.isNotEmpty) return true;
    } catch (_) {}
    return false;
  }

  Future<bool> _systemProxyEnabled(int mixedPort) async {
    try {
      final verified = await SystemProxyManager.verify(
        mixedPort,
        force: true,
      ).timeout(const Duration(seconds: 5));
      return verified == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ipv6Enabled() async {
    try {
      final interfaces = await _interfaceLister().timeout(
        const Duration(seconds: 2),
      );
      return interfaces.any(
        (iface) => iface.addresses.any(
          (addr) =>
              addr.type == InternetAddressType.IPv6 &&
              !addr.isLoopback &&
              !addr.isLinkLocal,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _httpsReachable(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..findProxy = (_) => 'DIRECT';
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      await resp.drain<void>();
      return resp.statusCode < 500;
    } catch (e) {
      debugPrint('[DesktopTunDiagnostics] reachability $url failed: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static String _platformName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return Platform.operatingSystem;
  }

  static String _normalizeMode(String value) =>
      value == 'systemProxy' ? 'system_proxy' : value;

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
    Duration timeout,
  ) async {
    try {
      return await Process.run(executable, arguments).timeout(timeout);
    } on TimeoutException {
      return ProcessResult(0, -1, '', 'timeout');
    }
  }
}
