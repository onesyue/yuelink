import 'package:flutter/foundation.dart';

import 'module_repository.dart';

/// Injects rules (and optionally MITM routing) from enabled Surge modules
/// into a mihomo config YAML string.
///
/// Phase 0: injects [Rule] entries from enabled modules.
/// Phase 1: if [mitmPort] > 0, also injects:
///   - A `_mitm_engine` HTTP proxy in the `proxies:` section.
///   - DOMAIN/DOMAIN-SUFFIX rules for each MITM hostname pointing to
///     `_mitm_engine`, prepended before other module rules.
///
/// Log prefix: [ModuleRuntime]
class ModuleRuleInjector {
  ModuleRuleInjector._();

  static const mitmProxyName = '_mitm_engine';

  // ---------------------------------------------------------------------------
  // Public entry point (I/O)
  // ---------------------------------------------------------------------------

  /// Inject enabled module rules (and MITM routing if [mitmPort] > 0) into
  /// [configYaml]. Returns the modified config string unchanged when there is
  /// nothing to inject.
  static Future<String> inject(String configYaml, {int mitmPort = 0}) async {
    final repo = const ModuleRepository();
    final moduleRules = await repo.getEnabledRules();
    final mitmHostnames = mitmPort > 0
        ? await repo.getEnabledMitmHostnames()
        : const <String>[];

    return injectFromLists(
      configYaml,
      mitmPort: mitmPort,
      moduleRules: moduleRules,
      mitmHostnames: mitmHostnames,
    );
  }

  // ---------------------------------------------------------------------------
  // Pure transformation entry point (no I/O — testable directly)
  // ---------------------------------------------------------------------------

  /// Inject rules from pre-resolved lists into [configYaml].
  ///
  /// This pure function contains all YAML transformation logic and has no
  /// filesystem or repository dependencies. Used by [inject] and by tests.
  static String injectFromLists(
    String configYaml, {
    int mitmPort = 0,
    List<String> moduleRules = const [],
    List<String> mitmHostnames = const [],
  }) {
    final mitmRules =
        mitmPort > 0 ? hostnameToRules(mitmHostnames) : const <String>[];

    if (moduleRules.isEmpty && mitmRules.isEmpty) {
      debugPrint('[ModuleRuntime] no enabled module rules — skipping injection');
      return configYaml;
    }

    debugPrint(
        '[ModuleRuntime] injecting ${moduleRules.length} module rules'
        '${mitmRules.isNotEmpty ? ' + ${mitmRules.length} MITM rules' : ''}');

    var result = configYaml;

    if (mitmRules.isNotEmpty) {
      result = injectMitmProxy(result, mitmPort);
    }

    final allRules = [...mitmRules, ...moduleRules];
    result = injectRules(result, allRules);
    return result;
  }

  // ---------------------------------------------------------------------------
  // Hostname → Rule conversion  (public, pure, no side-effects)
  // ---------------------------------------------------------------------------

  /// Convert Surge-style MITM hostnames to mihomo rule strings targeting
  /// `_mitm_engine`.
  ///
  /// Patterns:
  ///   `.example.com`   → DOMAIN-SUFFIX,example.com,_mitm_engine
  ///   `*.example.com`  → DOMAIN-SUFFIX,example.com,_mitm_engine
  ///   `example.com`    → DOMAIN,example.com,_mitm_engine
  static List<String> hostnameToRules(List<String> hostnames) {
    final rules = <String>[];
    for (final h in hostnames) {
      final clean = h.trim();
      if (clean.isEmpty) continue;
      if (clean.startsWith('.')) {
        rules.add('DOMAIN-SUFFIX,${clean.substring(1)},$mitmProxyName');
      } else if (clean.startsWith('*.')) {
        rules.add('DOMAIN-SUFFIX,${clean.substring(2)},$mitmProxyName');
      } else {
        rules.add('DOMAIN,$clean,$mitmProxyName');
      }
    }
    return rules;
  }

  // ---------------------------------------------------------------------------
  // Proxy injection  (public, pure, no side-effects)
  // ---------------------------------------------------------------------------

  /// Inject the `_mitm_engine` HTTP proxy into the `proxies:` section.
  ///
  /// Behaviour:
  /// - If `proxies:` exists and `_mitm_engine` is **absent** → prepend entry.
  /// - If `proxies:` exists and `_mitm_engine` is **present** → update port only.
  /// - If `proxies:` is **absent** → create section before first known section.
  /// - If nothing matches → append at end.
  static String injectMitmProxy(String yaml, int port) {
    final proxyEntry = '  - name: $mitmProxyName\n'
        '    type: http\n'
        '    server: 127.0.0.1\n'
        '    port: $port\n';

    final proxiesPattern = RegExp(r'^(proxies:\s*\n)', multiLine: true);
    final match = proxiesPattern.firstMatch(yaml);

    if (match != null) {
      // Idempotent update: _mitm_engine already present → update port only.
      if (yaml.contains('name: $mitmProxyName')) {
        return yaml.replaceFirstMapped(
          RegExp(
              r'(name: _mitm_engine\n\s+type: http\n\s+server: 127\.0\.0\.1\n\s+port: )\d+'),
          (m) => '${m.group(1)}$port',
        );
      }
      // First injection: prepend entry after "proxies:\n".
      return yaml.replaceFirstMapped(
        proxiesPattern,
        (m) => '${m.group(1)}$proxyEntry',
      );
    }

    // No proxies: section — inject one before the first known section.
    final firstSection = RegExp(
        r'^(proxy-groups:|rules:|dns:|tun:|listeners:)',
        multiLine: true);
    final sectionMatch = firstSection.firstMatch(yaml);
    if (sectionMatch != null) {
      final before = yaml.substring(0, sectionMatch.start);
      final after = yaml.substring(sectionMatch.start);
      return '${before}proxies:\n$proxyEntry\n$after';
    }

    // Fallback: append at end.
    final sep = yaml.endsWith('\n') ? '' : '\n';
    return '${yaml}${sep}proxies:\n$proxyEntry\n';
  }

  // ---------------------------------------------------------------------------
  // Rule injection  (public, pure, no side-effects)
  // ---------------------------------------------------------------------------

  /// Prepend [rules] into the existing `rules:` section, or append a new one.
  ///
  /// Indentation is detected from the FIRST existing rule item, matching the
  /// subscription's format (e.g. "    - rule" for 4-space, "  - rule" for
  /// 2-space, "- rule" for 0-space). Mismatched indentation causes go-yaml to
  /// treat subsequent items as a multiline plain-scalar continuation of the
  /// last injected rule, concatenating all remaining rules into one broken
  /// rule string (e.g. "DOMAIN,x,DIRECT - 'DOMAIN,y,...'").
  static String injectRules(String yaml, List<String> rules) {
    if (rules.isEmpty) return yaml;

    final rulesPattern = RegExp(r'^(rules:\s*\n)', multiLine: true);
    final match = rulesPattern.firstMatch(yaml);

    if (match != null) {
      // Detect indentation from the first existing rule item so the injected
      // rules use the same column as the subscription's rules.
      final afterHeader = yaml.substring(match.end);
      final firstItem =
          RegExp(r'^([ \t]*)-[ \t]', multiLine: true).firstMatch(afterHeader);
      final indent = firstItem?.group(1) ?? '  ';

      final rulesBlock = rules.map((r) => '$indent- $r').join('\n');
      return yaml.replaceFirstMapped(
        rulesPattern,
        (m) => '${m.group(1)}$rulesBlock\n',
      );
    }

    // No rules: section — append with default 2-space indent.
    final rulesBlock = rules.map((r) => '  - $r').join('\n');
    final sep = yaml.endsWith('\n') ? '' : '\n';
    return '${yaml}${sep}rules:\n$rulesBlock\n';
  }
}
