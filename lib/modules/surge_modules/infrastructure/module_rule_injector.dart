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

  static const _mitmProxyName = '_mitm_engine';

  /// Inject enabled module rules (and MITM routing if [mitmPort] > 0) into
  /// [configYaml]. Returns the modified config string unchanged when there is
  /// nothing to inject.
  static Future<String> inject(String configYaml, {int mitmPort = 0}) async {
    final repo = const ModuleRepository();

    final rules = await repo.getEnabledRules();

    // Collect MITM hostname rules when engine is running.
    List<String> mitmRules = [];
    if (mitmPort > 0) {
      final hostnames = await repo.getEnabledMitmHostnames();
      if (hostnames.isNotEmpty) {
        mitmRules = _hostnameToRules(hostnames);
        debugPrint(
            '[ModuleRuntime] MITM engine on port $mitmPort — routing '
            '${hostnames.length} hostname(s) to $_mitmProxyName');
      }
    }

    if (rules.isEmpty && mitmRules.isEmpty) {
      debugPrint('[ModuleRuntime] no enabled module rules — skipping injection');
      return configYaml;
    }

    debugPrint(
        '[ModuleRuntime] injecting ${rules.length} module rules'
        '${mitmRules.isNotEmpty ? ' + ${mitmRules.length} MITM rules' : ''}');

    String result = configYaml;

    // Inject _mitm_engine proxy entry when MITM rules are present.
    if (mitmRules.isNotEmpty) {
      result = _injectMitmProxy(result, mitmPort);
    }

    // All rules to inject: MITM hostname rules first, then module rules.
    final allRules = [...mitmRules, ...rules];
    result = _injectRules(result, allRules);

    return result;
  }

  // ---------------------------------------------------------------------------
  // Hostname → Rule conversion
  // ---------------------------------------------------------------------------

  /// Convert Surge-style MITM hostnames to mihomo rule strings targeting
  /// `_mitm_engine`.
  ///
  /// Patterns:
  ///   `.example.com`   → DOMAIN-SUFFIX,example.com,_mitm_engine
  ///   `*.example.com`  → DOMAIN-SUFFIX,example.com,_mitm_engine
  ///   `example.com`    → DOMAIN,example.com,_mitm_engine
  static List<String> _hostnameToRules(List<String> hostnames) {
    final rules = <String>[];
    for (final h in hostnames) {
      final clean = h.trim();
      if (clean.isEmpty) continue;
      if (clean.startsWith('.')) {
        rules.add('DOMAIN-SUFFIX,${clean.substring(1)},$_mitmProxyName');
      } else if (clean.startsWith('*.')) {
        rules.add('DOMAIN-SUFFIX,${clean.substring(2)},$_mitmProxyName');
      } else {
        rules.add('DOMAIN,$clean,$_mitmProxyName');
      }
    }
    return rules;
  }

  // ---------------------------------------------------------------------------
  // Proxy injection
  // ---------------------------------------------------------------------------

  /// Inject the `_mitm_engine` HTTP proxy into the `proxies:` section.
  /// If no `proxies:` section exists, one is prepended before the first
  /// top-level section (or appended at end).
  static String _injectMitmProxy(String yaml, int port) {
    final proxyEntry = '  - name: $_mitmProxyName\n'
        '    type: http\n'
        '    server: 127.0.0.1\n'
        '    port: $port\n';

    // Try to insert after "proxies:\n"
    final proxiesPattern = RegExp(r'^(proxies:\s*\n)', multiLine: true);
    final match = proxiesPattern.firstMatch(yaml);

    if (match != null) {
      // Check if _mitm_engine is already present (idempotent).
      if (yaml.contains('name: $_mitmProxyName')) {
        // Update the port in the existing entry.
        return yaml.replaceFirst(
          RegExp(r'(name: _mitm_engine\n\s+type: http\n\s+server: 127\.0\.0\.1\n\s+port: )\d+'),
          '${match.group(0)!.split('\n').last}$port',
        );
      }
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
  // Rule injection
  // ---------------------------------------------------------------------------

  /// Prepend [rules] into the existing `rules:` section, or append a new one.
  static String _injectRules(String yaml, List<String> rules) {
    final rulesBlock = rules.map((r) => '  - $r').join('\n');

    final rulesPattern = RegExp(r'^(rules:\s*\n)', multiLine: true);
    final match = rulesPattern.firstMatch(yaml);

    if (match != null) {
      return yaml.replaceFirstMapped(
        rulesPattern,
        (m) => '${m.group(1)}$rulesBlock\n',
      );
    }

    // No rules: section — append.
    final sep = yaml.endsWith('\n') ? '' : '\n';
    return '${yaml}${sep}rules:\n$rulesBlock\n';
  }
}
