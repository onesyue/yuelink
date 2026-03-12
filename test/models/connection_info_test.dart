import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/models/traffic.dart';

void main() {
  group('ConnectionInfo', () {
    test('parses full JSON correctly', () {
      final conn = ConnectionInfo.fromJson({
        'id': 'conn-001',
        'metadata': {
          'host': 'api.example.com',
          'destinationPort': '443',
          'network': 'tcp',
          'type': 'HTTPS',
        },
        'rule': 'Domain',
        'rulePayload': 'example.com',
        'chains': ['HK-01', 'Proxy'],
        'upload': 2048,
        'download': 8192,
        'start': '2026-03-10T08:30:00Z',
      });

      expect(conn.id, 'conn-001');
      expect(conn.host, 'api.example.com:443');
      expect(conn.network, 'tcp');
      expect(conn.type, 'HTTPS');
      expect(conn.rule, 'Domain (example.com)');
      expect(conn.chains, 'HK-01 → Proxy');
      expect(conn.upload, 2048);
      expect(conn.download, 8192);
      expect(conn.start.hour, 8);
    });

    test('parses destinationIP fallback', () {
      final conn = ConnectionInfo.fromJson({
        'id': '1',
        'metadata': {
          'destinationIP': '1.2.3.4',
          'destinationPort': '80',
          'network': 'udp',
          'type': 'HTTP',
        },
        'rule': 'MATCH',
        'chains': ['DIRECT'],
        'upload': 0,
        'download': 0,
        'start': '2026-01-01T00:00:00Z',
      });

      expect(conn.host, '1.2.3.4:80');
      expect(conn.network, 'udp');
      expect(conn.chains, 'DIRECT');
    });

    test('handles completely empty JSON', () {
      final conn = ConnectionInfo.fromJson({});

      expect(conn.id, '');
      expect(conn.host, ':');
      expect(conn.network, '');
      expect(conn.upload, 0);
      expect(conn.download, 0);
    });

    test('rule without payload', () {
      final conn = ConnectionInfo.fromJson({
        'id': '2',
        'metadata': {
          'host': 'test.com',
          'destinationPort': '443',
          'network': 'tcp',
          'type': 'TLS',
        },
        'rule': 'GeoIP',
        'chains': ['JP-01'],
        'upload': 100,
        'download': 500,
        'start': '2026-01-01T00:00:00Z',
      });

      expect(conn.rule, 'GeoIP');
      expect(conn.rule.contains('('), false);
    });
  });

  group('Traffic', () {
    test('default values', () {
      const t = Traffic();
      expect(t.up, 0);
      expect(t.down, 0);
      expect(t.upFormatted, '0.00 MB/s');
      expect(t.downFormatted, '0.00 MB/s');
    });

    test('MB range formatting', () {
      const t = Traffic(down: 1048576); // 1 MB/s
      expect(t.downFormatted, '1.00 MB/s');
    });
  });
}
