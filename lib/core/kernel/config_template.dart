import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

import '../../constants.dart';

/// Processes mihomo configs from subscription providers.
///
/// Subscriptions (机场) typically deliver a **complete** config with
/// proxies, proxy-groups, rules, rule-providers, DNS, etc.
/// The app only needs to:
/// 1. Replace template variables (`$app_name` -> `YueLink`)
/// 2. Ensure critical keys are set for core functionality
///
/// The bundled `default_config.yaml` is a **complete fallback** used
/// when a subscription provides raw proxy nodes without groups/rules.
class ConfigTemplate {
  /// Prefix for temporary per-node wrapper groups injected for chain proxy.
  /// Groups are named _YueLink_Chain_0, _YueLink_Chain_1, …
  static const chainGroupPrefix = '_YueLink_Chain_';
  ConfigTemplate._();

  /// Template variables and their replacement values.
  static const _variables = {
    r'$app_name': AppConstants.appName,
  };

  // Cached RegExp patterns
  static final _reTunKey = RegExp(r'^tun:', multiLine: true);
  static final _reDnsKey = RegExp(r'^dns:', multiLine: true);

  /// Matches a top-level YAML key (non-whitespace, non-comment at line start).
  /// Excludes `#` comment lines which are not section boundaries.
  static final _reTopLevel = RegExp(r'^[^\s#]', multiLine: true);
  static final _reEnableTrue = RegExp(r'\benable:\s*true');
  static final _reEnableFalse = RegExp(r'\benable:\s*false');
  static final _reExtController =
      RegExp(r'^(external-controller:\s*).*$', multiLine: true);
  static final _reMixedPort = RegExp(r'^mixed-port:\s*(\d+)', multiLine: true);
  static final _reApiPort =
      RegExp(r'^external-controller:\s*[\w.]*:(\d+)', multiLine: true);
  static final _reSecret =
      RegExp(r'^secret:\s*["\x27]?(.+?)["\x27]?\s*$', multiLine: true);
  static final _reProxiesSection = RegExp(r'^proxies:\s*\n', multiLine: true);

  /// Process a raw config from a subscription.
  ///
  /// Ensures all critical config keys are present for reliable operation
  /// across all platforms. Uses "ensure" pattern: only injects when missing,
  /// never overwrites subscription-provided settings.
  /// Validate that a string is parseable YAML. Returns null on success,
  /// or an error message on failure.
  static String? validateYaml(String yaml) {
    try {
      loadYaml(yaml);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static String process(
    String rawConfig, {
    int apiPort = AppConstants.defaultApiPort,
    int mixedPort = AppConstants.defaultMixedPort,
    String? secret,
    String connectionMode = 'systemProxy',
    String desktopTunStack = AppConstants.defaultDesktopTunStack,
    List<String> tunBypassAddresses = const [],
    List<String> tunBypassProcesses = const [],
    int? tunFd,
  }) {
    var config = rawConfig;

    debugPrint('[Config] process start, len=${config.length}');

    // Pre-validate input YAML to catch broken subscription configs early
    final yamlError = validateYaml(config);
    if (yamlError != null) {
      debugPrint('[Config] WARNING: input YAML is malformed: $yamlError');
      // Don't throw — some subscription configs have minor YAML issues that
      // mihomo's parser tolerates. Log and proceed; if it's truly broken,
      // StartCore will surface the real error.
    }

    // Replace template variables
    for (final entry in _variables.entries) {
      config = config.replaceAll(entry.key, entry.value);
    }
    debugPrint('[Config] 1 variables done');

    config = _ensureMixedPort(config, mixedPort);
    debugPrint('[Config] 2 mixedPort done');

    config = _ensureExternalController(config, apiPort, secret);
    debugPrint('[Config] 3 externalController done');

    config = _ensureDns(config);
    debugPrint('[Config] 4 dns done');

    config = _ensureSniffer(config);
    debugPrint('[Config] 5 sniffer done');

    config = _ensureGeodata(config);
    debugPrint('[Config] 6 geodata done');

    config = _ensureProfile(config);
    debugPrint('[Config] 7 profile done');

    config = _ensurePerformance(config);
    debugPrint('[Config] 8 performance done');

    config = _ensureAllowLan(config);
    debugPrint('[Config] 9 allowLan done');

    // Disable IPv6 — mihomo TUN only has inet4-address, and Android
    // VpnService only routes IPv4. Enabling IPv6 causes resolution failures.
    if (!_hasKey(config, 'ipv6')) {
      config += '\nipv6: false\n';
    }

    config = _ensureFindProcessMode(config);
    debugPrint('[Config] 10 findProcessMode done');

    config = _ensureConnectivityRules(config);
    debugPrint('[Config] 10b connectivityRules done');

    if (!_hasKey(config, 'mode')) {
      config += '\nmode: rule\n';
    }
    debugPrint('[Config] 11 mode done');

    if (Platform.isMacOS || Platform.isWindows) {
      if (connectionMode == 'tun') {
        config = _ensureDesktopTun(
          config,
          desktopTunStack,
          bypassAddresses: tunBypassAddresses,
          bypassProcesses: tunBypassProcesses,
        );
      } else {
        config = _disableTun(config);
      }
    }
    debugPrint('[Config] 12 desktopTun done');

    if (tunFd != null && tunFd > 0) {
      config = _injectTunFd(config, tunFd);
    }
    debugPrint('[Config] 13 tunFd done');

    return config;
  }

  /// Inject an upstream proxy (e.g. soft router) so mihomo routes outbound
  /// connections through it. Adds a `_upstream` proxy entry and sets
  /// `dialer-proxy: _upstream` on all user-defined proxies.
  static String injectUpstreamProxy(
      String config, String type, String server, int port) {
    try {
      final yaml = loadYaml(config);
      if (yaml is! YamlMap) return config;
      final mutable = _toMutable(yaml) as Map<String, dynamic>;

      final proxies = (mutable['proxies'] as List<dynamic>?)?.cast<dynamic>() ??
          <dynamic>[];
      proxies.removeWhere((p) => p is Map && p['name'] == '_upstream');
      proxies.insert(0, <String, dynamic>{
        'name': '_upstream',
        'type': type,
        'server': server,
        'port': port,
        'udp': true,
      });
      for (final proxy in proxies) {
        if (proxy is Map<String, dynamic> && proxy['name'] != '_upstream') {
          proxy['dialer-proxy'] = '_upstream';
        }
      }
      mutable['proxies'] = proxies;

      return YamlWriter().write(mutable);
    } catch (_) {
      return config;
    }
  }

  /// Inject a proxy chain by setting `dialer-proxy` directly on proxy nodes.
  ///
  /// mihomo only allows `dialer-proxy` on proxy nodes in `proxies:`, NOT on
  /// proxy-groups. For chain [A, B, C]:
  ///   - A (entry): unchanged
  ///   - B: dialer-proxy: A   (B connects through A)
  ///   - C (exit): dialer-proxy: B  (C → B → A)
  ///
  /// After calling this, the caller should select the exit node (chainNames.last)
  /// in the active proxy group via the REST API.
  static String injectProxyChain(
      String config, List<String> chainNames, String activeGroup,
      {List<Map<String, dynamic>>? externalProxies}) {
    if (chainNames.length < 2) return config;
    try {
      final yaml = loadYaml(config);
      if (yaml is! YamlMap) return config;
      final mutable = _toMutable(yaml) as Map<String, dynamic>;

      final proxies = (mutable['proxies'] as List<dynamic>?)?.cast<dynamic>() ??
          <dynamic>[];
      final proxyGroups =
          (mutable['proxy-groups'] as List<dynamic>?)?.cast<dynamic>() ??
              <dynamic>[];

      // Strip any existing chain dialer-proxy on nodes (idempotent re-inject).
      // Preserve _upstream dialer-proxy (soft-router pass-through feature).
      for (final p in proxies) {
        if (p is Map<String, dynamic> && p['dialer-proxy'] != '_upstream') {
          p.remove('dialer-proxy');
        }
      }

      // Remove stale _YueLink_Chain_* wrapper groups (backward compat with
      // the old proxy-group-based implementation).
      proxyGroups.removeWhere(
          (g) => g is Map && _isChainGroup(g['name'] as String? ?? ''));
      for (final g in proxyGroups) {
        if (g is Map<String, dynamic>) {
          final gp = (g['proxies'] as List<dynamic>?)?.toList();
          if (gp != null) {
            final before = gp.length;
            gp.removeWhere((p) => _isChainGroup(p as String? ?? ''));
            if (gp.length != before) g['proxies'] = gp;
          }
        }
      }

      // Merge external proxies (from other subscriptions) into the proxies list.
      if (externalProxies != null && externalProxies.isNotEmpty) {
        final existingNames =
            proxies.whereType<Map<String, dynamic>>().map((p) => p['name']).toSet();
        for (final ep in externalProxies) {
          if (ep['name'] != null && !existingNames.contains(ep['name'])) {
            proxies.add(Map<String, dynamic>.from(ep));
            existingNames.add(ep['name']);
          }
        }
      }

      // Verify that the active group exists in this config.
      final hasGroup = proxyGroups
          .any((g) => g is Map<String, dynamic> && g['name'] == activeGroup);
      if (!hasGroup) return config;

      // Set dialer-proxy on nodes[1..N-1]: each node dials through the previous.
      for (var i = 1; i < chainNames.length; i++) {
        for (final p in proxies) {
          if (p is Map<String, dynamic> && p['name'] == chainNames[i]) {
            p['dialer-proxy'] = chainNames[i - 1];
            break;
          }
        }
      }

      mutable['proxies'] = proxies;
      mutable['proxy-groups'] = proxyGroups;
      return YamlWriter().write(mutable);
    } catch (e) {
      debugPrint('[ConfigTemplate] injectProxyChain error: $e');
      return config;
    }
  }

  /// Remove all chain wrapper groups and their entries from every proxy-group.
  /// Also strips any legacy dialer-proxy on raw proxy nodes (backward compat).
  static String removeProxyChain(String config) {
    try {
      final yaml = loadYaml(config);
      if (yaml is! YamlMap) return config;
      final mutable = _toMutable(yaml) as Map<String, dynamic>;

      final proxies = (mutable['proxies'] as List<dynamic>?)?.cast<dynamic>() ??
          <dynamic>[];
      final proxyGroups =
          (mutable['proxy-groups'] as List<dynamic>?)?.cast<dynamic>() ??
              <dynamic>[];

      // Strip legacy dialer-proxy on raw proxy nodes (backward compat)
      for (final p in proxies) {
        if (p is Map<String, dynamic> && p['dialer-proxy'] != '_upstream') {
          p.remove('dialer-proxy');
        }
      }

      // Remove chain entries from every group's proxies list
      for (final g in proxyGroups) {
        if (g is Map<String, dynamic>) {
          final gp = (g['proxies'] as List<dynamic>?)?.toList();
          if (gp != null) {
            final before = gp.length;
            gp.removeWhere((p) => _isChainGroup(p as String? ?? ''));
            if (gp.length != before) g['proxies'] = gp;
          }
        }
      }

      // Remove all chain wrapper groups
      proxyGroups.removeWhere(
          (g) => g is Map && _isChainGroup(g['name'] as String? ?? ''));

      mutable['proxies'] = proxies;
      if (proxyGroups.isNotEmpty) mutable['proxy-groups'] = proxyGroups;
      return YamlWriter().write(mutable);
    } catch (e) {
      debugPrint('[ConfigTemplate] removeProxyChain error: $e');
      return config;
    }
  }

  /// Extract proxy definitions from a config YAML string.
  /// Returns a list of proxy maps (each containing at least 'name').
  /// Returns an empty list if the YAML is malformed or has no proxies.
  static List<Map<String, dynamic>> extractProxies(String configYaml) {
    try {
      final yaml = loadYaml(configYaml);
      if (yaml is! YamlMap) return [];
      final rawProxies = yaml['proxies'];
      if (rawProxies is! YamlList) return [];
      final result = <Map<String, dynamic>>[];
      for (final p in rawProxies) {
        if (p is YamlMap) {
          result.add(_toMutable(p) as Map<String, dynamic>);
        }
      }
      return result;
    } catch (e) {
      debugPrint('[ConfigTemplate] extractProxies error: $e');
      return [];
    }
  }

  /// Extract proxy names from a config YAML string.
  /// Lighter than [extractProxies] — only returns the name strings.
  static List<String> extractProxyNames(String configYaml) {
    try {
      final yaml = loadYaml(configYaml);
      if (yaml is! YamlMap) return [];
      final rawProxies = yaml['proxies'];
      if (rawProxies is! YamlList) return [];
      final result = <String>[];
      for (final p in rawProxies) {
        if (p is YamlMap && p['name'] is String) {
          result.add(p['name'] as String);
        }
      }
      return result;
    } catch (e) {
      debugPrint('[ConfigTemplate] extractProxyNames error: $e');
      return [];
    }
  }

  static bool _isChainGroup(String name) => name.startsWith(chainGroupPrefix);

  static dynamic _toMutable(dynamic value) {
    if (value is YamlMap) {
      return Map<String, dynamic>.fromEntries(
        value.entries
            .map((e) => MapEntry(e.key.toString(), _toMutable(e.value))),
      );
    } else if (value is YamlList) {
      return value.map(_toMutable).toList();
    }
    return value;
  }

  /// Disable TUN on desktop platforms where system proxy is used instead.
  static String _disableTun(String config) {
    if (!_hasKey(config, 'tun')) return config;
    // Find the tun section and replace enable: true → false within it.
    // Use string operations to avoid catastrophic backtracking on large configs.
    final tunMatch = _reTunKey.firstMatch(config);
    if (tunMatch == null) return config;

    final afterTunLine = config.indexOf('\n', tunMatch.start);
    final afterTun = afterTunLine >= 0 ? afterTunLine + 1 : config.length;
    final nextTopLevel = _reTopLevel.firstMatch(config.substring(afterTun));
    final tunEnd =
        nextTopLevel != null ? afterTun + nextTopLevel.start : config.length;

    final tunSection = config.substring(tunMatch.start, tunEnd);
    if (!_reEnableTrue.hasMatch(tunSection)) return config;

    final newSection = tunSection.replaceFirst(_reEnableTrue, 'enable: false');
    return config.substring(0, tunMatch.start) +
        newSection +
        config.substring(tunEnd);
  }

  /// Inject desktop-safe TUN configuration for macOS/Windows.
  ///
  /// Unlike Android, desktop platforms let mihomo create and manage the TUN
  /// device itself. Replace any subscription-provided TUN section so we don't
  /// inherit mobile-only settings such as `file-descriptor` or `gvisor`.
  ///
  /// Also forces fake-ip DNS mode — TUN requires fake-ip to work reliably.
  /// Without it, DNS resolution for proxied domains fails because TUN
  /// intercepts raw IP packets, not domain-based connections. This matches
  /// Clash Verge Rev's `use_tun()` which forces fake-ip when TUN is enabled.
  static String _ensureDesktopTun(
    String config,
    String stack, {
    List<String> bypassAddresses = const [],
    List<String> bypassProcesses = const [],
  }) {
    final normalizedStack = switch (stack) {
      'system' => 'system',
      'gvisor' => 'gvisor',
      _ => 'mixed',
    };

    if (_hasKey(config, 'tun')) {
      config = _removeSection(config, 'tun');
    }

    if (_hasKey(config, 'find-process-mode')) {
      config = _replaceScalar(config, 'find-process-mode', 'always');
    } else {
      config += '\nfind-process-mode: always\n';
    }

    // Force fake-ip DNS mode for TUN (CVR does the same in use_tun())
    config = _ensureFakeIpForTun(config);

    // mtu: 1500 — matches the physical Ethernet/Wi-Fi MTU. Previous 9000
    // was mihomo's jumbo-frame default, designed for point-to-point
    // virtual links. On a real desktop the TUN packets traverse the
    // kernel socket layer which is 1500-bound, so the extra 7500 bytes
    // per packet either get re-fragmented (TCP) or silently dropped
    // (UDP without PMTUD), costing 15-30% throughput. mihomo-party
    // explicitly sets 1500; CVR/FlClash rely on mihomo's default which
    // we now override to match reality. Android/iOS in _injectTunFd
    // also use 1500 now for the same reason.
    final buf = StringBuffer()
      ..write('$config\ntun:\n')
      ..write('  enable: true\n')
      ..write('  stack: $normalizedStack\n')
      ..write('  auto-route: true\n')
      ..write('  auto-detect-interface: true\n')
      ..write('  dns-hijack:\n')
      ..write('    - any:53\n')
      ..write('  mtu: 1500\n');

    // TUN bypass: exclude addresses from TUN routing
    if (bypassAddresses.isNotEmpty) {
      buf.write('  route-exclude-address:\n');
      for (final addr in bypassAddresses) {
        buf.write('    - $addr\n');
      }
    }

    // TUN bypass: exclude processes from TUN
    if (bypassProcesses.isNotEmpty) {
      buf.write('  exclude-package:\n');
      for (final proc in bypassProcesses) {
        buf.write('    - $proc\n');
      }
    }

    return buf.toString();
  }

  /// Force fake-ip DNS mode within the existing dns section.
  ///
  /// TUN mode requires fake-ip to function correctly. If the subscription
  /// config uses redir-host or has no enhanced-mode, override it.
  /// Only touches enhanced-mode and fake-ip-range — leaves nameservers,
  /// fallback, and other DNS settings from the subscription intact.
  static String _ensureFakeIpForTun(String config) {
    if (!_hasKey(config, 'dns')) {
      // No dns section — _ensureDns() already injected one with fake-ip
      return config;
    }

    final dnsMatch = _reDnsKey.firstMatch(config);
    if (dnsMatch == null) return config;

    final afterDnsLine = config.indexOf('\n', dnsMatch.start);
    final afterDns = afterDnsLine >= 0 ? afterDnsLine + 1 : config.length;
    final nextTopLevel = _reTopLevel.firstMatch(config.substring(afterDns));
    final dnsEnd =
        nextTopLevel != null ? afterDns + nextTopLevel.start : config.length;

    var dnsSection = config.substring(dnsMatch.start, dnsEnd);

    // Force enhanced-mode: fake-ip
    final enhancedRe = RegExp(r'enhanced-mode:\s*\S+');
    if (enhancedRe.hasMatch(dnsSection)) {
      dnsSection =
          dnsSection.replaceFirst(enhancedRe, 'enhanced-mode: fake-ip');
    } else {
      // Inject after dns: line
      final indentMatch = RegExp(r'\n( +)\S').firstMatch(dnsSection);
      final indent = indentMatch?.group(1) ?? '  ';
      dnsSection = dnsSection.replaceFirst(
        'dns:\n',
        'dns:\n${indent}enhanced-mode: fake-ip\n',
      );
    }

    // Ensure fake-ip-range exists
    if (!dnsSection.contains('fake-ip-range')) {
      final indentMatch = RegExp(r'\n( +)\S').firstMatch(dnsSection);
      final indent = indentMatch?.group(1) ?? '  ';
      dnsSection = dnsSection.replaceFirst(
        'enhanced-mode: fake-ip\n',
        'enhanced-mode: fake-ip\n${indent}fake-ip-range: 198.18.0.1/16\n',
      );
    }

    return config.substring(0, dnsMatch.start) +
        dnsSection +
        config.substring(dnsEnd);
  }

  /// Inject Android-safe TUN configuration with the VpnService file descriptor.
  ///
  /// On Android, VpnService owns the TUN device and handles routing.
  /// mihomo must use the provided fd without trying to create routes itself.
  ///
  /// Critical settings:
  /// - `file-descriptor: <fd>` — use VpnService's TUN device
  /// - `inet4-address: [172.19.0.1/30]` — **required** by sing-tun stack init,
  ///   must match VpnService builder's `addAddress("172.19.0.1", 30)`
  /// - `stack: gvisor` — pure userspace TCP/IP stack; `mixed`/`system` stacks
  ///   use kernel TCP which can fail with VPN-provided fds on Android
  /// - `auto-route: false` — VpnService handles routing (netlink banned on Android 14+)
  /// - `auto-detect-interface: false` — avoid NetworkUpdateMonitor (netlink)
  /// - `dns-hijack: [any:53]` — intercept DNS for fake-ip/redir
  /// - `mtu: 1500` — match VpnService builder's `setMtu(1500)` and the
  ///   physical cellular/Wi-Fi MTU. Larger values don't help on Android
  ///   (see YueLinkVpnService.kt comment).
  static String _injectTunFd(String config, int fd) {
    // Remove existing tun section entirely and replace with Android-safe config.
    // This avoids partial merges where subscription settings (auto-route: true)
    // conflict with Android VpnService requirements.
    if (_hasKey(config, 'tun')) {
      config = _removeSection(config, 'tun');
    }

    // Override find-process-mode for mobile (Android has no permission)
    if (_hasKey(config, 'find-process-mode')) {
      config = _replaceScalar(config, 'find-process-mode', 'off');
    }

    // Append clean Android TUN section
    // - gvisor stack: pure userspace TCP/IP — doesn't depend on kernel features.
    //   mixed/system stacks use kernel TCP which fails with VPN-provided fds.
    // - inet4-address MUST match VpnService's addAddress("172.19.0.1", 30)
    // - auto-route: false — VpnService handles routing
    // - auto-detect-interface: false — monitor_android.go uses netlink which
    //   is banned on Android 14+ (API 34). Not needed anyway because
    //   addDisallowedApplication(packageName) excludes our UID from VPN,
    //   so mihomo's outbound connections use the physical interface directly.
    return '$config\ntun:\n'
        '  enable: true\n'
        '  stack: gvisor\n'
        '  file-descriptor: $fd\n'
        '  inet4-address:\n'
        '    - 172.19.0.1/30\n'
        '  mtu: 1500\n'
        '  auto-route: false\n'
        '  auto-detect-interface: false\n'
        '  dns-hijack:\n'
        '    - any:53\n';
  }

  /// Ensure DNS is enabled with comprehensive fake-ip + fallback config.
  /// If the subscription config already has a dns section, ensure enable: true
  /// and inject nameserver-policy for Apple/iCloud so DIRECT-routed Apple
  /// system services (mesu.apple.com, etc.) resolve via domestic DoH instead
  /// of UDP DNS that may return 0.0.0.0 on some networks.
  static String _ensureDns(String config) {
    if (!_hasKey(config, 'dns')) {
      return '$config\ndns:\n'
          '  enable: true\n'
          '  prefer-h3: true\n'
          // respect-rules: DNS lookups honour the routing table, so a
          // Chinese domain that should be DIRECT doesn't get its DNS
          // query tunneled through a proxy (which would add 200+ ms of
          // cross-border RTT to every page load). Mihomo 0.9+ / Clash
          // Verge Rev default this to true.
          '  respect-rules: true\n'
          '  enhanced-mode: fake-ip\n'
          '  fake-ip-range: 198.18.0.1/16\n'
          '  fake-ip-filter:\n'
          '    - "+.lan"\n'
          '    - "+.local"\n'
          '    - "+.direct"\n'
          '    - "+.msftconnecttest.com"\n'
          '    - "+.msftncsi.com"\n'
          '    - "localhost.ptlogin2.qq.com"\n'
          '    - "+.srv.nintendo.net"\n'
          '    - "+.stun.playstation.net"\n'
          '    - "+.xboxlive.com"\n'
          '    - "+.ntp.org"\n'
          '    - "+.pool.ntp.org"\n'
          '    - "+.time.edu.cn"\n'
          '    - "+.apple.com"\n'
          '    - "+.icloud.com"\n'
          '    - "+.cdn-apple.com"\n'
          '    - "+.mzstatic.com"\n'
          '    - "+.push.apple.com"\n'
          // Connectivity check domains — must resolve to real IPs to avoid
          // "no internet" / WiFi exclamation mark on all platforms.
          // Google / Android
          '    - "connectivitycheck.gstatic.com"\n'
          '    - "www.gstatic.com"\n'
          '    - "+.connectivitycheck.android.com"\n'
          '    - "clients1.google.com"\n'
          '    - "clients3.google.com"\n'
          '    - "play.googleapis.com"\n'
          // Apple captive portal
          '    - "captive.apple.com"\n'
          '    - "gsp-ssl.ls.apple.com"\n'
          '    - "gsp-ssl.ls-apple.com.akadns.net"\n'
          // Huawei
          '    - "connectivitycheck.platform.hicloud.com"\n'
          '    - "+.wifi.huawei.com"\n'
          // Samsung
          '    - "connectivitycheck.samsung.com"\n'
          // Xiaomi
          '    - "connect.rom.miui.com"\n'
          '    - "connectivitycheck.platform.xiaomi.com"\n'
          // OPPO / Realme / ColorOS
          '    - "conn1.coloros.com"\n'
          '    - "conn2.coloros.com"\n'
          // Honor
          '    - "connectivitycheck.platform.hihonorcloud.com"\n'
          // Meizu
          '    - "connectivitycheck.meizu.com"\n'
          // Vivo / other
          '    - "wifi.vivo.com.cn"\n'
          '    - "noisyfox.cn"\n'
          '  default-nameserver:\n'
          '    - 223.5.5.5\n'
          '    - 119.29.29.29\n'
          '    - 8.8.8.8\n'
          '  nameserver:\n'
          '    - https://doh.pub/dns-query\n'
          '    - https://dns.alidns.com/dns-query\n'
          '  direct-nameserver:\n'
          '    - https://doh.pub/dns-query\n'
          '    - https://dns.alidns.com/dns-query\n'
          '  proxy-server-nameserver:\n'
          '    - 223.5.5.5\n'
          '    - 119.29.29.29\n'
          '    - 8.8.8.8\n'
          '    - https://doh.pub/dns-query\n'
          '    - https://dns.alidns.com/dns-query\n'
          '  nameserver-policy:\n'
          '    "+.apple.com": ["https://doh.pub/dns-query", "https://dns.alidns.com/dns-query"]\n'
          '    "+.icloud.com": ["https://doh.pub/dns-query", "https://dns.alidns.com/dns-query"]\n'
          '  fallback:\n'
          '    - "tls://8.8.4.4:853"\n'
          '    - "tls://1.0.0.1:853"\n'
          '    - "https://1.0.0.1/dns-query"\n'
          '    - "https://8.8.4.4/dns-query"\n'
          '  fallback-filter:\n'
          '    geoip: true\n'
          '    geoip-code: CN\n'
          '    geosite:\n'
          '      - gfw\n'
          '    domain:\n'
          '      - "+.google.com"\n'
          '      - "+.facebook.com"\n'
          '      - "+.youtube.com"\n'
          '      - "+.github.com"\n'
          '      - "+.googleapis.com"\n';
    }

    // Subscription has DNS section — use string operations to patch it
    // without fully re-parsing the YAML (avoids catastrophic backtracking
    // on large configs with anchors).
    final dnsMatch = _reDnsKey.firstMatch(config);
    if (dnsMatch == null) return config;

    // Find where the dns section ends (next top-level key or EOF)
    final afterDnsLine = config.indexOf('\n', dnsMatch.start);
    var afterDns = afterDnsLine >= 0 ? afterDnsLine + 1 : config.length;
    final nextTopLevel = _reTopLevel.firstMatch(config.substring(afterDns));
    var dnsEnd =
        nextTopLevel != null ? afterDns + nextTopLevel.start : config.length;

    var dnsSection = config.substring(dnsMatch.start, dnsEnd);

    // Fix 1: ensure enable: true
    if (_reEnableFalse.hasMatch(dnsSection)) {
      final newSection =
          dnsSection.replaceFirst(_reEnableFalse, 'enable: true');
      config = config.substring(0, dnsMatch.start) +
          newSection +
          config.substring(dnsEnd);
      // Adjust dnsEnd to account for length change
      dnsEnd += newSection.length - dnsSection.length;
      dnsSection = newSection;
    } else if (!_reEnableTrue.hasMatch(dnsSection)) {
      // DNS section exists but has no 'enable' key — inject after dns: line
      const injection = '  enable: true\n';
      config = config.substring(0, afterDns) +
          injection +
          config.substring(afterDns);
      dnsEnd += injection.length;
      afterDns += injection.length;
      dnsSection = config.substring(dnsMatch.start, dnsEnd);
    }

    // Fix 2: inject nameserver-policy + direct-nameserver for Apple/iCloud.
    //
    // Problem: subscription routes Apple domains DIRECT. mihomo resolves them
    // using direct-nameserver (or nameserver if not set). On some Chinese
    // networks, plain UDP DNS (223.5.5.5) returns 0.0.0.0 for Apple update
    // domains (mesu.apple.com, swscan.apple.com), causing
    // "dial tcp 0.0.0.0:443: connection refused".
    //
    // Fix: inject DoH-based nameserver-policy + direct-nameserver so that:
    // - nameserver-policy covers Apple/iCloud (if main resolver is used)
    // - direct-nameserver uses DoH (if direct resolver is used)
    //
    // Indent detection: subscription configs use varied indentation (2/4 space).
    // Detect the actual indent from existing keys to avoid YAML parse errors.
    final indentMatch = RegExp(r'\n( +)\S').firstMatch(dnsSection);
    if (indentMatch != null) {
      final indent = indentMatch.group(1)!; // e.g. "  " or "    "
      // Sub-entries need more indentation than the key itself.
      // Detect from existing list items, or use indent + 2 spaces.
      final listMatch = RegExp(r'\n( +)- ').firstMatch(dnsSection);
      final entryIndent = listMatch?.group(1) ?? '$indent  ';

      // Fix 1b: inject prefer-h3 for DNS-over-HTTPS/3 (QUIC).
      // Benefits: faster DNS resolution over QUIC (matches hy2 transport),
      // avoids TCP DNS blocking on some networks.
      if (!dnsSection.contains('prefer-h3')) {
        final injection = '${indent}prefer-h3: true\n';
        config = config.substring(0, afterDns) +
            injection +
            config.substring(afterDns);
        dnsEnd += injection.length;
        afterDns += injection.length;
        dnsSection = config.substring(dnsMatch.start, dnsEnd);
      }

      // Fix 1c: inject respect-rules so DNS queries honour the routing
      // table. Without this, a Chinese domain that's supposed to resolve
      // via direct-nameserver may still go out through the proxy path if
      // the DNS server is a proxy-routed resolver, adding cross-border
      // RTT to every first page load. Ensure-only — subscription that
      // explicitly sets it stays untouched.
      if (!dnsSection.contains('respect-rules')) {
        final injection = '${indent}respect-rules: true\n';
        config = config.substring(0, afterDns) +
            injection +
            config.substring(afterDns);
        dnsEnd += injection.length;
        afterDns += injection.length;
        dnsSection = config.substring(dnsMatch.start, dnsEnd);
      }

      if (!dnsSection.contains('nameserver-policy:')) {
        final policy = '$indent'
            'nameserver-policy:\n'
            '$entryIndent'
            '"+.apple.com": ["https://doh.pub/dns-query", "https://dns.alidns.com/dns-query"]\n'
            '$entryIndent'
            '"+.icloud.com": ["https://doh.pub/dns-query", "https://dns.alidns.com/dns-query"]\n';
        config =
            config.substring(0, dnsEnd) + policy + config.substring(dnsEnd);
        dnsEnd += policy.length;
      }

      if (!dnsSection.contains('direct-nameserver:')) {
        final directNs = '$indent'
            'direct-nameserver:\n'
            '$entryIndent'
            '- https://doh.pub/dns-query\n'
            '$entryIndent'
            '- https://dns.alidns.com/dns-query\n';
        config =
            config.substring(0, dnsEnd) + directNs + config.substring(dnsEnd);
        dnsEnd += directNs.length;
        dnsSection = config.substring(dnsMatch.start, dnsEnd);
      }

      // Fix 4: ensure proxy-server-nameserver has plain UDP DNS fallbacks.
      // Problem: if proxy-server-nameserver only has DoH (HTTPS) servers,
      // mihomo can't resolve proxy server hostnames before connecting — the
      // DoH query itself requires the proxy to be up (chicken-and-egg).
      // Plain UDP DNS (223.5.5.5 / 8.8.8.8) bypass the proxy and bootstrap
      // resolution so the proxy can start in the first place.
      if (!dnsSection.contains('proxy-server-nameserver:')) {
        final proxyNs = '${indent}proxy-server-nameserver:\n'
            '$entryIndent- 223.5.5.5\n'
            '$entryIndent- 119.29.29.29\n'
            '$entryIndent- 8.8.8.8\n'
            '$entryIndent- https://doh.pub/dns-query\n'
            '$entryIndent- https://dns.alidns.com/dns-query\n';
        config =
            config.substring(0, dnsEnd) + proxyNs + config.substring(dnsEnd);
        dnsEnd += proxyNs.length;
        dnsSection = config.substring(dnsMatch.start, dnsEnd);
      }

      // Fix 5: ensure connectivity-check domains are in fake-ip-filter.
      // Without these, connectivity checks resolve to fake IPs, causing
      // "no internet" / WiFi exclamation mark on Android, iOS, Windows, etc.
      dnsSection = config.substring(dnsMatch.start, dnsEnd);
      const connectivityDomains = [
        // Google / Android
        'connectivitycheck.gstatic.com',
        'www.gstatic.com',
        '+.connectivitycheck.android.com',
        'clients1.google.com',
        'clients3.google.com',
        'play.googleapis.com',
        // Apple captive portal
        'captive.apple.com',
        'gsp-ssl.ls.apple.com',
        'gsp-ssl.ls-apple.com.akadns.net',
        // Microsoft
        'www.msftconnecttest.com',
        'www.msftncsi.com',
        'dns.msftncsi.com',
        // Huawei
        'connectivitycheck.platform.hicloud.com',
        '+.wifi.huawei.com',
        // Samsung
        'connectivitycheck.samsung.com',
        // Xiaomi
        'connect.rom.miui.com',
        'connectivitycheck.platform.xiaomi.com',
        // OPPO / Realme / ColorOS
        'conn1.coloros.com',
        'conn2.coloros.com',
        // Honor
        'connectivitycheck.platform.hihonorcloud.com',
        // Meizu
        'connectivitycheck.meizu.com',
        // Vivo / other
        'wifi.vivo.com.cn',
        'noisyfox.cn',
      ];
      if (dnsSection.contains('fake-ip-filter:')) {
        // Append missing domains to existing fake-ip-filter
        final filterMatch =
            RegExp(r'fake-ip-filter:\s*\n').firstMatch(dnsSection);
        if (filterMatch != null) {
          var insertOffset = dnsMatch.start + filterMatch.end;
          // Find end of list items (lines starting with entryIndent + "- ")
          final afterFilter = config.substring(insertOffset);
          final listEnd =
              RegExp(r'^(?![ \t]+- )', multiLine: true).firstMatch(afterFilter);
          if (listEnd != null) insertOffset += listEnd.start;
          final existingFilter = dnsSection;
          var injection = '';
          for (final domain in connectivityDomains) {
            if (!existingFilter.contains(domain)) {
              injection += '$entryIndent- "$domain"\n';
            }
          }
          if (injection.isNotEmpty) {
            config = config.substring(0, insertOffset) +
                injection +
                config.substring(insertOffset);
            dnsEnd += injection.length;
          }
        }
      } else {
        // No fake-ip-filter at all — inject one with connectivity domains
        final filterBlock = '${indent}fake-ip-filter:\n'
            '${connectivityDomains.map((d) => '$entryIndent- "$d"').join('\n')}\n';
        config = config.substring(0, dnsEnd) +
            filterBlock +
            config.substring(dnsEnd);
      }
    }

    return config;
  }

  /// Force sniffer with override-destination: true for TLS/HTTP/QUIC.
  /// Always overwrite — subscription templates may have override-destination: false
  /// which breaks server-side audit rules (server only sees IP, not domain).
  static String _ensureSniffer(String config) {
    // Remove existing sniffer block to force our correct config
    config = _removeSection(config, 'sniffer');
    return '$config\nsniffer:\n'
        '  enable: true\n'
        '  force-dns-mapping: true\n'
        '  parse-pure-ip: true\n'
        '  override-destination: true\n'
        '  sniff:\n'
        '    HTTP:\n'
        '      ports: [80, 8080-8880]\n'
        '      override-destination: true\n'
        '    TLS:\n'
        '      ports: [443, 8443]\n'
        '      override-destination: true\n'
        '    QUIC:\n'
        '      ports: [443, 8443]\n'
        '      override-destination: true\n'
        '  force-domain:\n'
        '    - "+.v2ex.com"\n'
        '  skip-domain:\n'
        '    - "Mijia Cloud"\n'
        '    - "+.push.apple.com"\n';
  }

  /// Ensure geodata settings so GEOIP/GEOSITE rules resolve correctly.
  static String _ensureGeodata(String config) {
    if (!_hasKey(config, 'geodata-mode')) {
      config += '\ngeodata-mode: true\n';
    }
    if (!_hasKey(config, 'geodata-loader')) {
      // memconservative: lazy-loads GeoIP entries on first hit instead
      // of slurping the whole .dat at startup. ~60% lower peak RSS,
      // particularly important on iOS PacketTunnel (15 MB cap) and on
      // low-RAM Android devices. Matches mihomo 1.19+ recommendation.
      config += 'geodata-loader: memconservative\n';
    }
    if (!_hasKey(config, 'geo-auto-update')) {
      config += 'geo-auto-update: true\n';
    }
    if (!_hasKey(config, 'geo-update-interval')) {
      config += 'geo-update-interval: 24\n';
    }
    if (!_hasKey(config, 'geox-url')) {
      config += 'geox-url:\n'
          '  geoip: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"\n'
          '  geosite: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"\n'
          '  mmdb: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"\n';
    }
    return config;
  }

  /// Ensure profile persistence settings.
  static String _ensureProfile(String config) {
    if (_hasKey(config, 'profile')) return config;
    return '$config\nprofile:\n'
        '  store-selected: true\n'
        '  store-fake-ip: true\n';
  }

  /// Ensure performance tuning defaults.
  static String _ensurePerformance(String config) {
    if (!_hasKey(config, 'tcp-concurrent')) {
      config += '\ntcp-concurrent: true\n';
    }
    if (!_hasKey(config, 'unified-delay')) {
      config += 'unified-delay: true\n';
    }
    if (!_hasKey(config, 'global-client-fingerprint')) {
      config += 'global-client-fingerprint: chrome\n';
    }
    // Keep-alive interval: mihomo upstream default is 30s — matches the
    // mobile carrier NAT floor (~30s) while halving CPU wake-ups / battery
    // drain vs the previous 15s. Clash Verge Rev and mihomo-party both
    // use 30s.
    if (!_hasKey(config, 'keep-alive-interval')) {
      config += 'keep-alive-interval: 30\n';
    }
    return config;
  }

  /// Ensure allow-lan for mixed-port to listen on all interfaces.
  static String _ensureAllowLan(String config) {
    if (!_hasKey(config, 'allow-lan')) {
      config += '\nallow-lan: true\n';
    }
    if (!_hasKey(config, 'bind-address')) {
      config += 'bind-address: "*"\n';
    }
    return config;
  }

  /// Ensure find-process-mode based on platform.
  /// Desktop (macOS/Windows/Linux): always — enables process-based routing.
  /// Mobile (Android/iOS): off — no permission, avoids useless overhead.
  static String _ensureFindProcessMode(String config) {
    if (_hasKey(config, 'find-process-mode')) {
      // On mobile, force off regardless of subscription setting
      if (Platform.isAndroid || Platform.isIOS) {
        config = _replaceScalar(config, 'find-process-mode', 'off');
      }
      return config;
    }
    final mode = (Platform.isAndroid || Platform.isIOS) ? 'off' : 'always';
    return '$config\nfind-process-mode: $mode\n';
  }

  /// Remove a top-level YAML section (key + all indented content below it).
  /// Works whether the section ends with a newline, EOF, or next top-level key.
  static String _removeSection(String config, String key) {
    final keyPattern = RegExp('^$key:', multiLine: true);
    final match = keyPattern.firstMatch(config);
    if (match == null) return config;

    final afterKeyLine = config.indexOf('\n', match.start);
    if (afterKeyLine < 0) {
      // Section is the last line with no newline — remove to EOF
      return config.substring(0, match.start);
    }
    final afterKey = afterKeyLine + 1;
    final nextTopLevel = _reTopLevel.firstMatch(config.substring(afterKey));
    final sectionEnd =
        nextTopLevel != null ? afterKey + nextTopLevel.start : config.length;
    return config.substring(0, match.start) + config.substring(sectionEnd);
  }

  /// Replace the value of a top-level scalar key.
  static String _replaceScalar(String config, String key, String value) {
    return config.replaceAll(
      RegExp('^$key:.*\$', multiLine: true),
      '$key: $value',
    );
  }

  /// Ensure the config has mixed-port set.
  ///
  /// mihomo silently skips creating the HTTP+SOCKS proxy listener when
  /// mixed-port is 0 (not set). Without it, system proxy on macOS/Windows
  /// points to a port where nobody is listening, and all proxy traffic fails.
  static String _ensureMixedPort(String config, int port) {
    if (_hasKey(config, 'mixed-port')) return config;
    return '$config\nmixed-port: $port\n';
  }

  /// Force-set mixed-port, replacing an existing value if present.
  /// Used by CoreManager to remap the port when it is already in use.
  static String setMixedPort(String config, int port) {
    if (_hasKey(config, 'mixed-port')) {
      return config.replaceAllMapped(_reMixedPort, (_) => 'mixed-port: $port');
    }
    return '$config\nmixed-port: $port\n';
  }

  /// Ensure the config has external-controller set.
  static String _ensureExternalController(
      String config, int port, String? secret) {
    // Check if already has external-controller
    if (_hasKey(config, 'external-controller')) {
      // Replace the existing value to ensure our port
      config = config.replaceAllMapped(
        _reExtController,
        (m) => '${m.group(1)}127.0.0.1:$port',
      );
    } else {
      // Append at the end (before rules section if possible)
      config += '\nexternal-controller: 127.0.0.1:$port\n';
    }

    // Handle secret
    if (secret != null && !_hasKey(config, 'secret')) {
      config += 'secret: $secret\n';
    }

    return config;
  }

  /// Check if a top-level YAML key exists.
  static bool _hasKey(String config, String key) {
    return RegExp('^$key:', multiLine: true).hasMatch(config);
  }

  /// Extract the mixed-port from config, or return default.
  static int getMixedPort(String config) {
    final match = _reMixedPort.firstMatch(config);
    if (match != null) return int.parse(match.group(1)!);
    return AppConstants.defaultMixedPort;
  }

  /// Extract the external-controller port from config.
  static int getApiPort(String config) {
    final match = _reApiPort.firstMatch(config);
    if (match != null) return int.parse(match.group(1)!);
    return AppConstants.defaultApiPort;
  }

  /// Extract secret from config.
  static String? getSecret(String config) {
    return _reSecret.firstMatch(config)?.group(1);
  }

  /// Memoised fallback template — assets/default_config.yaml is read at
  /// most ONCE per app lifetime. The previous implementation called
  /// `rootBundle.loadString` on every profile add/update, including bulk
  /// imports and the background subscription sync timer, which thrashed
  /// the asset bundle reader for no reason (the file is a baked-in const).
  static Future<String>? _fallbackTemplateFuture;

  /// Load the built-in fallback config.
  ///
  /// This is NOT the default config for normal usage. Subscriptions provide
  /// complete configs. This is only for the rare case where a subscription
  /// returns raw proxy nodes without any proxy-groups or rules.
  static Future<String> loadFallbackTemplate() {
    return _fallbackTemplateFuture ??=
        rootBundle.loadString('assets/default_config.yaml');
  }

  /// Ensure connectivity-check domains are routed DIRECT in rules.
  /// Without this, even with correct fake-ip-filter, the HTTP 204 check
  /// may still go through the proxy and fail (blocked, slow, or wrong response),
  /// causing WiFi exclamation mark on various Android brands.
  static String _ensureConnectivityRules(String config) {
    final rulesMatch =
        RegExp(r'^rules:\s*\n', multiLine: true).firstMatch(config);
    if (rulesMatch == null) return config; // no rules section

    const domains = [
      'connectivitycheck.gstatic.com',
      'connectivitycheck.android.com',
      'clients3.google.com',
      'connectivitycheck.platform.hicloud.com',
      'connectivitycheck.samsung.com',
      'connect.rom.miui.com',
      'connectivitycheck.platform.xiaomi.com',
      'conn1.coloros.com',
      'conn2.coloros.com',
      'connectivitycheck.platform.hihonorcloud.com',
      'connectivitycheck.meizu.com',
      'wifi.vivo.com.cn',
      'captive.apple.com',
      'www.msftconnecttest.com',
    ];

    // Only inject rules not already present.
    // Detect indentation from existing rules (e.g. "  - " or "- ").
    final firstRule = RegExp(r'^([ \t]*)-\s', multiLine: true)
        .firstMatch(config.substring(rulesMatch.end));
    final ruleIndent = firstRule?.group(1) ?? '  ';
    var injection = '';
    for (final d in domains) {
      // Google/gstatic/msft 域名被 GFW 干扰，不注入 DIRECT
      // 让订阅自带的 Google→代理 规则处理
      if (d.contains('google') || d.contains('gstatic') || d.contains('msft'))
        continue;
      if (!config.contains('DOMAIN,$d,')) {
        injection += '$ruleIndent- "DOMAIN,$d,DIRECT"\n';
      }
    }
    if (injection.isEmpty) return config;

    // Insert right after "rules:\n"
    return config.substring(0, rulesMatch.end) +
        injection +
        config.substring(rulesMatch.end);
  }

  /// Determine if a subscription config is complete (has groups + rules).
  ///
  /// Most subscriptions (机场) deliver complete configs. Only use the
  /// fallback template when the subscription provides raw proxies only.
  static bool isCompleteConfig(String config) {
    return _hasKey(config, 'proxy-groups') && _hasKey(config, 'rules');
  }

  /// Merge subscription proxy nodes into the fallback template.
  ///
  /// Only called when the subscription doesn't provide a complete config
  /// (no proxy-groups, no rules). In the normal case where the subscription
  /// delivers everything, this method returns the subscription config as-is.
  static String mergeIfNeeded(String fallbackTemplate, String subConfig) {
    // Subscription has everything — use it directly (the normal case)
    if (isCompleteConfig(subConfig)) {
      return subConfig;
    }

    // Rare case: subscription only has proxies, merge into fallback
    final proxiesBlock = _extractSection(subConfig, 'proxies');
    if (proxiesBlock == null) return subConfig;

    if (_hasKey(fallbackTemplate, 'proxies')) {
      return fallbackTemplate.replaceFirst(
        _reProxiesSection,
        'proxies:\n$proxiesBlock\n',
      );
    }

    return subConfig;
  }

  /// Extract a YAML section's content (everything until the next top-level key).
  static String? _extractSection(String config, String key) {
    final keyPattern = RegExp('^$key:', multiLine: true);
    final match = keyPattern.firstMatch(config);
    if (match == null) return null;

    final start = match.end;
    final nextKeyPattern = RegExp(r'^\S', multiLine: true);
    final nextMatch = nextKeyPattern.firstMatch(config.substring(start));
    final end = nextMatch != null ? start + nextMatch.start : config.length;

    return config.substring(start, end).trimRight();
  }
}
