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
    xb_server_id: 127
    region: HK
  - name: Name B
    type: vless
    server: b.example.com
    port: 8443
    uuid: uuid-b
    sni: b.example.com
    xb_server_id: 94
    region: TW
    flow: xtls-rprx-vision
    client-fingerprint: chrome
    reality-opts:
      public-key: abcdef
      short-id: 01
''';

void main() {
  group('NodeTelemetry.ensureInventoryLoaded', () {
    setUp(NodeTelemetry.resetForTest);

    test('uses the v2 SHA256 fingerprint contract', () {
      final fp = NodeTelemetry.fingerprint({
        'name': 'Name A',
        'type': 'hysteria2',
        'server': 'a.example.com',
        'port': 443,
        'sni': 'a.example.com',
        'password': 'secret-a',
        'xb_server_id': 127,
      });

      expect(fp, '51f9ec1b513c6709');
    });

    test('inventory row includes fp and server identity without secrets', () {
      final row = NodeTelemetry.inventoryRow({
        'name': 'TW-HY2',
        'type': 'hysteria2',
        'server': 'a.example.com',
        'port': 443,
        'sni': 'a.example.com',
        'password': 'secret-a',
        'xb_server_id': 127,
        'region': 'TW',
      });

      expect(row['fp'], '51f9ec1b513c6709');
      expect(row['type'], 'hysteria2');
      expect(row['xb_server_id'], 127);
      expect(row['region'], 'TW');
      expect(row['label'], 'TW-HY2');
      expect(row.containsKey('password'), isFalse);
      expect(row.containsKey('uuid'), isFalse);
      expect(row.containsKey('server'), isFalse);
    });

    test('inventory row falls back to sid when xb_server_id is absent', () {
      final row = NodeTelemetry.inventoryRow({
        'name': 'TW-Reality',
        'type': 'vless',
        'server': 'b.example.com',
        'port': 8443,
        'uuid': 'uuid-b',
        'sni': 'b.example.com',
        'sid': 'yue-tw-relay',
        'region': 'TW',
      });

      expect(row['type'], 'vless');
      expect(row['sid'], 'yue-tw-relay');
      expect(row.containsKey('xb_server_id'), isFalse);
      expect(row['region'], 'TW');
    });

    test('uses sid as the v2 node_id hash input when numeric id is absent', () {
      final fp = NodeTelemetry.fingerprint({
        'name': 'TW-Reality',
        'type': 'vless',
        'server': 'b.example.com',
        'port': 8443,
        'uuid': 'uuid-b',
        'sni': 'b.example.com',
        'sid': 'yue-tw-relay',
      });

      expect(fp, 'd4e2f32ca9cf518f');
    });

    test('uses ws host as sni/host fallback for v2 hash', () {
      final fp = NodeTelemetry.fingerprint({
        'name': 'TW-Reality',
        'type': 'vless',
        'server': 'b.example.com',
        'port': 8443,
        'uuid': 'uuid-b',
        'xb_server_id': 94,
        'ws-opts': {
          'headers': {'Host': 'ws.example.com'},
        },
      });

      expect(fp, 'd03b611b5e044bc6');
    });

    test('populates fp map from YAML returned by callback', () async {
      await NodeTelemetry.ensureInventoryLoaded(
        loadActiveConfig: () async => _sampleYaml,
      );

      final fpA = NodeTelemetry.fpForName('Name A');
      expect(fpA, isNotNull);
      expect(fpA!.isNotEmpty, isTrue);
      expect(fpA, NodeTelemetry.metadataForName('Name A')?['fp']);
      expect(NodeTelemetry.typeForName('Name A'), 'hysteria2');
      expect(NodeTelemetry.metadataForName('Name A')?['xb_server_id'], 127);

      final fpB = NodeTelemetry.fpForName('Name B');
      expect(fpB, isNotNull);
      expect(fpB!.isNotEmpty, isTrue);
      expect(fpB, NodeTelemetry.metadataForName('Name B')?['fp']);
      expect(NodeTelemetry.typeForName('Name B'), 'vless');
      expect(NodeTelemetry.metadataForName('Name B')?['xb_server_id'], 94);
    });

    test('is idempotent — second call does not change fp', () async {
      // First call populates the cache.
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
