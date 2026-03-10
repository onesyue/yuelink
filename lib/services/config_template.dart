import 'package:flutter/services.dart';

import '../constants.dart';

/// Processes mihomo configs from subscription providers.
///
/// Subscriptions (机场) typically deliver a **complete** config with
/// proxies, proxy-groups, rules, rule-providers, DNS, etc.
/// The app only needs to:
/// 1. Replace template variables (`$app_name` -> `YueLink`)
/// 2. Ensure `external-controller` is set for REST API access
///
/// The bundled `default_config.yaml` is a **minimal fallback** only used
/// when a subscription provides raw proxy nodes without groups/rules.
class ConfigTemplate {
  ConfigTemplate._();

  /// Template variables and their replacement values.
  static const _variables = {
    r'$app_name': AppConstants.appName,
  };

  /// Process a raw config from a subscription.
  ///
  /// 1. Replaces template variables (`$app_name` -> `YueLink`)
  /// 2. Ensures `external-controller` is set for REST API access
  /// 3. Ensures `external-controller` secret if configured
  /// 4. On Android: injects `tun.file-descriptor` so mihomo uses the
  ///    pre-created TUN fd from VpnService instead of creating its own
  static String process(
    String rawConfig, {
    int apiPort = AppConstants.defaultApiPort,
    String? secret,
    int? tunFd,
  }) {
    var config = rawConfig;

    // Replace template variables
    for (final entry in _variables.entries) {
      config = config.replaceAll(entry.key, entry.value);
    }

    // Ensure external-controller is present
    config = _ensureExternalController(config, apiPort, secret);

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
  /// Key settings:
  /// - `file-descriptor: <fd>` — use VpnService's TUN device
  /// - `auto-route: false` — VpnService handles routing (netlink banned on Android 14+)
  /// - `auto-detect-interface: false` — avoid NetworkUpdateMonitor (netlink)
  /// - `enable: true` + `stack: system` — enable TUN with system stack
  /// - `dns-hijack: [any:53]` — intercept DNS for fake-ip/redir
  static String _injectTunFd(String config, int fd) {
    // Remove existing tun section entirely and replace with Android-safe config.
    // This avoids partial merges where subscription settings (auto-route: true)
    // conflict with Android VpnService requirements.
    if (_hasKey(config, 'tun')) {
      config = _removeSection(config, 'tun');
    }

    // Append clean Android TUN section
    return '$config\ntun:\n'
        '  enable: true\n'
        '  stack: system\n'
        '  file-descriptor: $fd\n'
        '  auto-route: false\n'
        '  auto-detect-interface: false\n'
        '  dns-hijack:\n'
        '    - any:53\n';
  }

  /// Remove a top-level YAML section (key + all indented content below it).
  static String _removeSection(String config, String key) {
    final pattern = RegExp(
      '^$key:.*\n(?:[ \t]+.*\n)*',
      multiLine: true,
    );
    return config.replaceFirst(pattern, '');
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

  /// Load the built-in minimal fallback config.
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
