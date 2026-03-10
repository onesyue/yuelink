import 'dart:isolate';

import 'package:yaml/yaml.dart' as yaml_pkg;

import 'settings_service.dart';

/// A single node filter rule.
class NodeFilterRule {
  final NodeFilterAction action;
  final String pattern; // regex pattern
  final String? renameTo; // only for rename action; may contain \$1 backrefs

  const NodeFilterRule({
    required this.action,
    required this.pattern,
    this.renameTo,
  });

  factory NodeFilterRule.fromJson(Map<String, dynamic> j) => NodeFilterRule(
        action: NodeFilterAction.values.byName(j['action'] as String),
        pattern: j['pattern'] as String,
        renameTo: j['renameTo'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'action': action.name,
        'pattern': pattern,
        if (renameTo != null) 'renameTo': renameTo,
      };
}

enum NodeFilterAction { keep, exclude, rename }

/// Applies regex-based node filter rules to YAML proxy configs.
///
/// Rules are processed in order:
///   - keep:    only nodes whose name matches are retained (whitelist)
///   - exclude: nodes whose name matches are removed (blacklist)
///   - rename:  nodes whose name matches are renamed (supports regex groups)
///
/// If no keep rules exist, all nodes pass through by default.
/// Processing runs in a background Isolate to avoid UI jank.
class NodeFilterService {
  NodeFilterService._();
  static final instance = NodeFilterService._();

  static const _settingsKey = 'nodeFilterRules';

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<List<NodeFilterRule>> loadRules() async {
    final raw = await SettingsService.get<List>(_settingsKey);
    if (raw == null) return [];
    return raw
        .map((e) => NodeFilterRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveRules(List<NodeFilterRule> rules) async {
    await SettingsService.set(
        _settingsKey, rules.map((r) => r.toJson()).toList());
  }

  // ── Apply ─────────────────────────────────────────────────────────────────

  /// Apply all saved filter rules to a YAML config string.
  /// Returns the modified YAML. If rules are empty, returns original unchanged.
  Future<String> apply(String configYaml) async {
    final rules = await loadRules();
    if (rules.isEmpty) return configYaml;
    // Run heavy YAML processing in background isolate
    return Isolate.run(() => _applyRules(configYaml, rules));
  }

  static String _applyRules(String configYaml, List<NodeFilterRule> rules) {
    // Parse YAML
    final doc = yaml_pkg.loadYaml(configYaml);
    if (doc is! Map) return configYaml;

    final proxies = doc['proxies'];
    if (proxies is! List) return configYaml;

    // Convert to mutable list of mutable maps
    var nodes = proxies
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Separate rule types
    final keepRules =
        rules.where((r) => r.action == NodeFilterAction.keep).toList();
    final excludeRules =
        rules.where((r) => r.action == NodeFilterAction.exclude).toList();
    final renameRules =
        rules.where((r) => r.action == NodeFilterAction.rename).toList();

    // Apply keep rules (whitelist) — only if any keep rules exist
    if (keepRules.isNotEmpty) {
      final patterns = keepRules.map((r) {
        try {
          return RegExp(r.pattern, caseSensitive: false);
        } catch (_) {
          return null;
        }
      }).whereType<RegExp>().toList();

      nodes = nodes.where((n) {
        final name = n['name'] as String? ?? '';
        return patterns.any((p) => p.hasMatch(name));
      }).toList();
    }

    // Apply exclude rules (blacklist)
    for (final rule in excludeRules) {
      RegExp? rx;
      try {
        rx = RegExp(rule.pattern, caseSensitive: false);
      } catch (_) {
        continue;
      }
      nodes = nodes
          .where((n) => !rx!.hasMatch(n['name'] as String? ?? ''))
          .toList();
    }

    // Apply rename rules
    for (final rule in renameRules) {
      RegExp? rx;
      try {
        rx = RegExp(rule.pattern, caseSensitive: false);
      } catch (_) {
        continue;
      }
      final renameTo = rule.renameTo ?? '';
      for (final node in nodes) {
        final name = node['name'] as String? ?? '';
        if (rx.hasMatch(name)) {
          node['name'] = name.replaceAllMapped(rx, (m) {
            String result = renameTo;
            for (var i = 0; i <= m.groupCount; i++) {
              result = result.replaceAll('\$$i', m.group(i) ?? '');
            }
            return result;
          });
        }
      }
    }

    // Rebuild YAML string manually (line-by-line replacement isn't safe;
    // use a simple serializer that preserves the rest of the config)
    return _rebuildYaml(configYaml, nodes);
  }

  /// Replace the proxies list in the YAML string with the filtered nodes.
  /// We rebuild only the proxies block to avoid touching the rest of the config.
  static String _rebuildYaml(
      String original, List<Map<String, dynamic>> nodes) {
    // Convert nodes back to YAML entries (simple inline format)
    final proxiesYaml = nodes.map((n) {
      final fields = n.entries
          .map((e) {
            final v = e.value;
            if (v is String && (v.contains(':') || v.contains('#') || v.isEmpty)) {
              return '${e.key}: "${v.replaceAll('"', '\\"')}"';
            }
            return '${e.key}: $v';
          })
          .join(', ');
      return '  {$fields}';
    }).join('\n');

    // Find and replace the proxies block
    final proxiesBlockRx = RegExp(
      r'^proxies:\s*\n((?:  .+\n?)*)',
      multiLine: true,
    );

    if (proxiesBlockRx.hasMatch(original)) {
      return original.replaceFirstMapped(proxiesBlockRx, (m) {
        return 'proxies:\n$proxiesYaml\n';
      });
    }

    // If no proxies block found, return original unchanged
    return original;
  }
}
