import 'dart:io';

import 'yaml_helpers.dart';

class ScalarTransformers {
  const ScalarTransformers._();

  static final _reExtController = RegExp(
    r'^(external-controller:\s*).*$',
    multiLine: true,
  );
  static final _reMixedPort = RegExp(r'^mixed-port:\s*(\d+)', multiLine: true);

  /// Ensure the config has mixed-port set.
  ///
  /// mihomo silently skips creating the HTTP+SOCKS proxy listener when
  /// mixed-port is 0 (not set). Without it, system proxy on macOS/Windows
  /// points to a port where nobody is listening, and all proxy traffic fails.
  static String ensureMixedPort(String config, int port) {
    if (hasKey(config, 'mixed-port')) return config;
    return '$config\nmixed-port: $port\n';
  }

  /// Force-set mixed-port, replacing an existing value if present.
  /// Used by CoreManager to remap the port when it is already in use.
  static String setMixedPort(String config, int port) {
    if (hasKey(config, 'mixed-port')) {
      return config.replaceAllMapped(_reMixedPort, (_) => 'mixed-port: $port');
    }
    return '$config\nmixed-port: $port\n';
  }

  /// Ensure the config has external-controller set.
  static String ensureExternalController(
    String config,
    int port,
    String? secret,
  ) {
    if (hasKey(config, 'external-controller')) {
      config = config.replaceAllMapped(
        _reExtController,
        (m) => '${m.group(1)}127.0.0.1:$port',
      );
    } else {
      config += '\nexternal-controller: 127.0.0.1:$port\n';
    }

    if (secret != null && secret.isNotEmpty && !hasKey(config, 'secret')) {
      config += 'secret: $secret\n';
    }

    return config;
  }

  /// Ensure allow-lan for mixed-port to listen on all interfaces.
  static String ensureAllowLan(String config) {
    if (!hasKey(config, 'allow-lan')) {
      config += '\nallow-lan: true\n';
    }
    if (!hasKey(config, 'bind-address')) {
      config += 'bind-address: "*"\n';
    }
    return config;
  }

  /// Disable IPv6 — mihomo TUN only has inet4-address, and Android VpnService
  /// only routes IPv4. Enabling IPv6 causes resolution failures.
  static String ensureIpv6(String config) {
    if (!hasKey(config, 'ipv6')) {
      config += '\nipv6: false\n';
    }
    return config;
  }

  static String ensureMode(String config) {
    if (!hasKey(config, 'mode')) {
      config += '\nmode: rule\n';
    }
    return config;
  }

  /// Ensure find-process-mode based on platform.
  ///   * Mobile (Android/iOS): off — no permission, avoids useless overhead.
  ///   * Windows: strict — see [defaultFindProcessMode] docstring.
  ///   * macOS / Linux: always — preserves split-tunnel-by-process UX.
  static String ensureFindProcessMode(String config) {
    if (hasKey(config, 'find-process-mode')) {
      // On mobile, force off regardless of subscription setting
      if (Platform.isAndroid || Platform.isIOS) {
        config = replaceScalar(config, 'find-process-mode', 'off');
      }
      return config;
    }
    return '$config\nfind-process-mode: ${defaultFindProcessMode()}\n';
  }

  /// Default `find-process-mode` for the current platform.
  ///
  /// v1.0.22 P1-2: Windows shifts from `always` to `strict` to fix the
  /// "Win 下载软件一直断开链接" report — `always` resolves the
  /// originating process for every connection (a Windows
  /// QueryFullProcessImageName + handle resolution per packet flow),
  /// which is hostile to high-frequency download tools that spawn
  /// short-lived helper processes (IDM/迅雷/Steam). `strict` only
  /// performs the lookup when a rule actually references
  /// `PROCESS-NAME`, eliminating the per-flow cost without affecting
  /// rule-based routing. macOS / Linux retain `always` until / unless
  /// similar reports surface there. Mobile is `off` (no permission).
  static String defaultFindProcessMode() {
    if (Platform.isAndroid || Platform.isIOS) return 'off';
    if (Platform.isWindows) return 'strict';
    return 'always';
  }
}
