import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

import '../../constants.dart';
import 'config/dns_transformer.dart';
import 'config/performance_transformer.dart';
import 'config/provider_proxy_transformer.dart';
import 'config/rules_transformer.dart';
import 'config/scalar_transformers.dart';
import 'config/static_sections_transformer.dart';
import 'config/tun_transformer.dart';
import 'config/yaml_helpers.dart';

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
  static const quicRejectPolicyOff = 'off';
  static const quicRejectPolicyGooglevideo = 'googlevideo';
  static const quicRejectPolicyAll = 'all';
  static const defaultQuicRejectPolicy = quicRejectPolicyGooglevideo;

  ConfigTemplate._();

  /// Template variables and their replacement values.
  static const _variables = {r'$app_name': AppConstants.appName};

  // Cached RegExp patterns

  static final _reMixedPort = RegExp(r'^mixed-port:\s*(\d+)', multiLine: true);
  static final _reApiPort = RegExp(
    r'^external-controller:\s*[\w.]*:(\d+)',
    multiLine: true,
  );
  static final _reSecret = RegExp(
    r'^secret:\s*["\x27]?(.+?)["\x27]?\s*$',
    multiLine: true,
  );
  static final _reProxiesSection = RegExp(r'^proxies:\s*\n', multiLine: true);

  static String normalizeQuicRejectPolicy(String? policy) {
    switch (policy) {
      case quicRejectPolicyOff:
      case quicRejectPolicyGooglevideo:
      case quicRejectPolicyAll:
        return policy!;
      default:
        return defaultQuicRejectPolicy;
    }
  }

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

  /// Async wrapper around [process] that offloads onto a background
  /// isolate for large configs. Small configs are processed inline to avoid
  /// isolate-spawn overhead (~1-5 ms on mobile).
  ///
  /// Threshold chosen at 200 KB: a typical Loyalsoldier-bundled
  /// subscription runs 5-10 MB, producing ~300-500 ms of string-regex
  /// work on the main isolate — enough to drop 8-30 frames. Below 200 KB
  /// the inline path stays < 50 ms on mid-range phones.
  static Future<String> processInIsolate(
    String rawConfig, {
    int apiPort = AppConstants.defaultApiPort,
    int mixedPort = AppConstants.defaultMixedPort,
    String? secret,
    String connectionMode = 'systemProxy',
    String desktopTunStack = AppConstants.defaultDesktopTunStack,
    List<String> tunBypassAddresses = const [],
    List<String> tunBypassProcesses = const [],
    int? tunFd,
    String? quicRejectPolicy,
    List<String> relayHostWhitelist = const [],
  }) {
    final effectiveQuicRejectPolicy = normalizeQuicRejectPolicy(
      quicRejectPolicy,
    );
    if (rawConfig.length < 200 * 1024) {
      return Future.value(
        process(
          rawConfig,
          apiPort: apiPort,
          mixedPort: mixedPort,
          secret: secret,
          connectionMode: connectionMode,
          desktopTunStack: desktopTunStack,
          tunBypassAddresses: tunBypassAddresses,
          tunBypassProcesses: tunBypassProcesses,
          tunFd: tunFd,
          quicRejectPolicy: effectiveQuicRejectPolicy,
          relayHostWhitelist: relayHostWhitelist,
        ),
      );
    }
    // All closure captures are immutable value types — safe to send to a
    // new isolate. tunFd staying null is fine; process handles that.
    return Isolate.run(
      () => process(
        rawConfig,
        apiPort: apiPort,
        mixedPort: mixedPort,
        secret: secret,
        connectionMode: connectionMode,
        desktopTunStack: desktopTunStack,
        tunBypassAddresses: tunBypassAddresses,
        tunBypassProcesses: tunBypassProcesses,
        tunFd: tunFd,
        quicRejectPolicy: effectiveQuicRejectPolicy,
        relayHostWhitelist: relayHostWhitelist,
      ),
    );
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
    String? quicRejectPolicy,
    List<String> relayHostWhitelist = const [],
  }) {
    final effectiveQuicRejectPolicy = normalizeQuicRejectPolicy(
      quicRejectPolicy,
    );
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

    config = ScalarTransformers.ensureMixedPort(config, mixedPort);
    debugPrint('[Config] 2 mixedPort done');

    config = ScalarTransformers.ensureExternalController(
      config,
      apiPort,
      secret,
    );
    debugPrint('[Config] 3 externalController done');

    config = DnsTransformer.ensureDns(
      config,
      relayHostWhitelist: relayHostWhitelist,
    );
    debugPrint('[Config] 4 dns done');

    config = StaticSectionsTransformer.ensureSniffer(config);
    debugPrint('[Config] 5 sniffer done');

    config = StaticSectionsTransformer.ensureGeodata(config);
    debugPrint('[Config] 6 geodata done');

    config = StaticSectionsTransformer.ensureProfile(config);
    debugPrint('[Config] 7 profile done');

    config = PerformanceTransformer.ensurePerformance(config);
    debugPrint('[Config] 8 performance done');

    config = StaticSectionsTransformer.ensureExperimental(config);
    debugPrint('[Config] 8b experimental done');

    config = ScalarTransformers.ensureAllowLan(config);
    debugPrint('[Config] 9 allowLan done');

    config = ScalarTransformers.ensureIpv6(config);

    config = ScalarTransformers.ensureFindProcessMode(config);
    debugPrint('[Config] 10 findProcessMode done');

    config = RulesTransformer.ensureConnectivityRules(config);
    debugPrint('[Config] 10b connectivityRules done');

    config = ProviderProxyTransformer.ensureProviderProxyDirect(config);
    debugPrint('[Config] 10b2 providerProxyDirect done');

    config = RulesTransformer.ensureQuicReject(
      config,
      effectiveQuicRejectPolicy,
    );
    debugPrint('[Config] 10c quicReject done');

    config = ScalarTransformers.ensureMode(config);
    debugPrint('[Config] 11 mode done');

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      if (connectionMode == 'tun') {
        config = TunTransformer.ensureDesktopTun(
          config,
          desktopTunStack,
          bypassAddresses: tunBypassAddresses,
          bypassProcesses: tunBypassProcesses,
        );
      } else {
        config = TunTransformer.disableTun(config);
      }
    }
    debugPrint('[Config] 12 desktopTun done');

    if (tunFd != null && tunFd > 0) {
      config = TunTransformer.injectTunFd(config, tunFd);
    }
    debugPrint('[Config] 13 tunFd done');

    return config;
  }

  /// Inject an upstream proxy (e.g. soft router) so mihomo routes outbound
  /// connections through it. Adds a `_upstream` proxy entry and sets
  /// `dialer-proxy: _upstream` on all user-defined proxies.
  static String injectUpstreamProxy(
    String config,
    String type,
    String server,
    int port,
  ) {
    try {
      final yaml = loadYaml(config);
      if (yaml is! YamlMap) return config;
      final mutable = _toMutable(yaml) as Map<String, dynamic>;

      final proxies =
          (mutable['proxies'] as List<dynamic>?)?.cast<dynamic>() ??
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
    String config,
    List<String> chainNames,
    String activeGroup, {
    List<Map<String, dynamic>>? externalProxies,
  }) {
    if (chainNames.length < 2) return config;
    try {
      final yaml = loadYaml(config);
      if (yaml is! YamlMap) return config;
      final mutable = _toMutable(yaml) as Map<String, dynamic>;

      final proxies =
          (mutable['proxies'] as List<dynamic>?)?.cast<dynamic>() ??
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
        (g) => g is Map && _isChainGroup(g['name'] as String? ?? ''),
      );
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
        final existingNames = proxies
            .whereType<Map<String, dynamic>>()
            .map((p) => p['name'])
            .toSet();
        for (final ep in externalProxies) {
          if (ep['name'] != null && !existingNames.contains(ep['name'])) {
            proxies.add(Map<String, dynamic>.from(ep));
            existingNames.add(ep['name']);
          }
        }
      }

      // Verify that the active group exists in this config.
      final hasGroup = proxyGroups.any(
        (g) => g is Map<String, dynamic> && g['name'] == activeGroup,
      );
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

      final proxies =
          (mutable['proxies'] as List<dynamic>?)?.cast<dynamic>() ??
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
        (g) => g is Map && _isChainGroup(g['name'] as String? ?? ''),
      );

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
        value.entries.map(
          (e) => MapEntry(e.key.toString(), _toMutable(e.value)),
        ),
      );
    } else if (value is YamlList) {
      return value.map(_toMutable).toList();
    }
    return value;
  }

  /// Force-set mixed-port, replacing an existing value if present.
  /// Used by CoreManager to remap the port when it is already in use.
  static String setMixedPort(String config, int port) {
    return ScalarTransformers.setMixedPort(config, port);
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
    return _fallbackTemplateFuture ??= rootBundle.loadString(
      'assets/default_config.yaml',
    );
  }

  /// Determine if a subscription config is complete (has groups + rules).
  ///
  /// Most subscriptions (机场) deliver complete configs. Only use the
  /// fallback template when the subscription provides raw proxies only.
  static bool isCompleteConfig(String config) {
    return hasKey(config, 'proxy-groups') && hasKey(config, 'rules');
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

    if (hasKey(fallbackTemplate, 'proxies')) {
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
