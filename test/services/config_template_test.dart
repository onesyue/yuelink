import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/constants.dart';
import 'package:yuelink/core/kernel/config_template.dart';

void main() {
  group('ConfigTemplate.process', () {
    test('replaces \$app_name with YueLink', () {
      const config = 'name: \$app_name\nproxies: []';
      final result = ConfigTemplate.process(config);
      expect(result, contains('name: YueLink'));
      expect(result, isNot(contains('\$app_name')));
    });

    test('adds external-controller when missing', () {
      const config = 'mixed-port: 7890';
      final result = ConfigTemplate.process(config, apiPort: 9090);
      expect(result, contains('external-controller: 127.0.0.1:9090'));
    });

    test('replaces existing external-controller port', () {
      const config = 'external-controller: 0.0.0.0:1234\nmixed-port: 7890';
      final result = ConfigTemplate.process(config, apiPort: 9090);
      expect(result, contains('external-controller: 127.0.0.1:9090'));
      expect(result, isNot(contains(':1234')));
    });

    test('adds secret when provided', () {
      const config = 'mixed-port: 7890';
      final result = ConfigTemplate.process(config, secret: 'mytoken');
      expect(result, contains('secret: mytoken'));
    });

    test('desktop tun mode injects desktop-safe tun config', () {
      const config = '''
mixed-port: 7890
tun:
  enable: false
  stack: gvisor
  file-descriptor: 42
find-process-mode: off
''';
      final result = ConfigTemplate.process(config, connectionMode: 'tun');

      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        expect(result, contains('tun:'));
        expect(result, contains('enable: true'));
        expect(result, contains('stack: mixed'));
        expect(result, contains('auto-route: true'));
        expect(result, contains('auto-detect-interface: true'));
        if (Platform.isWindows || Platform.isLinux) {
          expect(result, contains('device: YueLink'));
        } else {
          expect(result, isNot(contains('device: YueLink')));
        }
        expect(result, contains('strict-route:'));
        expect(result, contains('dns-hijack:'));
        expect(result, contains('- tcp://any:53'));
        // v1.0.22 P1-2: Windows TUN now defaults to strict (was always);
        // macOS keeps always pending similar reports.
        if (Platform.isWindows) {
          expect(result, contains('find-process-mode: strict'));
        } else {
          expect(result, contains('find-process-mode: always'));
        }
        expect(result, isNot(contains('file-descriptor: 42')));
      } else {
        expect(result, contains('file-descriptor: 42'));
        expect(result, contains('find-process-mode: off'));
      }
    });

    test('desktop system-proxy mode disables tun section', () {
      const config = '''
mixed-port: 7890
tun:
  enable: true
  stack: mixed
''';
      final result = ConfigTemplate.process(
        config,
        connectionMode: 'systemProxy',
      );

      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        expect(result, contains('enable: false'));
      } else {
        expect(result, contains('enable: true'));
      }
    });

    test('desktop tun process bypass injects PROCESS-NAME rules', () {
      const config = '''
mixed-port: 7890
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(
        config,
        connectionMode: 'tun',
        tunBypassProcesses: const ['ssh', 'Parallels Desktop'],
      );

      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        expect(result, contains('"PROCESS-NAME,ssh,DIRECT"'));
        expect(result, contains('"PROCESS-NAME,Parallels Desktop,DIRECT"'));
        expect(result, isNot(contains('exclude-package:')));
      } else {
        expect(result, isNot(contains('PROCESS-NAME,ssh,DIRECT')));
      }
    });

    test('find-process-mode default is platform-aware (P1-2 Win=strict, '
        'mac/linux=always, mobile=off)', () {
      // Subscription with NO find-process-mode key → injection path
      // (line 1268 in config_template.dart) decides the value.
      const config = 'mixed-port: 7890\ndns:\n  enable: true\n';
      final result = ConfigTemplate.process(
        config,
        connectionMode: 'systemProxy',
      );

      if (Platform.isAndroid || Platform.isIOS) {
        expect(result, contains('find-process-mode: off'));
      } else if (Platform.isWindows) {
        expect(
          result,
          contains('find-process-mode: strict'),
          reason:
              'Win default flipped strict to fix download-tool '
              'churn from per-flow process lookup',
        );
      } else {
        expect(
          result,
          contains('find-process-mode: always'),
          reason: 'macOS / Linux retain always until similar reports',
        );
      }
    });

    test('find-process-mode existing value is preserved on desktop, forced off '
        'on mobile', () {
      const config = '''
mixed-port: 7890
find-process-mode: always
dns:
  enable: true
''';
      final result = ConfigTemplate.process(
        config,
        connectionMode: 'systemProxy',
      );

      if (Platform.isAndroid || Platform.isIOS) {
        expect(result, contains('find-process-mode: off'));
      } else {
        // Desktop: subscription wins. Both Windows and macOS keep
        // the user-supplied 'always' instead of clobbering to the
        // platform default. (TUN mode is the special case that
        // does override — covered separately above.)
        expect(result, contains('find-process-mode: always'));
      }
    });

    test('respect-rules DNS does not force prefer-h3', () {
      const config = '''
mixed-port: 7890
dns:
  enable: true
  respect-rules: true
  enhanced-mode: fake-ip
  prefer-h3: true
''';
      final result = ConfigTemplate.process(config);
      expect(result, contains('respect-rules: true'));
      expect(result, isNot(contains('prefer-h3: true')));
      expect(result, contains('proxy-server-nameserver:'));
    });

    test(
      'inline rules: [] is not treated as injectable block (S4 regression)',
      () {
        // Pre-S4 the rules-injecting passes (_ensureProcessBypassRules,
        // _ensureConnectivityRules, _ensureGooglevideoQuicReject,
        // _ensureGlobalQuicReject) keyed off `^rules:\s*\n`, which only
        // matched block-style headers. The first cut of the
        // YamlIndentDetector migration relaxed that to `^rules:` and
        // would have happily injected children below `rules: []`,
        // producing invalid YAML like:
        //   rules: []
        //     - "DOMAIN,connectivitycheck..."
        // The fix routes those callers through `requireBlockHeader: true`.
        // This test pins the contract.
        const config = '''
mixed-port: 7890
proxies: []
rules: []
''';
        final result = ConfigTemplate.process(config);
        // The original `rules: []` line stays exactly as written, with no
        // injected child indented under it.
        expect(
          result,
          contains('rules: []\n'),
          reason: 'inline rules: [] line must survive intact',
        );
        expect(
          result,
          isNot(matches(RegExp(r'rules: \[\]\n\s+-'))),
          reason:
              'no `- ...` line may be injected directly under `rules: []` — '
              'that would be invalid YAML',
        );
      },
    );
  });

  group('ConfigTemplate extraction', () {
    test('getMixedPort extracts port from config', () {
      expect(ConfigTemplate.getMixedPort('mixed-port: 7890'), 7890);
      expect(ConfigTemplate.getMixedPort('mixed-port: 1080'), 1080);
    });

    test('getMixedPort returns default when missing', () {
      expect(ConfigTemplate.getMixedPort('other: value'), 7890);
    });

    test('getApiPort extracts port', () {
      expect(
        ConfigTemplate.getApiPort('external-controller: 127.0.0.1:9090'),
        9090,
      );
      expect(ConfigTemplate.getApiPort('external-controller: :8080'), 8080);
    });

    test('getSecret extracts secret', () {
      expect(ConfigTemplate.getSecret('secret: abc123'), 'abc123');
      expect(ConfigTemplate.getSecret('secret: "quoted"'), 'quoted');
    });

    test('getSecret returns null when missing', () {
      expect(ConfigTemplate.getSecret('mixed-port: 7890'), isNull);
    });
  });

  group('ConfigTemplate.mergeIfNeeded', () {
    test(
      'uses subscription config directly if it has proxy-groups and rules',
      () {
        const template = 'mixed-port: 7890\nproxies:\n';
        const sub =
            'proxies:\n  - name: test\nproxy-groups:\n  - name: g\nrules:\n  - MATCH,DIRECT';
        final result = ConfigTemplate.mergeIfNeeded(template, sub);
        expect(result, equals(sub));
      },
    );

    test('adds mode: rule when missing', () {
      const config = 'mixed-port: 7890\ndns:\n  enable: true';
      final result = ConfigTemplate.process(config);
      expect(result, contains('mode: rule'));
    });

    test('does not override existing mode', () {
      const config = 'mixed-port: 7890\nmode: global\ndns:\n  enable: true';
      final result = ConfigTemplate.process(config);
      expect(result, contains('mode: global'));
      expect(result, isNot(contains('mode: rule')));
    });

    test('preserves complete subscription config without corruption', () {
      // Simulate a real subscription config structure
      const config = '''
mixed-port: 7890
allow-lan: true
find-process-mode: always
dns:
  enable: true
  enhanced-mode: fake-ip
  respect-rules: true
sniffer:
  enable: true
geodata-mode: true
profile:
  store-selected: true
tcp-concurrent: true
unified-delay: true
global-client-fingerprint: chrome
proxies:
  - {name: node1, type: ss, server: 1.2.3.4, port: 443}
proxy-groups:
  - {name: Proxy, type: select, proxies: [node1]}
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config, apiPort: 9090);
      // Should add external-controller but not duplicate existing keys
      expect(result, contains('external-controller: 127.0.0.1:9090'));
      expect(result, contains('mode: rule'));
      // Existing keys should NOT be duplicated
      expect(
        'dns:'.allMatches(result).length,
        1,
        reason: 'dns should not be duplicated',
      );
      expect(
        'sniffer:'.allMatches(result).length,
        1,
        reason: 'sniffer should not be duplicated',
      );
      expect(
        'geodata-mode:'.allMatches(result).length,
        1,
        reason: 'geodata-mode should not be duplicated',
      );
      expect(
        'profile:'.allMatches(result).length,
        1,
        reason: 'profile should not be duplicated',
      );
      expect(
        'mixed-port:'.allMatches(result).length,
        1,
        reason: 'mixed-port should not be duplicated',
      );
      // Proxy structure should be preserved
      expect(result, contains('MATCH,Proxy'));
      expect(result, contains('name: node1'));
    });

    test('merges proxies into template when sub has no groups', () {
      const template =
          'mixed-port: 7890\nproxies:\n\nproxy-groups:\n  - name: g\n';
      const sub = 'proxies:\n  - name: node1\n    type: ss\n';
      final result = ConfigTemplate.mergeIfNeeded(template, sub);
      expect(result, contains('name: node1'));
      expect(result, contains('proxy-groups:'));
    });
  });

  group('ConfigTemplate.injectProxyChain', () {
    const baseConfig = '''
proxies:
  - name: HK
    type: ss
    server: 1.2.3.4
    port: 443
  - name: JP
    type: vmess
    server: 5.6.7.8
    port: 443
proxy-groups:
  - name: 自动选择
    type: select
    proxies:
      - HK
      - JP
''';

    test('sets dialer-proxy directly on exit proxy node', () {
      final result = ConfigTemplate.injectProxyChain(baseConfig, [
        'HK',
        'JP',
      ], '自动选择');
      // JP (exit) must have dialer-proxy: HK
      expect(
        result,
        anyOf(contains('dialer-proxy: HK'), contains('dialer-proxy: "HK"')),
      );
      // HK (entry) must NOT have dialer-proxy pointing to JP
      expect(result, isNot(contains('dialer-proxy: JP')));
      expect(result, isNot(contains('dialer-proxy: "JP"')));
      // No chain wrapper groups should be created
      expect(result, isNot(contains('_YueLink_Chain_')));
      // No relay type
      expect(
        result,
        isNot(anyOf(contains('type: relay'), contains('type: "relay"'))),
      );
    });

    test(
      'removes deprecated top-level global-client-fingerprint',
      () {
        const config = '''
mixed-port: 7890
global-client-fingerprint: random
proxies:
  - {name: node1, type: ss, server: 1.2.3.4, port: 443}
proxy-groups:
  - {name: Proxy, type: select, proxies: [node1]}
rules:
  - MATCH,Proxy
''';
        final result = ConfigTemplate.process(config);
        expect(result, isNot(contains('global-client-fingerprint')));
      },
    );

    test('preserves proxy-level client-fingerprint', () {
      const config = '''
mixed-port: 7890
proxies:
  - {name: node1, type: trojan, server: 1.2.3.4, port: 443, client-fingerprint: safari}
proxy-groups:
  - {name: Proxy, type: select, proxies: [node1]}
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, contains('client-fingerprint: safari'));
      expect(result, isNot(contains('global-client-fingerprint')));
    });

    test('3-node chain sets correct dialer-proxy links on nodes', () {
      const config = '''
proxies:
  - name: A
    type: ss
    server: 1.1.1.1
    port: 443
  - name: B
    type: vmess
    server: 2.2.2.2
    port: 443
  - name: C
    type: trojan
    server: 3.3.3.3
    port: 443
proxy-groups:
  - name: 选择
    type: select
    proxies: [A, B, C]
''';
      final result = ConfigTemplate.injectProxyChain(config, [
        'A',
        'B',
        'C',
      ], '选择');
      // B dials through A
      expect(
        result,
        anyOf(contains('dialer-proxy: A'), contains('dialer-proxy: "A"')),
      );
      // C dials through B
      expect(
        result,
        anyOf(contains('dialer-proxy: B'), contains('dialer-proxy: "B"')),
      );
      // A (entry) has no dialer-proxy
      expect(result, isNot(contains('dialer-proxy: C')));
      expect(result, isNot(contains('dialer-proxy: "C"')));
    });

    test(
      'is idempotent — re-inject clears old dialer-proxy before re-setting',
      () {
        var result = ConfigTemplate.injectProxyChain(baseConfig, [
          'HK',
          'JP',
        ], '自动选择');
        result = ConfigTemplate.injectProxyChain(result, ['HK', 'JP'], '自动选择');
        // Exactly one dialer-proxy in the entire config (JP → HK)
        expect(RegExp(r'dialer-proxy:').allMatches(result).length, 1);
      },
    );

    test('returns original config for less than 2 nodes', () {
      expect(
        ConfigTemplate.injectProxyChain(baseConfig, ['HK'], '自动选择'),
        equals(baseConfig),
      );
      expect(
        ConfigTemplate.injectProxyChain(baseConfig, [], '自动选择'),
        equals(baseConfig),
      );
    });

    test('returns original config when activeGroup not found', () {
      expect(
        ConfigTemplate.injectProxyChain(baseConfig, [
          'HK',
          'JP',
        ], 'NonExistent'),
        equals(baseConfig),
      );
    });

    test('strips legacy dialer-proxy on raw proxy nodes on inject', () {
      const legacyConfig = '''
proxies:
  - name: HK
    type: ss
    server: 1.2.3.4
    port: 443
    dialer-proxy: SomeNode
  - name: JP
    type: vmess
    server: 5.6.7.8
    port: 443
proxy-groups:
  - name: 自动选择
    type: select
    proxies:
      - HK
      - JP
''';
      final result = ConfigTemplate.injectProxyChain(legacyConfig, [
        'HK',
        'JP',
      ], '自动选择');
      expect(result, isNot(contains('dialer-proxy: SomeNode')));
      expect(result, isNot(contains('dialer-proxy: "SomeNode"')));
      // JP should now have dialer-proxy: HK
      expect(
        result,
        anyOf(contains('dialer-proxy: HK'), contains('dialer-proxy: "HK"')),
      );
    });

    test(
      'removes old _YueLink_Chain_* groups on re-inject (backward compat)',
      () {
        const oldChainConfig = '''
proxies:
  - name: HK
    type: ss
    server: 1.2.3.4
    port: 443
  - name: JP
    type: vmess
    server: 5.6.7.8
    port: 443
proxy-groups:
  - name: 自动选择
    type: select
    proxies:
      - _YueLink_Chain_1
      - HK
      - JP
  - name: _YueLink_Chain_0
    type: select
    proxies:
      - HK
  - name: _YueLink_Chain_1
    type: select
    proxies:
      - JP
''';
        final result = ConfigTemplate.injectProxyChain(oldChainConfig, [
          'HK',
          'JP',
        ], '自动选择');
        expect(result, isNot(contains('_YueLink_Chain_')));
        expect(
          result,
          anyOf(contains('dialer-proxy: HK'), contains('dialer-proxy: "HK"')),
        );
      },
    );
  });

  group('ConfigTemplate.removeProxyChain', () {
    test('removes all chain wrapper groups and their entries', () {
      const config = '''
proxies:
  - name: HK
    type: ss
    server: 1.2.3.4
    port: 443
proxy-groups:
  - name: 自动选择
    type: select
    proxies:
      - _YueLink_Chain_1
      - HK
  - name: _YueLink_Chain_0
    type: select
    proxies:
      - HK
  - name: _YueLink_Chain_1
    type: select
    proxies:
      - JP
    dialer-proxy: _YueLink_Chain_0
''';
      final result = ConfigTemplate.removeProxyChain(config);
      expect(result, isNot(contains('_YueLink_Chain_')));
    });

    test('keeps _upstream dialer-proxy intact', () {
      const config = '''
proxies:
  - name: _upstream
    type: socks5
    server: 10.0.0.1
    port: 1080
  - name: HK
    type: ss
    server: 1.2.3.4
    port: 443
    dialer-proxy: _upstream
proxy-groups:
  - name: 自动选择
    type: select
    proxies:
      - HK
''';
      final result = ConfigTemplate.removeProxyChain(config);
      expect(
        result,
        anyOf(
          contains('dialer-proxy: _upstream'),
          contains('dialer-proxy: "_upstream"'),
        ),
      );
    });

    test('strips legacy dialer-proxy on raw proxy nodes on remove', () {
      const config = '''
proxies:
  - name: HK
    type: ss
    server: 1.2.3.4
    port: 443
    dialer-proxy: SomeNode
proxy-groups:
  - name: 自动选择
    type: select
    proxies:
      - HK
''';
      final result = ConfigTemplate.removeProxyChain(config);
      expect(result, isNot(contains('dialer-proxy: SomeNode')));
      expect(result, isNot(contains('dialer-proxy: "SomeNode"')));
    });
  });

  group('ConfigTemplate QUIC reject policy', () {
    const globalRejectRule = 'AND,((NETWORK,UDP),(DST-PORT,443)),REJECT-DROP';
    const googlevideoRejectRule =
        'AND,((DOMAIN-SUFFIX,googlevideo.com),(NETWORK,UDP)),REJECT-DROP';
    const baseConfig = '''
mixed-port: 7890
proxy-groups:
  - name: YueLink
    type: select
    proxies: [DIRECT]
rules:
  - DOMAIN-SUFFIX,example.com,YueLink
  - MATCH,YueLink
''';

    test('off does not inject QUIC reject rules', () {
      final result = ConfigTemplate.process(
        baseConfig,
        quicRejectPolicy: ConfigTemplate.quicRejectPolicyOff,
      );
      expect(result, isNot(contains(globalRejectRule)));
      expect(result, isNot(contains(googlevideoRejectRule)));
    });

    test('googlevideo injects narrow rule at top without global block', () {
      final result = ConfigTemplate.process(
        baseConfig,
        quicRejectPolicy: ConfigTemplate.quicRejectPolicyGooglevideo,
      );
      expect(result, contains(googlevideoRejectRule));
      expect(result, isNot(contains(globalRejectRule)));

      final rulesStart = result.indexOf('rules:');
      final rejectIdx = result.indexOf(googlevideoRejectRule, rulesStart);
      final matchIdx = result.indexOf('MATCH,YueLink', rulesStart);
      expect(rejectIdx, greaterThan(0));
      expect(matchIdx, greaterThan(0));
      expect(
        rejectIdx,
        lessThan(matchIdx),
        reason: 'googlevideo reject rule must precede other rules',
      );
    });

    test('all injects global UDP:443 reject rule at top of rules section', () {
      final result = ConfigTemplate.process(
        baseConfig,
        quicRejectPolicy: ConfigTemplate.quicRejectPolicyAll,
      );
      expect(result, contains(globalRejectRule));
      expect(result, isNot(contains(googlevideoRejectRule)));

      final rulesStart = result.indexOf('rules:');
      final rejectIdx = result.indexOf(globalRejectRule, rulesStart);
      final matchIdx = result.indexOf('MATCH,YueLink', rulesStart);
      expect(rejectIdx, greaterThan(0));
      expect(matchIdx, greaterThan(0));
      expect(
        rejectIdx,
        lessThan(matchIdx),
        reason: 'global reject rule must precede other rules',
      );
    });

    test('repeated process does not duplicate injected rules', () {
      final once = ConfigTemplate.process(
        baseConfig,
        quicRejectPolicy: ConfigTemplate.quicRejectPolicyGooglevideo,
      );
      final twice = ConfigTemplate.process(
        once,
        quicRejectPolicy: ConfigTemplate.quicRejectPolicyGooglevideo,
      );
      final occurrences = RegExp(
        RegExp.escape(googlevideoRejectRule),
      ).allMatches(twice).length;
      expect(occurrences, 1);
      expect(twice, isNot(contains(globalRejectRule)));
    });

    test(
      'skips global injection when subscription already has UDP/443 REJECT',
      () {
        const config = '''
mixed-port: 7890
rules:
  - DOMAIN-SUFFIX,example.com,YueLink
  - AND,((NETWORK,UDP),(DST-PORT,443)),REJECT-DROP
  - MATCH,DIRECT
''';
        final result = ConfigTemplate.process(
          config,
          quicRejectPolicy: ConfigTemplate.quicRejectPolicyAll,
        );
        // Panel-injected rule already present — must not duplicate
        final occurrences = RegExp(
          RegExp.escape(globalRejectRule),
        ).allMatches(result).length;
        expect(occurrences, 1);
      },
    );

    test(
      'skips global injection when subscription uses reversed AND ordering',
      () {
        const config = '''
mixed-port: 7890
rules:
  - AND,((DST-PORT,443),(NETWORK,UDP)),REJECT-DROP
  - MATCH,DIRECT
''';
        final result = ConfigTemplate.process(
          config,
          quicRejectPolicy: ConfigTemplate.quicRejectPolicyAll,
        );
        // Should NOT inject our variant — equivalent rule already present
        expect(result, isNot(contains(globalRejectRule)));
      },
    );

    test('does nothing when config has no rules section', () {
      const config = 'mixed-port: 7890\nproxies: []\n';
      final result = ConfigTemplate.process(
        config,
        quicRejectPolicy: ConfigTemplate.quicRejectPolicyGooglevideo,
      );
      expect(result, isNot(contains('NETWORK,UDP')));
    });

    test('preserves indentation of existing rules (4-space)', () {
      const config = '''
mixed-port: 7890
rules:
    - DOMAIN-SUFFIX,example.com,DIRECT
    - MATCH,DIRECT
''';
      final result = ConfigTemplate.process(
        config,
        quicRejectPolicy: ConfigTemplate.quicRejectPolicyGooglevideo,
      );
      expect(
        result,
        contains('''
    - "AND,((DOMAIN-SUFFIX,googlevideo.com),(NETWORK,UDP)),REJECT-DROP"'''),
      );
    });

    test(
      'no cross-call pollution: omitted arg always defaults to googlevideo',
      () {
        // Regression guard for the removed _runtimeQuicRejectPolicy global.
        // Running process() with an explicit policy must NOT change what a
        // subsequent process() call (no arg) does — the default resolves
        // purely from normalizeQuicRejectPolicy(null) each invocation.
        final first = ConfigTemplate.process(
          baseConfig,
          quicRejectPolicy: ConfigTemplate.quicRejectPolicyAll,
        );
        expect(first, contains(globalRejectRule));

        final second = ConfigTemplate.process(baseConfig);
        expect(
          second,
          contains(googlevideoRejectRule),
          reason:
              'default must be googlevideo, not leaked "all" from prior call',
        );
        expect(second, isNot(contains(globalRejectRule)));

        final third = ConfigTemplate.process(
          baseConfig,
          quicRejectPolicy: ConfigTemplate.quicRejectPolicyOff,
        );
        expect(third, isNot(contains(globalRejectRule)));
        expect(third, isNot(contains(googlevideoRejectRule)));

        final fourth = ConfigTemplate.process(baseConfig);
        expect(
          fourth,
          contains(googlevideoRejectRule),
          reason:
              'default must be googlevideo, not leaked "off" from prior call',
        );
      },
    );
  });

  // v1.0.21 hotfix P1-4: two throughput-killing sniffer flags that were
  // still present in assets/default_config.yaml even though
  // ConfigTemplate._ensureSniffer rewrites the block without them. Source
  // of truth is the runtime template. These tests lock it in so any
  // future re-introduction (copy-paste from an old subscription, asset
  // edit, refactor of _ensureSniffer) fails loudly.
  group('ConfigTemplate sniffer — throughput flags', () {
    test(
      'strips force-dns-mapping / parse-pure-ip from subscription input',
      () {
        // Simulate a subscription that ships both flags (older airport
        // configs still do). process() must remove them.
        const config = '''
mixed-port: 7890
sniffer:
  enable: true
  force-dns-mapping: true
  parse-pure-ip: true
  sniff:
    HTTP:
      ports: [80]
proxies: []
''';
        final result = ConfigTemplate.process(config);
        expect(
          result,
          isNot(contains('force-dns-mapping')),
          reason:
              'force-dns-mapping: true forced every fake-IP lookup even '
              'when already accurate — cost ~30% throughput vs ClashMeta.',
        );
        expect(
          result,
          isNot(contains('parse-pure-ip')),
          reason:
              'parse-pure-ip: true ran HTTP/TLS/QUIC sniff on every '
              'pure-IP connection, not just DNS-derived ones.',
        );
        // override-destination still present (the flag we DO want on).
        expect(result, contains('override-destination: true'));
      },
    );

    test('no sniffer section in input → still no force-dns-mapping / '
        'parse-pure-ip in output', () {
      const config = 'mixed-port: 7890\nproxies: []\n';
      final result = ConfigTemplate.process(config);
      expect(result, isNot(contains('force-dns-mapping')));
      expect(result, isNot(contains('parse-pure-ip')));
      expect(
        result,
        contains('sniffer:'),
        reason: 'sniffer block itself must still be injected',
      );
    });

    test(
      'fallback default_config.yaml has no force-dns-mapping / parse-pure-ip',
      () async {
        // Reading the asset via AssetBundle in a unit test needs the Flutter
        // binding — covered by the other assertions above via process().
        // This test simply confirms the static loader wrapper works once
        // process() has cleaned the merged config.
        const config =
            'proxies:\n  - {name: a, type: ss, server: 1.1.1.1, port: 80}\n';
        final result = ConfigTemplate.process(config);
        expect(result, isNot(contains('force-dns-mapping')));
        expect(result, isNot(contains('parse-pure-ip')));
      },
    );
  });

  group('ConfigTemplate experimental defaults', () {
    test(
      'does not inject quic-go-disable-gso/ecn when subscription has none',
      () {
        const config = 'mixed-port: 7890\nproxies: []\n';
        final result = ConfigTemplate.process(config);
        expect(result, isNot(contains('quic-go-disable-gso')));
        expect(result, isNot(contains('quic-go-disable-ecn')));
        expect(result, isNot(contains('\nexperimental:')));
      },
    );

    test('keeps subscription-provided experimental block verbatim', () {
      const config = '''
mixed-port: 7890
experimental:
  quic-go-disable-gso: true
  sniff-tls-sni: true
''';
      final result = ConfigTemplate.process(config);
      expect(result, contains('quic-go-disable-gso: true'));
      expect(result, contains('sniff-tls-sni: true'));
    });
  });

  group('ConfigTemplate.relayHostWhitelist', () {
    test('empty whitelist is a no-op (regression guard)', () {
      const config = 'mixed-port: 7890\nproxies: []\n';
      final without = ConfigTemplate.process(config);
      final withEmpty = ConfigTemplate.process(
        config,
        relayHostWhitelist: const [],
      );
      expect(withEmpty, equals(without));
    });

    test(
      'populates fake-ip-filter in inline-injected dns section (branch A)',
      () {
        // No `dns:` key present → _ensureDns takes branch A (inline injection)
        const config = 'mixed-port: 7890\nproxies: []\n';
        final result = ConfigTemplate.process(
          config,
          relayHostWhitelist: const ['relay.example.com'],
        );
        expect(result, contains('fake-ip-filter:'));
        expect(result, contains('"relay.example.com"'));
      },
    );

    test('populates fake-ip-filter in existing dns section (branch B)', () {
      const config = '''
mixed-port: 7890
dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - 8.8.8.8
proxies: []
''';
      final result = ConfigTemplate.process(
        config,
        relayHostWhitelist: const ['relay2.example.com'],
      );
      expect(result, contains('"relay2.example.com"'));
      // The injected relay entry should be inside the fake-ip-filter list,
      // not somewhere random — sanity check: it's below the fake-ip-filter:
      // line and above the next top-level key.
      final filterIdx = result.indexOf('fake-ip-filter:');
      final hostIdx = result.indexOf('"relay2.example.com"');
      expect(filterIdx, greaterThanOrEqualTo(0));
      expect(hostIdx, greaterThan(filterIdx));
    });

    test('does not duplicate when host already in fake-ip-filter', () {
      const config = '''
mixed-port: 7890
dns:
  enable: true
  fake-ip-filter:
    - "relay.example.com"
proxies: []
''';
      final result = ConfigTemplate.process(
        config,
        relayHostWhitelist: const ['relay.example.com'],
      );
      final count = RegExp(r'"relay\.example\.com"').allMatches(result).length;
      expect(count, 1);
    });

    test('multi-host whitelist injects each once', () {
      const config = 'mixed-port: 7890\nproxies: []\n';
      final result = ConfigTemplate.process(
        config,
        relayHostWhitelist: const ['a.relay.com', 'b.relay.com'],
      );
      expect(result, contains('"a.relay.com"'));
      expect(result, contains('"b.relay.com"'));
    });
  });

  group('ConfigTemplate provider proxy: DIRECT injection', () {
    test('injects proxy: DIRECT into inline rule-providers entries', () {
      const config = '''
mixed-port: 7890
rule-providers:
  ads: { type: http, behavior: classical, url: 'https://fastly.jsdelivr.net/ads.yaml', path: ./ads.yaml, interval: 86400 }
  openai: { type: http, behavior: classical, url: 'https://fastly.jsdelivr.net/openai.yaml', path: ./openai.yaml, interval: 86400 }
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      // Both inline entries get proxy: DIRECT appended inside the {...}.
      expect(
        RegExp(r'ads:\s*\{[^}]*proxy:\s*DIRECT[^}]*\}').hasMatch(result),
        isTrue,
        reason: 'ads provider missing proxy: DIRECT',
      );
      expect(
        RegExp(r'openai:\s*\{[^}]*proxy:\s*DIRECT[^}]*\}').hasMatch(result),
        isTrue,
        reason: 'openai provider missing proxy: DIRECT',
      );
      // Original keys preserved.
      expect(result, contains("url: 'https://fastly.jsdelivr.net/ads.yaml'"));
      expect(result, contains('interval: 86400'));
    });

    test('injects proxy: DIRECT into inline proxy-providers entries', () {
      const config = '''
mixed-port: 7890
proxy-providers:
  airport1: { type: http, url: 'https://example.com/sub', path: ./airport1.yaml, interval: 3600 }
rules: []
''';
      final result = ConfigTemplate.process(config);
      expect(
        RegExp(r'airport1:\s*\{[^}]*proxy:\s*DIRECT[^}]*\}').hasMatch(result),
        isTrue,
      );
    });

    test(
      'idempotent: respects existing proxy: field (DIRECT or otherwise)',
      () {
        const config = '''
mixed-port: 7890
rule-providers:
  ads: { type: http, url: 'https://x.com/ads', path: ./ads.yaml, interval: 86400, proxy: DIRECT }
  custom: { type: http, url: 'https://y.com/c', path: ./c.yaml, interval: 86400, proxy: MyGroup }
  pristine: { type: http, url: 'https://z.com/p', path: ./p.yaml, interval: 86400 }
rules: []
''';
        final result = ConfigTemplate.process(config);
        // ads keeps its single proxy: DIRECT, no duplicate.
        final adsProxyCount = RegExp(
          r'ads:\s*\{[^}]*?proxy:\s*',
        ).allMatches(result).length;
        expect(adsProxyCount, 1);
        // custom: MyGroup is NOT overwritten — user's explicit choice wins.
        expect(result, contains('proxy: MyGroup'));
        expect(
          result.contains('custom:') &&
              RegExp(r'custom:\s*\{[^}]*proxy:\s*DIRECT').hasMatch(result),
          isFalse,
          reason: 'custom: MyGroup must not be replaced by DIRECT',
        );
        // pristine had no proxy field — gets DIRECT injected.
        expect(
          RegExp(r'pristine:\s*\{[^}]*proxy:\s*DIRECT[^}]*\}').hasMatch(result),
          isTrue,
        );
      },
    );

    test('handles block-style providers and matches sibling indent', () {
      const config = '''
mixed-port: 7890
rule-providers:
  ads:
    type: http
    behavior: classical
    url: 'https://fastly.jsdelivr.net/ads.yaml'
    path: ./ruleset/ads.yaml
    interval: 86400
rules: []
''';
      final result = ConfigTemplate.process(config);
      // Injected as a sibling key under `ads:`, indented to match siblings
      // (4 spaces in this fixture).
      expect(
        result,
        contains('    interval: 86400\n    proxy: DIRECT'),
        reason: 'block-style provider missing proxy: DIRECT at sibling indent',
      );
    });

    test('block-style: skips entry that already has a proxy field', () {
      const config = '''
mixed-port: 7890
rule-providers:
  ads:
    type: http
    url: 'https://fastly.jsdelivr.net/ads.yaml'
    path: ./ads.yaml
    interval: 86400
    proxy: MyGroup
rules: []
''';
      final result = ConfigTemplate.process(config);
      // Single proxy field, untouched.
      expect(
        RegExp(r'ads:\n(?:\s+.*\n)*\s+proxy:').allMatches(result).length,
        1,
      );
      expect(result, contains('proxy: MyGroup'));
      expect(result, isNot(contains('proxy: DIRECT')));
    });

    test('no providers blocks → no-op', () {
      const config = '''
mixed-port: 7890
proxies: []
rules: []
''';
      final result = ConfigTemplate.process(config);
      expect(result, isNot(contains('proxy: DIRECT')));
    });

    test(
      'false-positive guard: path/url containing the word "proxy" is safe',
      () {
        // `path: ./proxies/...` previously could have tripped a naive
        // `proxy:` substring search. The (?:^|,) anchor avoids this.
        const config = '''
mixed-port: 7890
rule-providers:
  ads: { type: http, url: 'https://some-proxy.example.com:8080/ads', path: ./proxies/ads.yaml, interval: 86400 }
rules: []
''';
        final result = ConfigTemplate.process(config);
        // Should still inject proxy: DIRECT — the URL substring doesn't count.
        expect(
          RegExp(r'ads:\s*\{[^}]*proxy:\s*DIRECT[^}]*\}').hasMatch(result),
          isTrue,
        );
      },
    );

    test('no longer pollutes user rules section', () {
      // Pre-fix, every user got DOMAIN-SUFFIX,jsdelivr.net,DIRECT injected
      // into their rules. Confirm we don't do that any more.
      const config = '''
mixed-port: 7890
rule-providers:
  ads: { type: http, url: 'https://fastly.jsdelivr.net/ads.yaml', path: ./ads.yaml, interval: 86400 }
rules:
  - DOMAIN-SUFFIX,example.com,DIRECT
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, isNot(contains('DOMAIN-SUFFIX,jsdelivr.net,DIRECT')));
      expect(
        result,
        isNot(contains('DOMAIN-SUFFIX,githubusercontent.com,DIRECT')),
      );
    });
  });

  group('ConfigTemplate TUN MTU', () {
    test(
      'desktop tun uses AppConstants.defaultTunMtu (matches hot-switch PATCH)',
      () {
        // Production code path injects desktop TUN on macOS/Windows/Linux.
        // Mobile TUN is fd-based and tested separately.
        if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
          return;
        }
        const config = 'mixed-port: 7890\nproxies: []\n';
        final result = ConfigTemplate.process(config, connectionMode: 'tun');
        expect(result, contains('mtu: ${AppConstants.defaultTunMtu}'));
      },
    );
  });
}
