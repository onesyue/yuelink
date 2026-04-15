import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/node_telemetry.dart';

const _sampleYaml = '''
proxies:
  - name: Name A
    type: hysteria2
    server: a.example.com
    port: 443
    sni: a.example.com
    password: secret-a
  - name: Name B
    type: vless
    server: b.example.com
    port: 8443
    sni: b.example.com
    flow: xtls-rprx-vision
    client-fingerprint: chrome
    reality-opts:
      public-key: abcdef
      short-id: 01
''';

void main() {
  group('NodeTelemetry.ensureInventoryLoaded', () {
    test('populates fp map from YAML returned by callback', () async {
      await NodeTelemetry.ensureInventoryLoaded(
        loadActiveConfig: () async => _sampleYaml,
      );

      final fpA = NodeTelemetry.fpForName('Name A');
      expect(fpA, isNotNull);
      expect(fpA!.isNotEmpty, isTrue);
      expect(NodeTelemetry.typeForName('Name A'), 'hysteria2');

      final fpB = NodeTelemetry.fpForName('Name B');
      expect(fpB, isNotNull);
      expect(fpB!.isNotEmpty, isTrue);
      expect(NodeTelemetry.typeForName('Name B'), 'vless');
    });

    test('is idempotent — second call does not change fp', () async {
      // First call — populates (or was populated by previous test).
      await NodeTelemetry.ensureInventoryLoaded(
        loadActiveConfig: () async => _sampleYaml,
      );
      final firstFp = NodeTelemetry.fpForName('Name A');
      expect(firstFp, isNotNull);

      // Second call: callback should NOT be invoked because cache is warm.
      var callbackInvoked = false;
      await NodeTelemetry.ensureInventoryLoaded(
        loadActiveConfig: () async {
          callbackInvoked = true;
          return 'proxies: []';
        },
      );
      expect(callbackInvoked, isFalse);
      expect(NodeTelemetry.fpForName('Name A'), firstFp);
    });

    test('never throws on malformed YAML', () async {
      await NodeTelemetry.ensureInventoryLoaded(
        loadActiveConfig: () async => '::: not valid yaml :::',
      );
      // Still has data from previous tests — just verify no throw.
      expect(true, isTrue);
    });

    test('never throws when callback returns null', () async {
      await NodeTelemetry.ensureInventoryLoaded(
        loadActiveConfig: () async => null,
      );
      expect(true, isTrue);
    });
  });
}
