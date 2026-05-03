import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/kernel/config_template.dart';

/// Golden-file regression lock for `ConfigTemplate.process()`.
///
/// **What this guards.** The S4 split of `config_template.dart` into a
/// shared `YamlIndentDetector` + per-step transformer files must produce
/// **byte-identical** output for every fixture below. Any diff here is
/// either a bug introduced by the split or a deliberate semantic change
/// that needs its own audit (and a separate commit, mirroring the X1/X2
/// split that landed before S4).
///
/// **Platform stability.** Every fixture pre-populates
/// `find-process-mode: off` and runs with `connectionMode: 'systemProxy'`
/// so the platform-dependent branches inside `process()` produce no output
/// delta on macOS / Linux / Windows / Android / iOS hosts:
///   - L231 desktop-tun branch — entered on desktop hosts but routes to
///     `_disableTun`, which is a no-op because none of the fixtures
///     contain a `tun:` section
///   - L1360/1381/1382 in `_ensureFindProcessMode` — short-circuited by
///     the pre-populated `find-process-mode: off` key (mobile would
///     overwrite a non-`off` value, so the explicit `off` is what makes
///     the output identical across mobile and desktop)
///   - L569/580 in `_ensureDesktopTun` — never reached, since
///     connectionMode is `systemProxy`
/// As a result the captured `.golden` files are valid on every host.
///
/// **Regeneration.** When a deliberate behavioural change makes a
/// regeneration appropriate, run:
///   ```
///   REGEN_GOLDEN=1 flutter test test/services/config_template_golden_test.dart
///   ```
/// inspect the resulting `*.golden` files in the diff, and commit them
/// alongside the code change in the same commit so the lock follows the
/// new contract.
void main() {
  final shouldRegenerate = Platform.environment['REGEN_GOLDEN'] == '1';
  final goldenDir = Directory('test/services/config_template_goldens');

  group('ConfigTemplate.process golden lock', () {
    setUpAll(() {
      if (shouldRegenerate && !goldenDir.existsSync()) {
        goldenDir.createSync(recursive: true);
      }
    });

    void runGolden(String name, String input) {
      final actual = ConfigTemplate.process(input);
      final goldenFile = File('${goldenDir.path}/$name.golden');
      if (shouldRegenerate) {
        goldenFile.writeAsStringSync(actual);
        return;
      }
      expect(
        goldenFile.existsSync(),
        isTrue,
        reason:
            'missing golden $name.golden — run with REGEN_GOLDEN=1 to seed',
      );
      final expected = goldenFile.readAsStringSync();
      expect(
        actual,
        expected,
        reason:
            'process() output drifted from golden $name.golden. If the '
            'change is intentional, run `REGEN_GOLDEN=1 flutter test '
            '${'test/services/config_template_golden_test.dart'}` and '
            'commit the regenerated golden in the same change.',
      );
    }

    test(
      shouldRegenerate
          ? 'regenerate full_subscription.golden'
          : 'full subscription golden',
      () => runGolden('full_subscription', _fixtureFullSubscription),
    );

    test(
      shouldRegenerate
          ? 'regenerate minimal_missing_dns_rules.golden'
          : 'minimal config (missing DNS / sniffer / geodata) golden',
      () => runGolden(
        'minimal_missing_dns_rules',
        _fixtureMinimalMissingSections,
      ),
    );

    test(
      shouldRegenerate
          ? 'regenerate block_style_rule_providers.golden'
          : 'block-style rule-providers golden',
      () => runGolden(
        'block_style_rule_providers',
        _fixtureBlockStyleRuleProviders,
      ),
    );
  });
}

// ── Fixtures ────────────────────────────────────────────────────────────────

/// Realistic subscription with most sections already present. Locks the
/// "ensure pattern" no-op behaviour: process() must NOT overwrite a
/// subscription's existing dns / sniffer / proxies / etc.
const _fixtureFullSubscription = '''
mixed-port: 7890
allow-lan: true
log-level: warning
find-process-mode: off
external-controller: 127.0.0.1:9090
geodata-mode: true
geodata-loader: memconservative

dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fake-ip-filter:
    - '*.lan'

sniffer:
  enable: true
  sniff:
    HTTP:
      ports: [80, 8080-8880]
    TLS:
      ports: [443, 8443]

proxies:
  - {name: node-hk, type: ss, server: 1.2.3.4, port: 443, cipher: aes-256-gcm, password: pwd-hk}
  - {name: node-jp, type: trojan, server: 5.6.7.8, port: 443, password: pwd-jp}

proxy-groups:
  - name: PROXY
    type: select
    proxies: [node-hk, node-jp]
  - name: AUTO
    type: url-test
    proxies: [node-hk, node-jp]
    url: 'http://www.gstatic.com/generate_204'
    interval: 300

rules:
  - DOMAIN-SUFFIX,google.com,PROXY
  - DOMAIN-SUFFIX,github.com,PROXY
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
''';

/// Minimal config — process() must inject DNS, sniffer, geodata,
/// performance, allow-lan, ipv6, mode, etc. Locks the "fresh defaults"
/// shape across every _ensureX path that adds rather than mutates.
const _fixtureMinimalMissingSections = '''
mixed-port: 7890
find-process-mode: off

proxies:
  - {name: n1, type: ss, server: 1.2.3.4, port: 443, cipher: aes-256-gcm, password: pwd}

proxy-groups:
  - name: PROXY
    type: select
    proxies: [n1]

rules:
  - MATCH,PROXY
''';

/// Block-style `rule-providers:` (mapping form, not inline flow form).
/// Locks the indent-detection paths that S4 will centralise into
/// `YamlIndentDetector` — any regression in sibling-key insertion or
/// section-range detection will surface as a byte diff here.
const _fixtureBlockStyleRuleProviders = '''
mixed-port: 7890
find-process-mode: off

rule-providers:
  google:
    type: http
    behavior: classical
    url: https://example.com/google.txt
    path: ./ruleset/google.txt
    interval: 86400
  github:
    type: http
    behavior: classical
    url: https://example.com/github.txt
    path: ./ruleset/github.txt
    interval: 86400

proxies:
  - {name: n1, type: ss, server: 1.2.3.4, port: 443, cipher: aes-256-gcm, password: pwd}

proxy-groups:
  - name: PROXY
    type: select
    proxies: [n1]

rules:
  - RULE-SET,google,PROXY
  - RULE-SET,github,PROXY
  - MATCH,PROXY
''';
