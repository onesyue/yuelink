import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/infrastructure/surge_modules/module_rule_injector.dart';

// ignore_for_file: lines_longer_than_80_chars

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // hostnameToRules
  // ══════════════════════════════════════════════════════════════════════════

  group('ModuleRuleInjector.hostnameToRules', () {
    test('exact hostname → DOMAIN rule', () {
      expect(
        ModuleRuleInjector.hostnameToRules(['example.com']),
        ['DOMAIN,example.com,_mitm_engine'],
      );
    });

    test('.example.com → DOMAIN-SUFFIX rule (dot prefix)', () {
      expect(
        ModuleRuleInjector.hostnameToRules(['.example.com']),
        ['DOMAIN-SUFFIX,example.com,_mitm_engine'],
      );
    });

    test('*.example.com → DOMAIN-SUFFIX rule (wildcard)', () {
      expect(
        ModuleRuleInjector.hostnameToRules(['*.example.com']),
        ['DOMAIN-SUFFIX,example.com,_mitm_engine'],
      );
    });

    test('.example.com and *.example.com produce the same rule', () {
      final r1 = ModuleRuleInjector.hostnameToRules(['.example.com']);
      final r2 = ModuleRuleInjector.hostnameToRules(['*.example.com']);
      expect(r1, r2);
    });

    test('multiple hostnames → multiple rules in order', () {
      final result = ModuleRuleInjector.hostnameToRules([
        'example.com',
        '.sub.org',
        '*.wildcard.io',
      ]);
      expect(result, [
        'DOMAIN,example.com,_mitm_engine',
        'DOMAIN-SUFFIX,sub.org,_mitm_engine',
        'DOMAIN-SUFFIX,wildcard.io,_mitm_engine',
      ]);
    });

    test('empty string is skipped', () {
      expect(ModuleRuleInjector.hostnameToRules(['']), isEmpty);
    });

    test('whitespace-only string is skipped', () {
      expect(ModuleRuleInjector.hostnameToRules(['   ']), isEmpty);
    });

    test('whitespace around hostname is trimmed', () {
      expect(
        ModuleRuleInjector.hostnameToRules(['  example.com  ']),
        ['DOMAIN,example.com,_mitm_engine'],
      );
    });

    test('empty list → empty result', () {
      expect(ModuleRuleInjector.hostnameToRules([]), isEmpty);
    });

    test('mixed valid and empty entries — empty skipped', () {
      final result = ModuleRuleInjector.hostnameToRules([
        '',
        'example.com',
        '  ',
        '*.foo.bar',
      ]);
      expect(result, [
        'DOMAIN,example.com,_mitm_engine',
        'DOMAIN-SUFFIX,foo.bar,_mitm_engine',
      ]);
    });

    test('all rules target _mitm_engine', () {
      final result = ModuleRuleInjector.hostnameToRules([
        'a.com',
        '.b.com',
        '*.c.com',
      ]);
      for (final r in result) {
        expect(r, endsWith(',_mitm_engine'));
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // injectMitmProxy
  // ══════════════════════════════════════════════════════════════════════════

  group('ModuleRuleInjector.injectMitmProxy', () {
    const port = 9091;
    const otherPort = 12345;

    // ── Case 1: proxies: exists, _mitm_engine absent → first injection ──────

    test('Case 1: first injection into existing proxies: section', () {
      const yaml = 'mixed-port: 7890\nproxies:\n  - name: OtherProxy\n    type: ss\n';
      final result = ModuleRuleInjector.injectMitmProxy(yaml, port);

      expect(result, contains('name: _mitm_engine'));
      expect(result, contains('type: http'));
      expect(result, contains('server: 127.0.0.1'));
      expect(result, contains('port: $port'));
      // Original proxy still present
      expect(result, contains('name: OtherProxy'));
      // _mitm_engine comes before OtherProxy
      expect(result.indexOf('_mitm_engine'), lessThan(result.indexOf('OtherProxy')));
    });

    // ── Case 2: proxies: exists and has other proxies → inserted at top ─────

    test('Case 2: existing proxies section gets _mitm_engine prepended', () {
      const yaml = 'proxies:\n  - name: A\n    type: ss\n  - name: B\n    type: vmess\n';
      final result = ModuleRuleInjector.injectMitmProxy(yaml, port);

      final mitm = result.indexOf('_mitm_engine');
      final a = result.indexOf('name: A');
      final b = result.indexOf('name: B');
      expect(mitm, lessThan(a));
      expect(a, lessThan(b));
    });

    // ── Case 3: idempotent update — port changes, YAML stays valid ───────────

    test('Case 3: idempotent — same port, no duplicate entry', () {
      const yaml = 'proxies:\n'
          '  - name: _mitm_engine\n'
          '    type: http\n'
          '    server: 127.0.0.1\n'
          '    port: $port\n';
      final result = ModuleRuleInjector.injectMitmProxy(yaml, port);

      expect('name: _mitm_engine'.allMatches(result).length, 1,
          reason: '_mitm_engine should appear exactly once');
      expect(result, contains('port: $port'));
    });

    test('Case 3: port update preserves "port: " prefix (P0 regression)', () {
      const yaml = 'proxies:\n'
          '  - name: _mitm_engine\n'
          '    type: http\n'
          '    server: 127.0.0.1\n'
          '    port: $port\n';
      final result = ModuleRuleInjector.injectMitmProxy(yaml, otherPort);

      // New port must appear with prefix intact
      expect(result, contains('port: $otherPort'));
      // Old port must be gone
      expect(result, isNot(contains('port: $port')));
      // Only one _mitm_engine entry
      expect('name: _mitm_engine'.allMatches(result).length, 1);
      // YAML is not broken — no raw number on its own line
      for (final line in result.split('\n')) {
        final trimmed = line.trim();
        if (trimmed == '$otherPort' || trimmed == '$port') {
          fail('Raw port number found on a line without "port: " prefix: $line');
        }
      }
    });

    test('Case 3: port update from A to B back to A stays correct', () {
      var yaml = 'proxies:\n'
          '  - name: _mitm_engine\n'
          '    type: http\n'
          '    server: 127.0.0.1\n'
          '    port: $port\n';
      yaml = ModuleRuleInjector.injectMitmProxy(yaml, otherPort);
      yaml = ModuleRuleInjector.injectMitmProxy(yaml, port);

      expect(yaml, contains('port: $port'));
      expect(yaml, isNot(contains('port: $otherPort')));
      expect('name: _mitm_engine'.allMatches(yaml).length, 1);
    });

    // ── Case 4: no proxies: section → creates one ────────────────────────────

    test('Case 4: no proxies: section, creates one before rules:', () {
      const yaml = 'mixed-port: 7890\nrules:\n  - MATCH,DIRECT\n';
      final result = ModuleRuleInjector.injectMitmProxy(yaml, port);

      expect(result, contains('proxies:'));
      expect(result, contains('name: _mitm_engine'));
      // proxies section comes before rules
      expect(result.indexOf('proxies:'), lessThan(result.indexOf('rules:')));
    });

    test('Case 4: no proxies: section, creates one before proxy-groups:', () {
      const yaml = 'mixed-port: 7890\nproxy-groups:\n  - name: G1\n';
      final result = ModuleRuleInjector.injectMitmProxy(yaml, port);

      expect(result, contains('proxies:'));
      expect(result.indexOf('proxies:'), lessThan(result.indexOf('proxy-groups:')));
    });

    test('Case 4: totally bare config → appends proxies at end', () {
      const yaml = 'mixed-port: 7890\n';
      final result = ModuleRuleInjector.injectMitmProxy(yaml, port);

      expect(result, contains('proxies:'));
      expect(result, contains('name: _mitm_engine'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // injectRules
  // ══════════════════════════════════════════════════════════════════════════

  group('ModuleRuleInjector.injectRules', () {
    test('prepends rules into existing rules: section (2-space indent)', () {
      const yaml = 'mixed-port: 7890\nrules:\n  - MATCH,DIRECT\n';
      final result = ModuleRuleInjector.injectRules(
          yaml, ['DOMAIN,example.com,PROXY']);
      expect(result, contains('  - DOMAIN,example.com,PROXY'));
      expect(result.indexOf('DOMAIN,example.com,PROXY'),
          lessThan(result.indexOf('MATCH,DIRECT')));
    });

    test('detects 4-space indent from existing rules', () {
      // Subscription-style: 4-space indent (common in airport-provided configs).
      // Mismatched indent causes go-yaml to fold subsequent items into a single
      // plain-scalar continuation, producing "DOMAIN,x,DIRECT - 'DOMAIN,y,...'".
      const yaml =
          'mixed-port: 7890\nrules:\n    - MATCH,DIRECT\n    - \'DOMAIN,a.com,DIRECT\'\n';
      final result = ModuleRuleInjector.injectRules(
          yaml, ['DOMAIN,example.com,PROXY']);
      // Injected rule must use the same 4-space indent as existing rules.
      expect(result, contains('    - DOMAIN,example.com,PROXY'));
      // Must NOT use 2-space indent (that would break YAML indentation).
      expect(result, isNot(contains('\n  - DOMAIN,example.com,PROXY')));
      // Injected rule must appear before the existing rules.
      expect(result.indexOf('DOMAIN,example.com,PROXY'),
          lessThan(result.indexOf('MATCH,DIRECT')));
    });

    test('detects 0-space indent from existing rules', () {
      const yaml = 'mixed-port: 7890\nrules:\n- MATCH,DIRECT\n';
      final result = ModuleRuleInjector.injectRules(
          yaml, ['DOMAIN,example.com,PROXY']);
      expect(result, contains('- DOMAIN,example.com,PROXY'));
    });

    test('appends rules: section when absent', () {
      const yaml = 'mixed-port: 7890\n';
      final result =
          ModuleRuleInjector.injectRules(yaml, ['MATCH,DIRECT']);
      expect(result, contains('rules:\n  - MATCH,DIRECT\n'));
    });

    test('empty rules list → yaml unchanged', () {
      const yaml = 'mixed-port: 7890\n';
      expect(ModuleRuleInjector.injectRules(yaml, []), yaml);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // injectFromLists — integration-level tests (no I/O)
  // ══════════════════════════════════════════════════════════════════════════

  group('ModuleRuleInjector.injectFromLists', () {
    // ── Test 1: MITM Engine running + module with mitmHostnames ──────────────

    test('Test 1: running MITM engine — proxy + MITM rules + module rules', () {
      const yaml = 'mixed-port: 7890\n'
          'proxies:\n'
          '  - name: Existing\n'
          '    type: ss\n'
          'rules:\n'
          '  - MATCH,DIRECT\n';

      final result = ModuleRuleInjector.injectFromLists(
        yaml,
        mitmPort: 9091,
        moduleRules: ['DOMAIN,cdn.example.net,PROXY'],
        mitmHostnames: ['example.com', '*.sub.org', '.test.local'],
      );

      // _mitm_engine proxy injected
      expect(result, contains('name: _mitm_engine'));
      expect(result, contains('type: http'));
      expect(result, contains('server: 127.0.0.1'));
      expect(result, contains('port: 9091'));

      // MITM hostname rules injected with correct type
      expect(result, contains('DOMAIN,example.com,_mitm_engine'));
      expect(result, contains('DOMAIN-SUFFIX,sub.org,_mitm_engine'));
      expect(result, contains('DOMAIN-SUFFIX,test.local,_mitm_engine'));

      // Regular module rule injected
      expect(result, contains('DOMAIN,cdn.example.net,PROXY'));

      // MITM rules come before module rules
      expect(
        result.indexOf('DOMAIN,example.com,_mitm_engine'),
        lessThan(result.indexOf('DOMAIN,cdn.example.net,PROXY')),
      );

      // Module rules come before MATCH fallback
      expect(
        result.indexOf('DOMAIN,cdn.example.net,PROXY'),
        lessThan(result.indexOf('MATCH,DIRECT')),
      );

      // Existing proxy preserved
      expect(result, contains('name: Existing'));
    });

    // ── Test 2: MITM Engine NOT running — no proxy, no MITM rules ───────────

    test('Test 2: mitmPort=0 — no _mitm_engine, only module rules', () {
      const yaml = 'mixed-port: 7890\n'
          'rules:\n'
          '  - MATCH,DIRECT\n';

      final result = ModuleRuleInjector.injectFromLists(
        yaml,
        mitmPort: 0,
        moduleRules: ['DOMAIN,cdn.example.net,PROXY'],
        mitmHostnames: ['example.com'],  // ignored when mitmPort=0
      );

      // No MITM proxy
      expect(result, isNot(contains('_mitm_engine')));
      expect(result, isNot(contains('proxies:')));

      // Regular rule still injected
      expect(result, contains('DOMAIN,cdn.example.net,PROXY'));
    });

    // ── Test 3: mitmPort=0 + no module rules → unchanged ────────────────────

    test('Test 3: nothing to inject → original yaml unchanged', () {
      const yaml = 'mixed-port: 7890\n';
      final result = ModuleRuleInjector.injectFromLists(yaml, mitmPort: 0);
      expect(result, yaml);
    });

    // ── Test 4: engine running but no MITM hostnames ─────────────────────────

    test('Test 4: engine running but no MITM hostnames — no proxy injected', () {
      const yaml = 'mixed-port: 7890\nrules:\n  - MATCH,DIRECT\n';
      final result = ModuleRuleInjector.injectFromLists(
        yaml,
        mitmPort: 9091,
        moduleRules: ['DOMAIN,example.net,PROXY'],
        mitmHostnames: [],
      );
      // No _mitm_engine because no hostnames
      expect(result, isNot(contains('_mitm_engine')));
      expect(result, contains('DOMAIN,example.net,PROXY'));
    });

    // ── Test 5: idempotent port update via injectFromLists ───────────────────

    test('Test 5: re-inject same yaml with new port → port updated cleanly', () {
      const yaml = 'mixed-port: 7890\n'
          'proxies:\n'
          'rules:\n'
          '  - MATCH,DIRECT\n';

      // First injection
      final first = ModuleRuleInjector.injectFromLists(
        yaml,
        mitmPort: 9091,
        mitmHostnames: ['example.com'],
      );
      expect(first, contains('port: 9091'));

      // Port changes (engine restarted on different port)
      final second = ModuleRuleInjector.injectFromLists(
        first,
        mitmPort: 12345,
        mitmHostnames: ['example.com'],
      );
      expect(second, contains('port: 12345'));
      expect(second, isNot(contains('port: 9091')));
      expect('name: _mitm_engine'.allMatches(second).length, 1);
    });

    // ── Test 6: deduplication across calls ───────────────────────────────────

    test('Test 6: MITM rules deduped across multiple hostnames', () {
      // Both .example.com and *.example.com produce the same rule
      final result = ModuleRuleInjector.injectFromLists(
        'rules:\n  - MATCH,DIRECT\n',
        mitmPort: 9091,
        mitmHostnames: ['.example.com', '*.example.com'],
      );
      // hostnameToRules does NOT deduplicate internally (both are added)
      // Dedup happens in getEnabledMitmHostnames (Set-based); here we test
      // that injectFromLists passes hostnames through correctly.
      // Both entries produce DOMAIN-SUFFIX,example.com,_mitm_engine
      final count = 'DOMAIN-SUFFIX,example.com,_mitm_engine'.allMatches(result).length;
      expect(count, 2); // hostnameToRules itself doesn't deduplicate, repo does
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Real-world config fragments
  // ══════════════════════════════════════════════════════════════════════════

  group('ModuleRuleInjector — real-world config fragments', () {
    const typicalConfig = '''mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

proxies:
  - name: "HK-01"
    type: ss
    server: 1.2.3.4
    port: 443
    cipher: chacha20-ietf-poly1305
    password: secret

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - HK-01
      - DIRECT

rules:
  - DOMAIN-SUFFIX,local,DIRECT
  - MATCH,PROXY
''';

    test('injects _mitm_engine before HK-01 in proxies', () {
      final result = ModuleRuleInjector.injectMitmProxy(typicalConfig, 9091);

      expect(result, contains('name: _mitm_engine'));
      // _mitm_engine before HK-01
      expect(
        result.indexOf('_mitm_engine'),
        lessThan(result.indexOf('HK-01')),
      );
      // All original sections preserved
      expect(result, contains('proxy-groups:'));
      expect(result, contains('DOMAIN-SUFFIX,local,DIRECT'));
    });

    test('injectFromLists produces full correct config', () {
      final result = ModuleRuleInjector.injectFromLists(
        typicalConfig,
        mitmPort: 9091,
        moduleRules: ['DOMAIN,ads.tracker.com,REJECT'],
        mitmHostnames: ['api.example.com', '.cdn.example.org'],
      );

      // Proxy section correct
      expect(result, contains('name: _mitm_engine'));
      expect(result, contains('server: 127.0.0.1'));
      expect(result, contains('port: 9091'));

      // Rules order: MITM rules → module rules → original rules
      final mitmIdx = result.indexOf('DOMAIN,api.example.com,_mitm_engine');
      final modIdx = result.indexOf('DOMAIN,ads.tracker.com,REJECT');
      final origIdx = result.indexOf('DOMAIN-SUFFIX,local,DIRECT');
      expect(mitmIdx, lessThan(modIdx));
      expect(modIdx, lessThan(origIdx));

      // proxy-groups untouched
      expect(result, contains('proxy-groups:'));
      expect(result, contains('- HK-01'));
    });
  });
}
