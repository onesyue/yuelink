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

typedef DesktopTunPrivilegedHelperProbe = Future<bool> Function();

typedef DesktopTunHostResolver =
    Future<List<InternetAddress>> Function(String host);

class DesktopTunDiagnostics {
  DesktopTunDiagnostics({
    DesktopTunProcessRunner? processRunner,
    DesktopTunInterfaceLister? interfaceLister,
    DesktopTunPrivilegedHelperProbe? privilegedHelperProbe,
    DesktopTunHostResolver? hostResolver,
  }) : _processRunner = processRunner ?? _runProcess,
       _interfaceLister = interfaceLister ?? NetworkInterface.list,
       _privilegedHelperProbe =
           privilegedHelperProbe ?? ServiceManager.isInstalled,
       _hostResolver = hostResolver ?? InternetAddress.lookup;

  static final instance = DesktopTunDiagnostics();

  final DesktopTunProcessRunner _processRunner;
  final DesktopTunInterfaceLister _interfaceLister;
  final DesktopTunPrivilegedHelperProbe _privilegedHelperProbe;
  final DesktopTunHostResolver _hostResolver;

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

  /// True when the macOS routing table shows a TUN interface taking the
  /// default route. Looks for the canonical split-default signature mihomo
  /// (and most TUN-mode VPNs) install on macOS — `default`, `0/1`, or
  /// `128.0/1` whose `Netif` column starts with `utun`. The 4th column in
  /// `netstat -rn` output is the interface; matching only on `utun*` there
  /// (instead of "any utun anywhere in the output") avoids the false
  /// positive on machines that have unrelated WireGuard / Tailscale /
  /// Cisco AnyConnect tunnels listed in fe80:: link-local rows.
  ///
  /// Returns the interface name (e.g. `utun6`) when matched so callers can
  /// correlate with [NetworkInterface.list]; null otherwise.
  @visibleForTesting
  static String? macosDefaultRouteTunInterface(String netstatOutput) {
    // Parser is intentionally loose on whitespace because `netstat -rn`
    // pads columns based on the widest entry across the whole table.
    const defaultDestinations = {'default', '0/1', '128.0/1'};
    for (final raw in netstatOutput.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      // Need at least: destination, gateway, flags, netif.
      if (parts.length < 4) continue;
      if (!defaultDestinations.contains(parts[0])) continue;
      final netif = parts[3];
      if (netif.startsWith('utun')) return netif;
    }
    return null;
  }

  /// True when `ip route` output references YueLink's named TUN device
  /// (`dev YueLink` or `dev mihomo`). The previous `dev tun` substring
  /// match treated any `tun0`/`tun1`/etc. from a different VPN as
  /// YueLink's TUN — common on Linux dev boxes that also run wg-quick or
  /// OpenVPN. YueLink's TUN device name is fixed (see
  /// `tun_transformer.dart` for the `device: YueLink` line we inject), so
  /// requiring an exact device match removes the false positive.
  @visibleForTesting
  static bool linuxRouteOutputHasYueLinkTun(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('dev yuelink') ||
        normalized.contains('dev mihomo');
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
    final normalizedMode = _normalizeMode(mode);
    final results = await Future.wait<Object>([
      _hasPrivilege(),
      _driverPresent(),
      _tunInterfacePresent(),
      _routeOk(),
      _dnsOk(api, normalizedMode),
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
      mode: normalizedMode,
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
    // Cleanup-OK uses the route-level signal, not interface enumeration.
    // The interface enumeration on macOS reports `true` for ANY utun the
    // OS has up — including unrelated VPNs (WireGuard, Tailscale, …) the
    // user has running alongside YueLink. Asserting "no utun left" was
    // false-failing every cleanup on multi-VPN machines and writing a
    // bogus `cleanup_failed` snapshot into desktopTunHealthProvider.
    // Routes are the right check: when YueLink's TUN is stopped, mihomo
    // tears down its split-default install (`128.0/1`/`0/1` → utun*),
    // leaving only foreign VPN routes (which we don't care about).
    final ourTunRouteStillPresent = await _routeOk();
    final cleanupOk = !ourTunRouteStillPresent && !systemProxyEnabled;
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
      routeOk: !ourTunRouteStillPresent,
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

  @visibleForTesting
  Future<bool> hasPrivilegeForTesting() => _hasPrivilege();

  @visibleForTesting
  Future<bool> dnsHijackOkForTesting() => _dnsHijackOk();

  Future<bool> _hasPrivilege() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return false;
    }
    try {
      // The privileged helper is the privilege boundary on every desktop
      // platform — launchd plist on macOS, systemd unit on Linux, SCM
      // service on Windows. Probing the calling process for elevation
      // (`net session` on Windows / EUID==0 on Unix) would gate TUN on
      // running the UI as admin, which YueLink never does and never
      // needs to: TUN-mode startup is dispatched through the helper
      // (see `_shouldUseDesktopServiceMode`).
      if (await _privilegedHelperProbe()) return true;
      if (Platform.isWindows) {
        // Legacy fallback for users who launch the UI elevated without
        // a service installed. Without this, an admin-launched UI that
        // intentionally bypasses the helper would be misclassified as
        // missing_permission while the routes/DNS it just installed
        // are functioning.
        final r = await _processRunner('net', const [
          'session',
        ], const Duration(seconds: 3));
        return r.exitCode == 0;
      }
      return false;
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
        if (r.exitCode != 0) return false;
        final out = '${r.stdout}\n${r.stderr}';
        return macosDefaultRouteTunInterface(out) != null;
      }
      if (Platform.isLinux) {
        final r = await _processRunner('ip', const [
          'route',
        ], const Duration(seconds: 4));
        final out = '${r.stdout}\n${r.stderr}'.toLowerCase();
        return r.exitCode == 0 && linuxRouteOutputHasYueLinkTun(out);
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

  /// True when DNS for the current mode is functioning end-to-end.
  ///
  /// In TUN mode the meaningful question is "did mihomo's DNS hijack
  /// actually capture the system's resolver path?" — not "is mihomo's
  /// internal resolver responsive?". The previous probe (`api.queryDns`)
  /// only answered the latter, so a working hijack failed-positive every
  /// time mihomo's upstream DNS or rule-bound proxy node briefly hiccuped
  /// (e.g. respect-rules + a flaky proxy returns no answers), and a
  /// truly-broken hijack false-passed because mihomo can always answer
  /// itself via the REST API.
  ///
  /// The end-to-end probe issues a real `InternetAddress.lookup` and
  /// inspects the returned IPv4. mihomo allocates fake-IPs from
  /// `198.18.0.0/16` (`fake-ip-range` in the injected config), so any
  /// `198.18.x.x` answer proves: (1) the system DNS query actually
  /// reached mihomo, (2) mihomo applied fake-IP, (3) the answer made it
  /// back through the system resolver. If the answer is a real public IP
  /// the hijack didn't intercept the query — system DNS is bypassing the
  /// TUN.
  ///
  /// In non-TUN modes (system_proxy) the hijack mechanism doesn't apply,
  /// so we fall back to the lighter "mihomo's internal resolver is
  /// responsive" probe via `api.queryDns`.
  Future<bool> _dnsOk(MihomoApi api, String normalizedMode) async {
    if (normalizedMode == 'tun') {
      return _dnsHijackOk();
    }
    return _mihomoApiDnsOk(api);
  }

  /// Issues a real system DNS lookup against domains that should reliably
  /// receive a fake-IP under typical YueLink configs. Returns true if any
  /// returned IPv4 falls inside the `198.18.0.0/16` fake-IP range.
  ///
  /// Probing two distinct domains keeps the check robust against a
  /// per-domain `respect-rules: true` decision routing one of them DIRECT
  /// (bypassing fake-IP allocation). Both probes are run sequentially with
  /// short timeouts; total wall-clock is bounded under 10s even when DNS
  /// is wedged.
  Future<bool> _dnsHijackOk() async {
    const probeHosts = ['www.google.com', 'www.youtube.com'];
    for (final host in probeHosts) {
      try {
        final addrs = await _hostResolver(
          host,
        ).timeout(const Duration(seconds: 4));
        if (addrs.any(isFakeIpAddress)) return true;
      } catch (_) {
        // Treat resolver errors (NXDOMAIN, timeout, network down) as
        // "not hijacked"; the next probe host might still succeed.
      }
    }
    return false;
  }

  Future<bool> _mihomoApiDnsOk(MihomoApi api) async {
    try {
      final dns = await api
          .queryDns('www.gstatic.com')
          .timeout(const Duration(seconds: 4));
      final answers = dns['Answer'];
      if (answers is List && answers.isNotEmpty) return true;
    } catch (_) {}
    return false;
  }

  /// True when [addr] is an IPv4 inside mihomo's default fake-IP range
  /// (`198.18.0.0/15`). Range mirrors `tun_transformer.dart` /
  /// `dns_transformer.dart` (`fake-ip-range: 198.18.0.1/16`); the second
  /// `198.19.x.x` half is included so a future bump of the range
  /// (mihomo's docs allow `/15`) doesn't silently break the probe.
  @visibleForTesting
  static bool isFakeIpAddress(InternetAddress addr) {
    if (addr.type != InternetAddressType.IPv4) return false;
    final raw = addr.address;
    return raw.startsWith('198.18.') || raw.startsWith('198.19.');
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
