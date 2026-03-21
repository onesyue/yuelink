import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/services/config_template.dart';

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
      expect(
        ConfigTemplate.getApiPort('external-controller: :8080'),
        8080,
      );
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
    test('uses subscription config directly if it has proxy-groups and rules',
        () {
      const template = 'mixed-port: 7890\nproxies:\n';
      const sub = 'proxies:\n  - name: test\nproxy-groups:\n  - name: g\nrules:\n  - MATCH,DIRECT';
      final result = ConfigTemplate.mergeIfNeeded(template, sub);
      expect(result, equals(sub));
    });

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
          'dns:'.allMatches(result).length, 1, reason: 'dns should not be duplicated');
      expect('sniffer:'.allMatches(result).length, 1,
          reason: 'sniffer should not be duplicated');
      expect('geodata-mode:'.allMatches(result).length, 1,
          reason: 'geodata-mode should not be duplicated');
      expect('profile:'.allMatches(result).length, 1,
          reason: 'profile should not be duplicated');
      expect('mixed-port:'.allMatches(result).length, 1,
          reason: 'mixed-port should not be duplicated');
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
      final result =
          ConfigTemplate.injectProxyChain(baseConfig, ['HK', 'JP'], '自动选择');
      // JP (exit) must have dialer-proxy: HK
      expect(result,
          anyOf(contains('dialer-proxy: HK'), contains('dialer-proxy: "HK"')));
      // HK (entry) must NOT have dialer-proxy pointing to JP
      expect(result, isNot(contains('dialer-proxy: JP')));
      expect(result, isNot(contains('dialer-proxy: "JP"')));
      // No chain wrapper groups should be created
      expect(result, isNot(contains('_YueLink_Chain_')));
      // No relay type
      expect(result,
          isNot(anyOf(contains('type: relay'), contains('type: "relay"'))));
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
      final result =
          ConfigTemplate.injectProxyChain(config, ['A', 'B', 'C'], '选择');
      // B dials through A
      expect(result,
          anyOf(contains('dialer-proxy: A'), contains('dialer-proxy: "A"')));
      // C dials through B
      expect(result,
          anyOf(contains('dialer-proxy: B'), contains('dialer-proxy: "B"')));
      // A (entry) has no dialer-proxy
      expect(result, isNot(contains('dialer-proxy: C')));
      expect(result, isNot(contains('dialer-proxy: "C"')));
    });

    test('is idempotent — re-inject clears old dialer-proxy before re-setting', () {
      var result =
          ConfigTemplate.injectProxyChain(baseConfig, ['HK', 'JP'], '自动选择');
      result =
          ConfigTemplate.injectProxyChain(result, ['HK', 'JP'], '自动选择');
      // Exactly one dialer-proxy in the entire config (JP → HK)
      expect(RegExp(r'dialer-proxy:').allMatches(result).length, 1);
    });

    test('returns original config for less than 2 nodes', () {
      expect(ConfigTemplate.injectProxyChain(baseConfig, ['HK'], '自动选择'),
          equals(baseConfig));
      expect(ConfigTemplate.injectProxyChain(baseConfig, [], '自动选择'),
          equals(baseConfig));
    });

    test('returns original config when activeGroup not found', () {
      expect(
          ConfigTemplate.injectProxyChain(
              baseConfig, ['HK', 'JP'], 'NonExistent'),
          equals(baseConfig));
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
      final result = ConfigTemplate.injectProxyChain(
          legacyConfig, ['HK', 'JP'], '自动选择');
      expect(result, isNot(contains('dialer-proxy: SomeNode')));
      expect(result, isNot(contains('dialer-proxy: "SomeNode"')));
      // JP should now have dialer-proxy: HK
      expect(result,
          anyOf(contains('dialer-proxy: HK'), contains('dialer-proxy: "HK"')));
    });

    test('removes old _YueLink_Chain_* groups on re-inject (backward compat)', () {
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
      final result = ConfigTemplate.injectProxyChain(
          oldChainConfig, ['HK', 'JP'], '自动选择');
      expect(result, isNot(contains('_YueLink_Chain_')));
      expect(result,
          anyOf(contains('dialer-proxy: HK'), contains('dialer-proxy: "HK"')));
    });
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
      expect(result,
          anyOf(contains('dialer-proxy: _upstream'),
              contains('dialer-proxy: "_upstream"')));
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

}
