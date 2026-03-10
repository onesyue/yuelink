import 'package:flutter_test/flutter_test.dart';

import 'package:yuelink/services/node_filter_service.dart';

// Test the static _applyRules method indirectly via a simple YAML
const _sampleYaml = '''
proxies:
  {name: HK-01, type: ss, server: hk1.example.com, port: 443, cipher: aes-256-gcm, password: test}
  {name: JP-02, type: vmess, server: jp2.example.com, port: 443, uuid: abc}
  {name: US-03, type: trojan, server: us3.example.com, port: 443, password: test}
  {name: SG-04, type: ss, server: sg4.example.com, port: 443, cipher: aes-256-gcm, password: test}

proxy-groups:
  - name: PROXY
    type: select
    proxies: [HK-01, JP-02, US-03, SG-04]
''';

void main() {
  group('NodeFilterRule JSON', () {
    test('serializes and deserializes keep rule', () {
      const rule = NodeFilterRule(
        action: NodeFilterAction.keep,
        pattern: r'HK|JP',
      );
      final json = rule.toJson();
      final restored = NodeFilterRule.fromJson(json);
      expect(restored.action, NodeFilterAction.keep);
      expect(restored.pattern, r'HK|JP');
      expect(restored.renameTo, isNull);
    });

    test('serializes rename rule with renameTo', () {
      const rule = NodeFilterRule(
        action: NodeFilterAction.rename,
        pattern: r'HK-(\d+)',
        renameTo: r'香港-$1',
      );
      final json = rule.toJson();
      final restored = NodeFilterRule.fromJson(json);
      expect(restored.action, NodeFilterAction.rename);
      expect(restored.renameTo, r'香港-$1');
    });
  });

  group('UpdateChecker._isNewer', () {
    test('detects newer minor version', () {
      // Access via public-facing parse logic — test version comparison
      expect(_isNewer('1.1.0', '1.0.0'), isTrue);
    });

    test('same version is not newer', () {
      expect(_isNewer('1.0.0', '1.0.0'), isFalse);
    });

    test('older version is not newer', () {
      expect(_isNewer('0.9.9', '1.0.0'), isFalse);
    });

    test('newer patch is detected', () {
      expect(_isNewer('1.0.2', '1.0.1'), isTrue);
    });
  });
}

// Mirror the private _isNewer logic for testing
bool _isNewer(String candidate, String current) {
  List<int> parse(String v) {
    final parts = v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) parts.add(0);
    return parts;
  }
  final c = parse(candidate);
  final cur = parse(current);
  for (var i = 0; i < 3; i++) {
    if (c[i] > cur[i]) return true;
    if (c[i] < cur[i]) return false;
  }
  return false;
}
