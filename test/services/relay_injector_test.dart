import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:yuelink/core/kernel/config_template.dart';
import 'package:yuelink/core/kernel/relay_injector.dart';
import 'package:yuelink/domain/models/relay_profile.dart';

const _baseConfig = '''
proxies:
  - name: HK-VLESS
    type: vless
    server: hk.example.com
    port: 443
    uuid: aaaa
  - name: JP-VLESS
    type: vless
    server: jp.example.com
    port: 443
    uuid: bbbb
  - name: SG-HY2
    type: hysteria2
    server: sg.example.com
    port: 443
    password: ccc
proxy-groups:
  - name: PROXY
    type: select
    proxies: [HK-VLESS, JP-VLESS, SG-HY2]
rules:
  - MATCH,PROXY
''';

void main() {
  group('RelayInjector.apply — disabled / invalid', () {
    test('null profile is a no-op with skipReason=no_profile', () {
      final r = RelayInjector.apply(_baseConfig, null);
      expect(r.config, equals(_baseConfig));
      expect(r.injected, isFalse);
      expect(r.targetCount, 0);
      expect(r.skipReason, RelayApplyResult.skipNoProfile);
    });

    test('enabled=false is a no-op with skipReason=invalid_profile', () {
      const profile = RelayProfile.disabled();
      final r = RelayInjector.apply(_baseConfig, profile);
      expect(r.config, equals(_baseConfig));
      expect(r.injected, isFalse);
      expect(r.skipReason, RelayApplyResult.skipInvalidProfile);
    });

    test('missing host skips injection', () {
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: '',
        port: 443,
      );
      final r = RelayInjector.apply(_baseConfig, profile);
      expect(r.config, equals(_baseConfig));
      expect(r.injected, isFalse);
      expect(r.skipReason, RelayApplyResult.skipInvalidProfile);
      expect(r.config, isNot(contains(RelayInjector.relayNodeName)));
    });

    test('invalid port skips injection', () {
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'r.example.com',
        port: 0,
      );
      final r = RelayInjector.apply(_baseConfig, profile);
      expect(r.config, equals(_baseConfig));
      expect(r.injected, isFalse);
      expect(r.skipReason, RelayApplyResult.skipInvalidProfile);
    });

    test('officialAccess source is rejected in Phase 1A', () {
      const profile = RelayProfile(
        enabled: true,
        source: RelaySource.officialAccess,
        type: 'vless',
        host: 'r.example.com',
        port: 443,
      );
      final r = RelayInjector.apply(_baseConfig, profile);
      expect(r.config, equals(_baseConfig));
      expect(r.injected, isFalse);
      expect(r.skipReason, RelayApplyResult.skipInvalidProfile);
    });

    test('allowlist mode with empty list is invalid', () {
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'r.example.com',
        port: 443,
        targetMode: RelayTargetMode.allowlistNames,
        allowlistNames: [],
      );
      final r = RelayInjector.apply(_baseConfig, profile);
      expect(r.config, equals(_baseConfig));
      expect(r.injected, isFalse);
      expect(r.skipReason, RelayApplyResult.skipInvalidProfile);
    });
  });

  group('RelayInjector.apply — allVless mode', () {
    test('wraps every VLESS node, skips HY2', () {
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
        extras: {'uuid': 'relay-uuid', 'tls': true},
      );
      final r = RelayInjector.apply(_baseConfig, profile);
      expect(r.injected, isTrue);
      expect(r.targetCount, 2, reason: 'two VLESS, one HY2 skipped');
      expect(r.skipReason, isNull);

      final yaml = loadYaml(r.config) as YamlMap;
      final proxies = (yaml['proxies'] as YamlList).cast<YamlMap>();

      final relay = proxies.firstWhere(
        (p) => p['name'] == RelayInjector.relayNodeName,
        orElse: () => throw StateError('relay node missing'),
      );
      expect(relay['type'], 'vless');
      expect(relay['server'], 'relay.example.com');
      expect(relay['port'], 443);
      expect(relay['uuid'], 'relay-uuid');
      expect(relay['tls'], true);

      final hk = proxies.firstWhere((p) => p['name'] == 'HK-VLESS');
      final jp = proxies.firstWhere((p) => p['name'] == 'JP-VLESS');
      final sg = proxies.firstWhere((p) => p['name'] == 'SG-HY2');

      expect(hk['dialer-proxy'], RelayInjector.relayNodeName);
      expect(jp['dialer-proxy'], RelayInjector.relayNodeName);
      expect(sg['dialer-proxy'], isNull,
          reason: 'HY2 must not be wrapped in allVless mode');

      expect(relay['dialer-proxy'], isNull,
          reason: 'relay node itself must never carry dialer-proxy');
    });
  });

  group('RelayInjector.apply — allowlistNames mode', () {
    test('only listed VLESS nodes get dialer-proxy', () {
      const profile = RelayProfile(
        enabled: true,
        type: 'trojan',
        host: 'relay2.example.com',
        port: 8443,
        targetMode: RelayTargetMode.allowlistNames,
        allowlistNames: ['HK-VLESS'],
      );
      final r = RelayInjector.apply(_baseConfig, profile);
      expect(r.injected, isTrue);
      expect(r.targetCount, 1);

      final yaml = loadYaml(r.config) as YamlMap;
      final proxies = (yaml['proxies'] as YamlList).cast<YamlMap>();

      final hk = proxies.firstWhere((p) => p['name'] == 'HK-VLESS');
      final jp = proxies.firstWhere((p) => p['name'] == 'JP-VLESS');

      expect(hk['dialer-proxy'], RelayInjector.relayNodeName);
      expect(jp['dialer-proxy'], isNull);
    });

    test('HY2 in allowlist is still skipped (Phase 1A guardrail)', () {
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
        targetMode: RelayTargetMode.allowlistNames,
        allowlistNames: ['SG-HY2'],
      );
      final r = RelayInjector.apply(_baseConfig, profile);
      expect(r.injected, isFalse);
      expect(r.skipReason, RelayApplyResult.skipNoTargets);

      final yaml = loadYaml(r.config) as YamlMap;
      final proxies = (yaml['proxies'] as YamlList).cast<YamlMap>();

      // allowlist only had SG-HY2 → no targets actually matched → no relay
      // node should have been added either.
      expect(
        proxies.any((p) => p['name'] == RelayInjector.relayNodeName),
        isFalse,
        reason: 'no valid targets → no relay node injected',
      );
      final sg = proxies.firstWhere((p) => p['name'] == 'SG-HY2');
      expect(sg['dialer-proxy'], isNull);
    });

    test('allowlist name that does not exist → no_targets', () {
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
        targetMode: RelayTargetMode.allowlistNames,
        allowlistNames: ['DOES-NOT-EXIST'],
      );
      final r = RelayInjector.apply(_baseConfig, profile);
      expect(r.config, equals(_baseConfig));
      expect(r.injected, isFalse);
      expect(r.skipReason, RelayApplyResult.skipNoTargets);
    });
  });

  group('RelayInjector.apply — safety', () {
    test('pre-existing _yue_relay name → name_collision, input preserved', () {
      const config = '''
proxies:
  - name: _yue_relay
    type: socks5
    server: pre.example.com
    port: 1080
  - name: HK
    type: vless
    server: hk.example.com
    port: 443
proxy-groups:
  - name: PROXY
    type: select
    proxies: [HK]
''';
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
      );
      final r = RelayInjector.apply(config, profile);
      expect(r.config, equals(config));
      expect(r.injected, isFalse);
      expect(r.skipReason, RelayApplyResult.skipNameCollision);
      // Ensure the original _yue_relay definition is preserved
      expect(r.config, contains('pre.example.com'));
      expect(r.config, isNot(contains('relay.example.com')));
    });

    test('malformed input YAML → exception skipReason, input unchanged', () {
      const broken = 'this is not valid yaml : : :\n\tnope';
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
      );
      final r = RelayInjector.apply(broken, profile);
      expect(r.config, equals(broken));
      expect(r.injected, isFalse);
      // Could be skipNotYaml or skipException depending on parser behavior —
      // both are acceptable no-op outcomes.
      expect(
        r.skipReason,
        anyOf(
          RelayApplyResult.skipNotYaml,
          RelayApplyResult.skipException,
        ),
      );
    });

    test('empty proxies list → no_proxies', () {
      const config = 'proxies: []\nrules: []\n';
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
      );
      final r = RelayInjector.apply(config, profile);
      expect(r.config, equals(config));
      expect(r.injected, isFalse);
      expect(r.skipReason, RelayApplyResult.skipNoProxies);
    });

    test('extras cannot override identity fields (name/type/server/port)', () {
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
        extras: {
          'name': 'evil',
          'type': 'shadowsocks',
          'server': 'evil.example.com',
          'port': 80,
          'uuid': 'good-uuid',
        },
      );
      final r = RelayInjector.apply(_baseConfig, profile);
      expect(r.injected, isTrue);

      final yaml = loadYaml(r.config) as YamlMap;
      final proxies = (yaml['proxies'] as YamlList).cast<YamlMap>();
      final relay =
          proxies.firstWhere((p) => p['name'] == RelayInjector.relayNodeName);
      expect(relay['type'], 'vless');
      expect(relay['server'], 'relay.example.com');
      expect(relay['port'], 443);
      expect(relay['uuid'], 'good-uuid',
          reason: 'non-identity extras still flow through');
    });
  });

  group('RelayInjector + chain proxy coexistence', () {
    test('_upstream dialer-proxy survives RelayInjector.apply', () {
      // Simulate soft-router upstream already set.
      final withUpstream = ConfigTemplate.injectUpstreamProxy(
          _baseConfig, 'socks5', '10.0.0.1', 1080);

      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
      );
      final r = RelayInjector.apply(withUpstream, profile);
      expect(r.injected, isTrue);

      final yaml = loadYaml(r.config) as YamlMap;
      final proxies = (yaml['proxies'] as YamlList).cast<YamlMap>();

      final upstream = proxies.firstWhere((p) => p['name'] == '_upstream');
      expect(upstream, isNotNull);
      final hk = proxies.firstWhere((p) => p['name'] == 'HK-VLESS');
      // RelayInjector wraps VLESS with the relay; the prior _upstream wiring
      // on this specific node is replaced — we preserve the _upstream *node*
      // itself, not its assignment to every proxy.
      expect(hk['dialer-proxy'], RelayInjector.relayNodeName);
    });
  });
}
