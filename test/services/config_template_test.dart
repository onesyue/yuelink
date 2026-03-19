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

}
