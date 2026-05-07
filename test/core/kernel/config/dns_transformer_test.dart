import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:yuelink/core/kernel/config/dns_policy_catalog.dart';
import 'package:yuelink/core/kernel/config/dns_transformer.dart';

/// Behaviour tests for [DnsTransformer.ensureDns]. The most important
/// case is the **subscription-already-has-everything** scenario — that's
/// where the v5 dedup bug lived (using `dnsSection.contains(domain)`
/// instead of `fakeIpFilterSubsection.contains(domain)`, causing
/// `geosite:cn` and AI domains to be silently dropped because they
/// appeared as `nameserver-policy` keys elsewhere in the same section).
void main() {
  group('DnsTransformer.ensureDns — fresh dns inject (no dns: in input)', () {
    const minimalConfig = '''
mixed-port: 7890
proxies: []
proxy-groups: []
rules: []
''';

    test('produces valid YAML', () {
      final out = DnsTransformer.ensureDns(minimalConfig);
      expect(() => loadYaml(out), returnsNormally);
    });

    test('writes geosite:cn into fake-ip-filter (P1-2b)', () {
      final out = DnsTransformer.ensureDns(minimalConfig);
      // The catalog `geositeCn` constant must end up as a list entry
      // under fake-ip-filter — check the exact YAML form.
      expect(out, contains('- "${DnsPolicyCatalog.geositeCn}"'));
    });

    test('writes direct-nameserver-follow-policy: true (P1-3)', () {
      final out = DnsTransformer.ensureDns(minimalConfig);
      expect(out, contains('direct-nameserver-follow-policy: true'));
    });

    test('writes every catalog AI domain into nameserver-policy (P1-1)', () {
      final out = DnsTransformer.ensureDns(minimalConfig);
      for (final ai in DnsPolicyCatalog.aiDomains) {
        expect(
          out.contains('"$ai":'),
          isTrue,
          reason: 'AI domain $ai missing from nameserver-policy',
        );
      }
    });

    test('writes every catalog CN-critical domain into fake-ip-filter (P1-4)',
        () {
      final out = DnsTransformer.ensureDns(minimalConfig);
      for (final cn in DnsPolicyCatalog.chinaCriticalDomains) {
        expect(
          out.contains('- "$cn"'),
          isTrue,
          reason: 'CN-critical domain $cn missing from fake-ip-filter',
        );
      }
    });

    test('idempotent: running twice equals running once', () {
      final once = DnsTransformer.ensureDns(minimalConfig);
      final twice = DnsTransformer.ensureDns(once);
      expect(twice, equals(once));
    });
  });

  group('DnsTransformer.ensureDns — augment existing dns section', () {
    /// **Critical fixture for P1-2a regression test.**
    ///
    /// This subscription already has `nameserver-policy` containing
    /// `geosite:cn` AS A KEY (routing CN domains to CN DoH). Pre-fix,
    /// the dedup logic was `dnsSection.contains('geosite:cn')` and would
    /// silently skip the fake-ip-filter inject because the substring
    /// matched the policy key. Post-fix, dedup is scoped to the
    /// fake-ip-filter subsection only.
    ///
    /// `+.openai.com` is set up the same way to catch the AI-domain
    /// variant of the same bug.
    const subscriptionWithPolicyKeys = '''
mixed-port: 7890
proxies: []
rules: []
dns:
  enable: true
  enhanced-mode: fake-ip
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - +.push.apple.com
  nameserver:
    - 223.5.5.5
  nameserver-policy:
    geosite:cn:
      - 223.5.5.5
    geosite:private:
      - 223.5.5.5
    +.openai.com:
      - https://cloudflare-dns.com/dns-query
''';

    test('P1-2a regression: geosite:cn enters fake-ip-filter despite '
        'nameserver-policy already having geosite:cn key', () {
      final out = DnsTransformer.ensureDns(subscriptionWithPolicyKeys);

      // YAML still valid
      expect(() => loadYaml(out), returnsNormally);

      // Find the fake-ip-filter subsection and confirm geosite:cn is
      // listed there (NOT just present somewhere in the dns section).
      final filterMatch =
          RegExp(r'fake-ip-filter:\s*\n').firstMatch(out)!.end;
      final tail = out.substring(filterMatch);
      final filterEnd =
          RegExp(r'^(?![ \t]+- )', multiLine: true).firstMatch(tail);
      final filterBody = filterEnd != null
          ? tail.substring(0, filterEnd.start)
          : tail;

      expect(
        filterBody,
        anyOf(
          contains('- geosite:cn'),
          contains('- "geosite:cn"'),
          contains("- 'geosite:cn'"),
        ),
        reason: 'P1-2a regression — fake-ip-filter must contain geosite:cn '
            'even when nameserver-policy already has geosite:cn key',
      );
    });

    test('idempotent on a config that already went through ensureDns', () {
      final once = DnsTransformer.ensureDns(subscriptionWithPolicyKeys);
      final twice = DnsTransformer.ensureDns(once);
      expect(twice, equals(once));
    });

    test('does not duplicate existing fake-ip-filter entries', () {
      final out = DnsTransformer.ensureDns(subscriptionWithPolicyKeys);
      // `+.push.apple.com` was in the input — should appear exactly once.
      final occurrences = '+.push.apple.com'.allMatches(out).length;
      expect(
        occurrences,
        1,
        reason: '+.push.apple.com should not be duplicated',
      );
    });

    test('respects existing direct-nameserver-follow-policy: false', () {
      const withExplicitFalse = '''
dns:
  enable: true
  fake-ip-filter:
    - '*.lan'
  direct-nameserver-follow-policy: false
  nameserver:
    - 223.5.5.5
''';
      final out = DnsTransformer.ensureDns(withExplicitFalse);
      // Must NOT flip user's explicit choice.
      expect(out, contains('direct-nameserver-follow-policy: false'));
      expect(
        out.contains('direct-nameserver-follow-policy: true'),
        isFalse,
        reason:
            'subscription explicitly set false; transformer should not add '
            'a second `direct-nameserver-follow-policy: true` line',
      );
    });

    test('preserves block-style nameserver-policy and adds geolocation-!cn',
        () {
      const blockStylePolicy = '''
dns:
  enable: true
  fake-ip-filter:
    - '*.lan'
  nameserver-policy:
    +.example.org:
      - 1.1.1.1
''';
      final out = DnsTransformer.ensureDns(blockStylePolicy);
      expect(() => loadYaml(out), returnsNormally);
      // Original entry preserved
      expect(out, contains('+.example.org'));
      // Catch-all added
      expect(out, contains(DnsPolicyCatalog.geolocationNonCnKey));
    });

    test('preserves flow-style nameserver-policy and adds geolocation-!cn',
        () {
      const flowStylePolicy = '''
dns:
  enable: true
  fake-ip-filter:
    - '*.lan'
  nameserver-policy: { '+.example.org': [1.1.1.1] }
''';
      final out = DnsTransformer.ensureDns(flowStylePolicy);
      expect(() => loadYaml(out), returnsNormally);
      expect(out, contains('+.example.org'));
      expect(out, contains(DnsPolicyCatalog.geolocationNonCnKey));
    });
  });

  group('DnsTransformer.ensureDns — relay fake-ip-filter (subsection-scoped)',
      () {
    test('P1-2a regression: relay host equal to AI policy key still injects',
        () {
      const subscriptionWithAiPolicy = '''
dns:
  enable: true
  fake-ip-filter:
    - '*.lan'
  nameserver-policy:
    +.openai.com:
      - https://cloudflare-dns.com/dns-query
''';
      // Relay whitelist contains a host that ALSO appears as a
      // nameserver-policy key. Pre-fix the naive `contains('"+.openai.com"')`
      // would falsely match the policy key and skip the inject.
      final out = DnsTransformer.ensureDns(
        subscriptionWithAiPolicy,
        relayHostWhitelist: ['+.openai.com'],
      );

      final filterMatch =
          RegExp(r'fake-ip-filter:\s*\n').firstMatch(out)!.end;
      final tail = out.substring(filterMatch);
      final filterEnd =
          RegExp(r'^(?![ \t]+- )', multiLine: true).firstMatch(tail);
      final filterBody = filterEnd != null
          ? tail.substring(0, filterEnd.start)
          : tail;

      expect(filterBody, contains('+.openai.com'));
    });

    test('does not inject relay host when already in fake-ip-filter', () {
      const config = '''
dns:
  enable: true
  fake-ip-filter:
    - '*.lan'
    - "relay.example.com"
''';
      final out = DnsTransformer.ensureDns(
        config,
        relayHostWhitelist: ['relay.example.com'],
      );
      // Should appear exactly once.
      final occurrences = 'relay.example.com'.allMatches(out).length;
      expect(occurrences, 1);
    });
  });

  group('DnsTransformer.ensureDns — AI domain injection in existing dns:', () {
    test('subscription with no nameserver-policy gets full AI policy (P1-1)',
        () {
      const subscriptionWithoutPolicy = '''
dns:
  enable: true
  fake-ip-filter:
    - '*.lan'
  nameserver:
    - 223.5.5.5
''';
      final out = DnsTransformer.ensureDns(subscriptionWithoutPolicy);
      // Every catalog AI domain must end up as a policy key.
      for (final ai in DnsPolicyCatalog.aiDomains) {
        expect(
          DnsTransformer.debugHasPolicyKey(out, ai),
          isTrue,
          reason: 'AI domain $ai should be a nameserver-policy key when '
              'subscription had no policy at all',
        );
      }
    });

    test('subscription with partial nameserver-policy gets missing AI '
        'domains injected (P1-1, block-style)', () {
      const partialPolicy = '''
dns:
  enable: true
  fake-ip-filter:
    - '*.lan'
  nameserver-policy:
    "geosite:cn":
      - 223.5.5.5
    "+.openai.com":
      - https://cloudflare-dns.com/dns-query
''';
      final out = DnsTransformer.ensureDns(partialPolicy);

      // Existing key preserved (single occurrence — no duplicate inject)
      final policyKey = RegExp(r'^[ \t]*"\+\.openai\.com"\s*:', multiLine: true);
      final hits = policyKey.allMatches(out).length;
      expect(hits, 1, reason: '+.openai.com appeared once before; should stay 1');

      // Missing AI domains now injected — pick a few to verify
      for (final ai in const ['+.anthropic.com', '+.cursor.com', '+.x.ai']) {
        expect(
          DnsTransformer.debugHasPolicyKey(out, ai),
          isTrue,
          reason: 'missing AI domain $ai should have been injected',
        );
      }

      expect(() => loadYaml(out), returnsNormally);
    });

    test('flow-style nameserver-policy gets missing AI domains spliced in',
        () {
      const flowStylePolicy = '''
dns:
  enable: true
  fake-ip-filter:
    - '*.lan'
  nameserver-policy: { '+.openai.com': ['https://cloudflare-dns.com/dns-query'] }
''';
      final out = DnsTransformer.ensureDns(flowStylePolicy);
      expect(() => loadYaml(out), returnsNormally);
      // openai.com still there (1 occurrence as policy key)
      expect(
        DnsTransformer.debugHasPolicyKey(out, '+.openai.com'),
        isTrue,
      );
      // A new AI domain that wasn't in the original flow map is now present
      expect(out, contains('+.anthropic.com'));
    });

    test('idempotent across all three policy paths', () {
      const fixtures = [
        // (a) no policy
        '''
dns:
  enable: true
  fake-ip-filter: [ '*.lan' ]
  nameserver: [ 223.5.5.5 ]
''',
        // (b) policy exists, no catch-all, missing some AI
        '''
dns:
  enable: true
  fake-ip-filter: [ '*.lan' ]
  nameserver-policy:
    "geosite:cn":
      - 223.5.5.5
''',
        // (c) policy exists with catch-all + many AI domains
        '''
dns:
  enable: true
  fake-ip-filter: [ '*.lan' ]
  nameserver-policy:
    "geosite:geolocation-!cn":
      - https://cloudflare-dns.com/dns-query
    "+.openai.com":
      - https://cloudflare-dns.com/dns-query
''',
      ];
      for (final fix in fixtures) {
        final once = DnsTransformer.ensureDns(fix);
        final twice = DnsTransformer.ensureDns(once);
        expect(
          twice,
          equals(once),
          reason: 'idempotency broken on fixture starting with: '
              '${fix.split('\n').take(3).join(' / ')}',
        );
      }
    });
  });

  group('DnsTransformer + assets/default_config.yaml (no-drift guard)', () {
    /// Stronger than `once == twice`: also assert that the **first** pass
    /// produces a fake-ip-filter list with no duplicate entries. The
    /// previous version of `_findFakeIpFilterSubrange` truncated at the
    /// first comment line in default_config, causing geosite:cn /
    /// CN-critical entries on the far side of the comment to be re-
    /// injected as duplicates while `once == twice` still held (because
    /// the comment also truncated the second pass identically).
    test('default_config.yaml — fake-ip-filter has no duplicates after '
        'ensureDns (P1-2a regression for comment dividers)', () async {
      final file =
          File('${Directory.current.path}/assets/default_config.yaml');
      if (!file.existsSync()) return;
      final raw = file.readAsStringSync();

      final once = DnsTransformer.ensureDns(raw);

      // Parse with mihomo-tolerant YAML loader and walk fake-ip-filter.
      final yaml = loadYaml(once) as YamlMap;
      final dns = yaml['dns'] as YamlMap;
      final filterRaw = dns['fake-ip-filter'] as YamlList;
      final filter =
          filterRaw.map((e) => e.toString()).toList(growable: false);

      final counts = <String, int>{};
      for (final d in filter) {
        counts[d] = (counts[d] ?? 0) + 1;
      }
      final dups = Map.fromEntries(
        counts.entries.where((e) => e.value > 1),
      );
      expect(
        dups,
        isEmpty,
        reason: 'fake-ip-filter has duplicate entries after ensureDns: '
            '$dups\n'
            'Likely cause: subsection regex truncates at comment / blank '
            'line, marking later catalog entries as "missing", causing '
            're-inject. See P1-2a regression notes in '
            'governance/client-comparison-deep-dive-2026-05-07.md',
      );
    });

    test('default_config.yaml — nameserver-policy has no duplicate AI keys '
        '(P1-1 regression for existing-policy path)', () async {
      final file =
          File('${Directory.current.path}/assets/default_config.yaml');
      if (!file.existsSync()) return;
      final raw = file.readAsStringSync();
      final once = DnsTransformer.ensureDns(raw);

      // For each catalog AI domain, count occurrences as policy keys
      // in the output. Expectation: exactly 1 each.
      for (final ai in DnsPolicyCatalog.aiDomains) {
        final keyPattern = RegExp(
          // ignore: prefer_adjacent_string_concatenation
          r'''^[ \t]*["']?''' + RegExp.escape(ai) + r'''["']?\s*:''',
          multiLine: true,
        );
        final hits = keyPattern.allMatches(once).length;
        expect(
          hits,
          1,
          reason: 'AI domain $ai should appear exactly once as a '
              'nameserver-policy key, found $hits times',
        );
      }
    });

    test('default_config.yaml is idempotent under ensureDns '
        '(no transformer/asset drift)', () async {
      final file =
          File('${Directory.current.path}/assets/default_config.yaml');
      if (!file.existsSync()) return;
      final raw = file.readAsStringSync();
      expect(() => loadYaml(raw), returnsNormally);
      final once = DnsTransformer.ensureDns(raw);
      final twice = DnsTransformer.ensureDns(once);
      expect(
        twice,
        equals(once),
        reason: 'default_config.yaml must be idempotent under ensureDns. '
            'If this fails, the catalog and the asset have drifted — '
            'sync them per governance/client-comparison-deep-dive-2026-05-07.md',
      );
    });
  });
}
