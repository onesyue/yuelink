import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/node_telemetry.dart';
import 'package:yuelink/shared/telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync(
      'yuelink_telemetry_sanitize_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    Telemetry.setEnabled(true);
  });

  tearDown(() {
    Telemetry.setEnabled(false);
  });

  test('preserves node_inventory nodes as a list of scalar maps', () {
    final cursor = Telemetry.recentEvents().length;

    Telemetry.event(
      'node_inventory',
      props: {
        'count': 1,
        'nodes': [
          {
            'fp': '62a0ff42fed5ce2c',
            'type': 'hysteria2',
            'xb_server_id': 127,
            'region': 'TW',
            'label': 'TW-HY2',
          },
        ],
      },
    );

    final event = Telemetry.recentEvents().skip(cursor).single;
    final nodes = event['nodes'];
    expect(nodes, isA<List<dynamic>>());
    expect(nodes, hasLength(1));
    expect(nodes.single, containsPair('fp', '62a0ff42fed5ce2c'));
    expect(nodes.single, containsPair('xb_server_id', 127));
  });

  test('node_inventory emission does not leak raw node secrets', () {
    NodeTelemetry.resetForTest();
    final cursor = Telemetry.recentEvents().length;

    NodeTelemetry.recordInventory([
      {
        'name': 'TW-HY2',
        'type': 'hysteria2',
        'server': 'a.example.com',
        'port': 443,
        'sni': 'a.example.com',
        'password': 'secret-a',
        'xb_server_id': 127,
        'region': 'TW',
      },
    ]);

    final event = Telemetry.recentEvents().skip(cursor).single;
    final node = (event['nodes'] as List<dynamic>).single as Map;
    expect(node.keys, isNot(contains('server')));
    expect(node.keys, isNot(contains('port')));
    expect(node.keys, isNot(contains('sni')));
    expect(node.keys, isNot(contains('password')));
    expect(node.values, isNot(contains('secret-a')));
    expect(node.values, isNot(contains('a.example.com')));
  });

  test('node_urltest uses the same fp and identity as inventory', () {
    NodeTelemetry.resetForTest();
    final cursor = Telemetry.recentEvents().length;

    NodeTelemetry.recordInventory([
      {
        'name': 'TW-HY2',
        'type': 'hysteria2',
        'server': 'a.example.com',
        'port': 443,
        'sni': 'a.example.com',
        'password': 'secret-a',
        'xb_server_id': 127,
        'region': 'TW',
      },
    ]);
    NodeTelemetry.recordUrlTestByName(name: 'TW-HY2', delayMs: 103);

    final events = Telemetry.recentEvents().skip(cursor).toList();
    final inventory = events.firstWhere(
      (event) => event['event'] == 'node_inventory',
    );
    final urltest = events.firstWhere(
      (event) => event['event'] == 'node_urltest',
    );
    final node = (inventory['nodes'] as List<dynamic>).single;

    expect(urltest['fp'], node['fp']);
    expect(urltest['type'], node['type']);
    expect(urltest['xb_server_id'], node['xb_server_id']);
    expect(urltest['region'], node['region']);
  });

  test(
    'failed node_urltest carries identity, normalized delay, and reason',
    () {
      NodeTelemetry.resetForTest();
      final cursor = Telemetry.recentEvents().length;

      NodeTelemetry.recordInventory([
        {
          'name': 'HK-Reality',
          'type': 'vless',
          'server': 'b.example.com',
          'port': 8443,
          'uuid': 'uuid-b',
          'sni': 'b.example.com',
          'xb_server_id': 88,
          'region': 'HK',
        },
      ]);
      NodeTelemetry.recordUrlTestByName(name: 'HK-Reality', delayMs: -1);

      final urltest = Telemetry.recentEvents()
          .skip(cursor)
          .firstWhere((event) => event['event'] == 'node_urltest');
      expect(urltest['ok'], isFalse);
      expect(urltest['delay_ms'], 5000);
      expect(urltest['reason'], 'timeout');
      expect(urltest['xb_server_id'], 88);
      expect(urltest['region'], 'HK');
    },
  );
}
