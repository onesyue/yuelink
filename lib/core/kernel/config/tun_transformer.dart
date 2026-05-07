import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../constants.dart';
import 'scalar_transformers.dart';
import 'yaml_helpers.dart';
import 'yaml_indent_detector.dart';

/// Test-only struct for forcing platform branches in
/// [TunTransformer.buildDesktopTunYaml]. Production callers never pass
/// this — `Platform.isWindows / isLinux` are read at runtime instead.
@visibleForTesting
class TunPlatform {
  final bool isWindows;
  final bool isLinux;
  const TunPlatform({required this.isWindows, required this.isLinux});

  static const windows = TunPlatform(isWindows: true, isLinux: false);
  static const linux = TunPlatform(isWindows: false, isLinux: true);
  static const macos = TunPlatform(isWindows: false, isLinux: false);
}

class TunTransformer {
  const TunTransformer._();

  static final _reEnableTrue = RegExp(r'\benable:\s*true');

  /// Disable TUN on desktop platforms where system proxy is used instead.
  static String disableTun(String config) {
    if (!hasKey(config, 'tun')) return config;
    final range = YamlIndentDetector.findTopLevelSection(config, 'tun');
    if (range == null) return config;

    final tunSection = config.substring(range.start, range.end);
    if (!_reEnableTrue.hasMatch(tunSection)) return config;

    final newSection = tunSection.replaceFirst(_reEnableTrue, 'enable: false');
    return config.substring(0, range.start) +
        newSection +
        config.substring(range.end);
  }

  /// Pure function: compute the `strict-route` value from the two
  /// inputs that influence it. Exported separately so unit tests on
  /// non-Windows hosts (CI runs on Mac/Linux) can still exercise the
  /// Windows branch without faking `Platform.isWindows`.
  ///
  /// Contract (P2-1):
  ///   * Windows + lanCompat off → `true` (safer, may break LAN access)
  ///   * Windows + lanCompat on  → `false` (LAN-friendly)
  ///   * non-Windows + any       → `false`
  static bool computeStrictRoute({
    required bool isWindows,
    required bool windowsLanCompatibilityMode,
  }) {
    return isWindows && !windowsLanCompatibilityMode;
  }

  /// Build the desktop `tun:` YAML section as a pure function.
  ///
  /// **No I/O, no SettingsService dependency, no Riverpod.** All user
  /// preferences enter through parameters so the builder can be reused
  /// from cold-start ([ensureDesktopTun]) and any future hot-switch /
  /// patch path without behaviour drift.
  ///
  /// Returns a multi-line string starting with `tun:\n` and ending with
  /// a trailing newline. Caller is responsible for joining it onto the
  /// rest of the config (see [ensureDesktopTun] for the canonical
  /// orchestration: remove old tun section → set find-process-mode →
  /// ensure fake-ip + bypass rules + ipv6 → append this builder's
  /// output).
  ///
  /// `windowsLanCompatibilityMode` (P2-1):
  ///   * `false` (default) → Windows gets `strict-route: true` (more
  ///     secure: prevents apps from binding outbound traffic onto
  ///     non-TUN interfaces; can break LAN file shares / printers /
  ///     remote-desktop into intranet).
  ///   * `true` → Windows gets `strict-route: false` (LAN-friendly,
  ///     equivalent to Clash Verge Rev's default; small risk of
  ///     selective leak via apps that explicitly bind a NIC).
  ///
  /// `platformOverrideForTest` (test-only, default null):
  ///   When set, replaces `Platform.is{Windows,Linux}` in the strict-route
  ///   branch and the `device: YueLink` emission. Production callers
  ///   never pass this — leave null.
  static String buildDesktopTunYaml({
    required String stack,
    List<String> bypassAddresses = const [],
    bool windowsLanCompatibilityMode = false,
    @visibleForTesting TunPlatform? platformOverrideForTest,
  }) {
    final isWindows = platformOverrideForTest?.isWindows ?? Platform.isWindows;
    final isLinux = platformOverrideForTest?.isLinux ?? Platform.isLinux;
    final normalizedStack = switch (stack) {
      'system' => 'system',
      'gvisor' => 'gvisor',
      _ => 'mixed',
    };
    final strictRoute = computeStrictRoute(
      isWindows: isWindows,
      windowsLanCompatibilityMode: windowsLanCompatibilityMode,
    );

    final buf = StringBuffer()
      ..write('tun:\n')
      ..write('  enable: true\n')
      ..write('  stack: $normalizedStack\n');
    if (isWindows || isLinux) {
      buf.write('  device: YueLink\n');
    }
    buf
      ..write('  auto-route: true\n')
      ..write('  auto-detect-interface: true\n')
      ..write('  strict-route: $strictRoute\n')
      // IPv6 plumbing: without `inet6-address` mihomo's auto-route only
      // installs IPv4 split-default routes (`0.0.0.0/1` + `128.0.0.0/1`),
      // leaving IPv6 default route on the user's physical interface. An
      // app issuing a direct IPv6 connection (or hitting an AAAA record
      // it received pre-TUN from system DNS cache) bypasses the TUN
      // entirely and leaks the user's real IPv6 address. Assigning a
      // ULA to the TUN + enabling inet6-route is the same pattern
      // upstream mihomo and FlClash use for desktop TUN.
      //
      // The ULA `fdfe:dcba:9876::1/126` is private (RFC 4193) and
      // never routable on the public Internet; it's just a transport
      // address for the TUN endpoint, mirroring `inet4-address` semantics.
      ..write('  inet6-address:\n')
      ..write('    - fdfe:dcba:9876::1/126\n')
      ..write('  dns-hijack:\n')
      ..write('    - any:53\n')
      ..write('    - tcp://any:53\n')
      ..write('  mtu: ${AppConstants.defaultTunMtu}\n');

    if (bypassAddresses.isNotEmpty) {
      buf.write('  route-exclude-address:\n');
      for (final addr in bypassAddresses) {
        buf.write('    - $addr\n');
      }
    }

    return buf.toString();
  }

  /// Inject desktop-safe TUN configuration for macOS/Windows/Linux.
  static String ensureDesktopTun(
    String config,
    String stack, {
    List<String> bypassAddresses = const [],
    List<String> bypassProcesses = const [],
    bool windowsLanCompatibilityMode = false,
  }) {
    if (hasKey(config, 'tun')) {
      config = _removeSection(config, 'tun');
    }

    final defaultMode = ScalarTransformers.defaultFindProcessMode();
    if (hasKey(config, 'find-process-mode')) {
      config = replaceScalar(config, 'find-process-mode', defaultMode);
    } else {
      config += '\nfind-process-mode: $defaultMode\n';
    }

    config = _ensureFakeIpForTun(config);
    config = _ensureProcessBypassRules(config, bypassProcesses);

    // Override the global `ipv6: false` that ScalarTransformers.ensureIpv6
    // would otherwise leave in place. That default is the right call for
    // Android (VpnService.Builder routes IPv4 only) and for desktop
    // systemProxy mode (apps connect to the IPv4 mixed-port socket
    // anyway), but in desktop TUN mode we DO want mihomo to process
    // IPv6: we just assigned a ULA to the TUN below, and without
    // top-level `ipv6: true` mihomo's DNS handler refuses AAAA queries
    // and `auto-route` skips the IPv6 route install — meaning the IPv6
    // hijack we set up via inet6-address is dead on arrival, and the
    // user's real IPv6 still leaks via the system default IPv6 route.
    if (hasKey(config, 'ipv6')) {
      config = replaceScalar(config, 'ipv6', 'true');
    } else {
      config += '\nipv6: true\n';
    }

    return '$config\n${buildDesktopTunYaml(
      stack: stack,
      bypassAddresses: bypassAddresses,
      windowsLanCompatibilityMode: windowsLanCompatibilityMode,
    )}';
  }

  /// Inject Android-safe TUN configuration with the VpnService file descriptor.
  static String injectTunFd(String config, int fd) {
    if (hasKey(config, 'tun')) {
      config = _removeSection(config, 'tun');
    }

    if (hasKey(config, 'find-process-mode')) {
      config = replaceScalar(config, 'find-process-mode', 'off');
    }

    return '$config\ntun:\n'
        '  enable: true\n'
        '  stack: gvisor\n'
        '  file-descriptor: $fd\n'
        '  inet4-address:\n'
        '    - 172.19.0.1/30\n'
        '  mtu: ${AppConstants.defaultTunMtu}\n'
        '  auto-route: false\n'
        '  auto-detect-interface: false\n'
        '  dns-hijack:\n'
        '    - any:53\n';
  }

  static String _ensureFakeIpForTun(String config) {
    if (!hasKey(config, 'dns')) {
      return config;
    }

    final range = YamlIndentDetector.findTopLevelSection(config, 'dns');
    if (range == null) return config;

    var dnsSection = config.substring(range.start, range.end);

    final enhancedRe = RegExp(r'enhanced-mode:\s*\S+');
    if (enhancedRe.hasMatch(dnsSection)) {
      dnsSection = dnsSection.replaceFirst(
        enhancedRe,
        'enhanced-mode: fake-ip',
      );
    } else {
      final indent = YamlIndentDetector.detectChildIndent(
        bodyOf(dnsSection),
        allowTabs: false,
      );
      dnsSection = dnsSection.replaceFirst(
        'dns:\n',
        'dns:\n${indent}enhanced-mode: fake-ip\n',
      );
    }

    if (!dnsSection.contains('fake-ip-range')) {
      final indent = YamlIndentDetector.detectChildIndent(
        bodyOf(dnsSection),
        allowTabs: false,
      );
      dnsSection = dnsSection.replaceFirst(
        'enhanced-mode: fake-ip\n',
        'enhanced-mode: fake-ip\n${indent}fake-ip-range: 198.18.0.1/16\n',
      );
    }

    return config.substring(0, range.start) +
        dnsSection +
        config.substring(range.end);
  }

  static String _ensureProcessBypassRules(
    String config,
    List<String> processNames,
  ) {
    final cleaned = processNames
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && !p.contains('\n') && !p.contains(','))
        .toSet()
        .toList(growable: false);
    if (cleaned.isEmpty) return config;

    final rulesRange = YamlIndentDetector.findTopLevelSection(
      config,
      'rules',
      requireBlockHeader: true,
    );
    if (rulesRange == null) return config;

    final rulesBody = config.substring(rulesRange.bodyStart);
    final ruleIndent = YamlIndentDetector.detectListItemIndent(
      rulesBody,
      allowTabs: true,
    );

    var injection = '';
    for (final proc in cleaned) {
      final rule = 'PROCESS-NAME,$proc,DIRECT';
      if (!rulesBody.contains(rule)) {
        injection += '$ruleIndent- "$rule"\n';
      }
    }
    if (injection.isEmpty) return config;

    return config.substring(0, rulesRange.bodyStart) +
        injection +
        config.substring(rulesRange.bodyStart);
  }

  static String _removeSection(String config, String key) {
    final range = YamlIndentDetector.findTopLevelSection(config, key);
    if (range == null) return config;
    return config.substring(0, range.start) + config.substring(range.end);
  }
}
