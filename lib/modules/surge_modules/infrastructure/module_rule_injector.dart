import 'package:flutter/foundation.dart';

import 'module_repository.dart';

/// Injects rules from enabled Surge modules into a mihomo config YAML string.
///
/// Rules from all enabled modules are prepended before the existing [Rule]
/// section. If no [Rule] section exists, a new one is appended at the end
/// of the config.
///
/// Log prefix: [ModuleRuntime]
class ModuleRuleInjector {
  ModuleRuleInjector._();

  /// Inject enabled module rules into [configYaml].
  ///
  /// Returns the modified config string. Returns [configYaml] unchanged if
  /// there are no enabled module rules (fast path, no I/O cost beyond a
  /// brief repository scan).
  static Future<String> inject(String configYaml) async {
    final rules = await const ModuleRepository().getEnabledRules();
    if (rules.isEmpty) {
      debugPrint('[ModuleRuntime] no enabled module rules — skipping injection');
      return configYaml;
    }

    debugPrint('[ModuleRuntime] injecting ${rules.length} module rules');

    // Format rules as YAML list items: "  - RULE_LINE\n"
    final rulesBlock = rules.map((r) => '  - $r').join('\n');

    // Try to prepend into existing rules: section
    final rulesPattern = RegExp(r'^(rules:\s*\n)', multiLine: true);
    final match = rulesPattern.firstMatch(configYaml);

    if (match != null) {
      // Insert after "rules:\n"
      final injected = configYaml.replaceFirstMapped(
        rulesPattern,
        (m) => '${m.group(1)}$rulesBlock\n',
      );
      debugPrint('[ModuleRuntime] rules injected into existing rules: section');
      return injected;
    }

    // No rules: section found — append at end of config
    debugPrint('[ModuleRuntime] no rules: section found — appending at end');
    final separator = configYaml.endsWith('\n') ? '' : '\n';
    return '$configYaml${separator}rules:\n$rulesBlock\n';
  }
}
