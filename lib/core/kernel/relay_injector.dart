import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

import '../../domain/models/relay_profile.dart';

/// Outcome of a [RelayInjector.apply] call.
///
/// `config` is always non-null — on skip / failure it equals the input, so
/// callers can always forward the field downstream unconditionally.
/// `injected` and `targetCount` tell telemetry whether the relay actually
/// took effect or was a silent no-op; `skipReason` carries a fixed-enum
/// short string for grouping (never a raw error message).
class RelayApplyResult {
  final String config;
  final bool injected;
  final int targetCount;
  final String? skipReason;

  const RelayApplyResult({
    required this.config,
    required this.injected,
    this.targetCount = 0,
    this.skipReason,
  });

  /// Skip reasons are a closed set — expanding it is a deliberate telemetry
  /// schema change, not a free-form string drop.
  static const skipNoProfile = 'no_profile';
  static const skipInvalidProfile = 'invalid_profile';
  static const skipNotYaml = 'not_yaml';
  static const skipNoProxies = 'no_proxies';
  static const skipNameCollision = 'name_collision';
  static const skipNoTargets = 'no_targets';
  static const skipException = 'exception';

  factory RelayApplyResult.noop(String config, {required String reason}) {
    return RelayApplyResult(
      config: config,
      injected: false,
      skipReason: reason,
    );
  }
}

/// Inject a commercial dialer-proxy relay into a raw mihomo YAML config.
///
/// Runs during `_prepareConfig`, before `ConfigTemplate.processInIsolate()`.
/// Never throws — on any failure the original config is returned unchanged
/// (via [RelayApplyResult.noop]) so relay problems can never block cold-start.
///
/// Scope for Phase 1A:
///   * only [RelaySource.commercial] profiles are materialised.
///   * target nodes come from [RelayTargetMode] — never all proxies, never HY2.
///   * output: one extra `_yue_relay` entry in `proxies:` plus
///     `dialer-proxy: _yue_relay` on each target node.
class RelayInjector {
  RelayInjector._();

  /// Reserved name for the injected relay proxy. Leading underscore
  /// namespaces it away from user nodes; matches the existing
  /// `_upstream` convention.
  static const relayNodeName = '_yue_relay';

  /// Transform [config]. Always returns a [RelayApplyResult] — on no-op the
  /// `config` field equals the input and `injected` is false, with a fixed
  /// `skipReason` describing why.
  static RelayApplyResult apply(String config, RelayProfile? profile) {
    if (profile == null) {
      return RelayApplyResult.noop(config,
          reason: RelayApplyResult.skipNoProfile);
    }
    if (!profile.isValid) {
      return RelayApplyResult.noop(config,
          reason: RelayApplyResult.skipInvalidProfile);
    }

    try {
      final yaml = loadYaml(config);
      if (yaml is! YamlMap) {
        return RelayApplyResult.noop(config,
            reason: RelayApplyResult.skipNotYaml);
      }
      final mutable = _toMutable(yaml) as Map<String, dynamic>;

      final proxies =
          (mutable['proxies'] as List<dynamic>?)?.cast<dynamic>() ?? <dynamic>[];
      if (proxies.isEmpty) {
        return RelayApplyResult.noop(config,
            reason: RelayApplyResult.skipNoProxies);
      }

      // Name-collision guard. A subscription that already defines `_yue_relay`
      // gets to keep its definition; we bail rather than silently overwrite.
      final existingNames = <String>{};
      for (final p in proxies) {
        if (p is Map && p['name'] is String) {
          existingNames.add(p['name'] as String);
        }
      }
      if (existingNames.contains(relayNodeName)) {
        debugPrint('[RelayInjector] skip: "$relayNodeName" already exists');
        return RelayApplyResult.noop(config,
            reason: RelayApplyResult.skipNameCollision);
      }

      final targets = _pickTargets(proxies, profile);
      if (targets.isEmpty) {
        debugPrint('[RelayInjector] skip: no target nodes matched '
            '(mode=${profile.targetMode.name})');
        return RelayApplyResult.noop(config,
            reason: RelayApplyResult.skipNoTargets);
      }

      // Cycle safety: the relay itself must not carry a dialer-proxy. Since
      // relayNodeName is newly inserted and we refuse to target it (see the
      // name check above), no cycle can form.
      final relayNode = <String, dynamic>{
        'name': relayNodeName,
        'type': profile.type,
        'server': profile.host,
        'port': profile.port,
        'udp': true,
        ...profile.extras,
      };
      // extras must not override the identity fields.
      relayNode['name'] = relayNodeName;
      relayNode['type'] = profile.type;
      relayNode['server'] = profile.host;
      relayNode['port'] = profile.port;
      relayNode.remove('dialer-proxy');

      proxies.insert(0, relayNode);

      for (final p in proxies) {
        if (p is Map<String, dynamic> &&
            p['name'] != relayNodeName &&
            targets.contains(p['name'])) {
          p['dialer-proxy'] = relayNodeName;
        }
      }

      mutable['proxies'] = proxies;
      return RelayApplyResult(
        config: YamlWriter().write(mutable),
        injected: true,
        targetCount: targets.length,
      );
    } catch (e) {
      debugPrint('[RelayInjector] apply failed, returning input: $e');
      return RelayApplyResult.noop(config,
          reason: RelayApplyResult.skipException);
    }
  }

  static Set<String> _pickTargets(List<dynamic> proxies, RelayProfile profile) {
    final targets = <String>{};
    switch (profile.targetMode) {
      case RelayTargetMode.allVless:
        for (final p in proxies) {
          if (p is! Map) continue;
          final name = p['name'];
          final type = p['type'];
          if (name is! String || type is! String) continue;
          if (type.toLowerCase() == 'vless') targets.add(name);
        }
      case RelayTargetMode.allowlistNames:
        final allow = profile.allowlistNames.toSet();
        for (final p in proxies) {
          if (p is! Map) continue;
          final name = p['name'];
          final type = p['type'];
          if (name is! String || type is! String) continue;
          if (!allow.contains(name)) continue;
          // HY2 guardrail: Phase 1A refuses to wrap hysteria2 nodes even if
          // the user allowlists them by name. dialer-proxy + UDP-based
          // transports needs its own validation track before we enable it.
          if (type.toLowerCase() == 'hysteria2' || type.toLowerCase() == 'hy2') {
            debugPrint(
                '[RelayInjector] skip HY2 node "$name" — Phase 1A guardrail');
            continue;
          }
          targets.add(name);
        }
    }
    return targets;
  }

  static dynamic _toMutable(dynamic value) {
    if (value is YamlMap) {
      return Map<String, dynamic>.fromEntries(
        value.entries
            .map((e) => MapEntry(e.key.toString(), _toMutable(e.value))),
      );
    }
    if (value is YamlList) {
      return value.map(_toMutable).toList();
    }
    return value;
  }
}
