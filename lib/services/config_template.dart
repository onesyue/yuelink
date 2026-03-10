import 'package:flutter/services.dart';

import '../constants.dart';

/// Processes mihomo config templates from subscription providers.
///
/// Subscription configs typically use template variables like `$app_name`
/// which need to be replaced with the actual app name. The `proxies:` section
/// is usually empty and gets filled by the subscription's proxy list.
///
/// This class also handles merging external-controller settings so the
/// REST API is always accessible.
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
  static String process(
    String rawConfig, {
    int apiPort = AppConstants.defaultApiPort,
    String? secret,
  }) {
    var config = rawConfig;

    // Replace template variables
    for (final entry in _variables.entries) {
      config = config.replaceAll(entry.key, entry.value);
    }

    // Ensure external-controller is present
    config = _ensureExternalController(config, apiPort, secret);

    return config;
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

  /// Load the built-in default config template.
  static Future<String> loadDefaultTemplate() async {
    return rootBundle.loadString('assets/default_config.yaml');
  }

  /// Merge subscription proxies into a config template.
  ///
  /// The subscription typically provides just `proxies:` with node data.
  /// This method extracts those proxies and injects them into the default
  /// template which has the full proxy-groups, rules, DNS config, etc.
  ///
  /// If the subscription config already has proxy-groups and rules,
  /// it's used as-is (it's a complete config, not just proxies).
  static String mergeWithTemplate(String template, String subscriptionConfig) {
    // If subscription has its own proxy-groups and rules, use it directly
    if (_hasKey(subscriptionConfig, 'proxy-groups') &&
        _hasKey(subscriptionConfig, 'rules')) {
      return subscriptionConfig;
    }

    // Extract proxies section from subscription
    final proxiesBlock = _extractSection(subscriptionConfig, 'proxies');
    if (proxiesBlock == null) return subscriptionConfig;

    // Replace the empty proxies section in the template
    if (_hasKey(template, 'proxies')) {
      final result = template.replaceFirst(
        RegExp(r'^proxies:\s*\n', multiLine: true),
        'proxies:\n$proxiesBlock\n',
      );
      return result;
    }

    return subscriptionConfig;
  }

  /// Extract a YAML section's content (everything until the next top-level key).
  static String? _extractSection(String config, String key) {
    final keyPattern = RegExp('^$key:', multiLine: true);
    final match = keyPattern.firstMatch(config);
    if (match == null) return null;

    final start = match.end;
    // Find the next top-level key (line starting with non-space, non-#)
    final nextKeyPattern =
        RegExp(r'^\S', multiLine: true);
    final nextMatch = nextKeyPattern.firstMatch(config.substring(start));
    final end = nextMatch != null ? start + nextMatch.start : config.length;

    return config.substring(start, end).trimRight();
  }
}
