import 'dart:io';

import 'package:flutter/services.dart';

import '../constants.dart';

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
  ConfigTemplate._();

  /// Template variables and their replacement values.
  static const _variables = {
    r'$app_name': AppConstants.appName,
  };

  /// Process a raw config from a subscription.
  ///
  /// Ensures all critical config keys are present for reliable operation
  /// across all platforms. Uses "ensure" pattern: only injects when missing,
  /// never overwrites subscription-provided settings.
  static String process(
    String rawConfig, {
    int apiPort = AppConstants.defaultApiPort,
    int mixedPort = AppConstants.defaultMixedPort,
    String? secret,
    int? tunFd,
  }) {
    var config = rawConfig;

    // Replace template variables
    for (final entry in _variables.entries) {
      config = config.replaceAll(entry.key, entry.value);
    }

    // Ensure mixed-port is present — without it mihomo silently skips
    // creating the HTTP+SOCKS listener, so system proxy (macOS/Windows)
    // and direct proxy connections all fail.
    config = _ensureMixedPort(config, mixedPort);

    // Ensure external-controller is present
    config = _ensureExternalController(config, apiPort, secret);

    // Ensure DNS is always present — not just for TUN mode.
    // Without DNS config, subscriptions relying on fake-ip or domain
    // resolution fail silently even in system proxy mode.
    config = _ensureDns(config);

    // Ensure sniffer for TLS/HTTP domain detection — critical for
    // DOMAIN-type rules to work correctly with encrypted connections.
    config = _ensureSniffer(config);

    // Ensure geodata settings so GEOIP/GEOSITE rules work
    config = _ensureGeodata(config);

    // Ensure profile persistence (store selected node, fake-ip cache)
    config = _ensureProfile(config);

    // Ensure performance tuning defaults
    config = _ensurePerformance(config);

    // Ensure allow-lan for mixed-port to listen on all interfaces
    config = _ensureAllowLan(config);

    // Platform-specific: find-process-mode
    config = _ensureFindProcessMode(config);

    // Ensure routing mode defaults to 'rule' if not specified.
    // Without this, mihomo defaults to 'rule' but being explicit prevents
    // ambiguity and ensures rules-based routing is active.
    if (!_hasKey(config, 'mode')) {
      config += '\nmode: rule\n';
    }

    // Inject TUN fd (Android VpnService mode)
    if (tunFd != null && tunFd > 0) {
      config = _injectTunFd(config, tunFd);
    }

    return config;
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
  /// - `stack: mixed` — gvisor for UDP + system for TCP; `system` alone fails
  ///   with "missing interface address" if inet4-address parsing has issues
  /// - `auto-route: false` — VpnService handles routing (netlink banned on Android 14+)
  /// - `auto-detect-interface: false` — avoid NetworkUpdateMonitor (netlink)
  /// - `dns-hijack: [any:53]` — intercept DNS for fake-ip/redir
  /// - `mtu: 9000` — match VpnService builder's `setMtu(9000)`
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
    // inet4-address MUST match VpnService's addAddress() — without it,
    // sing-tun's system/mixed stack fails with "missing interface address"
    // and mihomo silently skips TUN (only logs the error, doesn't fail startup).
    return '$config\ntun:\n'
        '  enable: true\n'
        '  stack: mixed\n'
        '  file-descriptor: $fd\n'
        '  inet4-address:\n'
        '    - 172.19.0.1/30\n'
        '  mtu: 9000\n'
        '  auto-route: false\n'
        '  auto-detect-interface: false\n'
        '  dns-hijack:\n'
        '    - any:53\n';
  }

  /// Ensure DNS is enabled with comprehensive fake-ip + fallback config.
  /// If the subscription config already has a dns section, leave it alone.
  static String _ensureDns(String config) {
    if (_hasKey(config, 'dns')) return config;
    return '$config\ndns:\n'
        '  enable: true\n'
        '  prefer-h3: true\n'
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
        '    - "+.push.apple.com"\n'
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
        '    - https://doh.pub/dns-query\n'
        '    - https://dns.alidns.com/dns-query\n'
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

  /// Ensure sniffer is configured for TLS/HTTP/QUIC domain detection.
  /// Without sniffer, DOMAIN-type rules can't match encrypted connections.
  static String _ensureSniffer(String config) {
    if (_hasKey(config, 'sniffer')) return config;
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
        '    QUIC:\n'
        '      ports: [443, 8443]\n'
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
      config += 'geodata-loader: standard\n';
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
  static String _removeSection(String config, String key) {
    final pattern = RegExp(
      '^$key:.*\n(?:[ \t]+.*\n)*',
      multiLine: true,
    );
    return config.replaceFirst(pattern, '');
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

  /// Ensure the config has external-controller set.
  static String _ensureExternalController(
      String config, int port, String? secret) {
    // Check if already has external-controller
    if (_hasKey(config, 'external-controller')) {
      // Replace the existing value to ensure our port
      config = config.replaceAllMapped(
        RegExp(r'^(external-controller:\s*).*$', multiLine: true),
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
    final match =
        RegExp(r'^mixed-port:\s*(\d+)', multiLine: true).firstMatch(config);
    if (match != null) return int.parse(match.group(1)!);
    return AppConstants.defaultMixedPort;
  }

  /// Extract the external-controller port from config.
  static int getApiPort(String config) {
    final match = RegExp(r'^external-controller:\s*[\w.]*:(\d+)',
            multiLine: true)
        .firstMatch(config);
    if (match != null) return int.parse(match.group(1)!);
    return AppConstants.defaultApiPort;
  }

  /// Extract secret from config.
  static String? getSecret(String config) {
    final match =
        RegExp(r'^secret:\s*["\x27]?(.+?)["\x27]?\s*$', multiLine: true)
            .firstMatch(config);
    return match?.group(1);
  }

  /// Load the built-in fallback config.
  ///
  /// This is NOT the default config for normal usage. Subscriptions provide
  /// complete configs. This is only for the rare case where a subscription
  /// returns raw proxy nodes without any proxy-groups or rules.
  static Future<String> loadFallbackTemplate() async {
    return rootBundle.loadString('assets/default_config.yaml');
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
        RegExp(r'^proxies:\s*\n', multiLine: true),
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
