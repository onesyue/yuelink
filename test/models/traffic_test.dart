import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/models/traffic.dart';

void main() {
  group('Traffic', () {
    test('formats upload/download rates', () {
      const t = Traffic(up: 512, down: 1048576);
      expect(t.upFormatted, '0.00 MB/s');
      expect(t.downFormatted, '1.00 MB/s');
    });

    test('zero traffic', () {
      const t = Traffic();
      expect(t.upFormatted, '0.00 MB/s');
      expect(t.downFormatted, '0.00 MB/s');
    });

    test('KB range', () {
      const t = Traffic(up: 1536, down: 10240);
      expect(t.upFormatted, '0.00 MB/s');
      expect(t.downFormatted, '0.01 MB/s');
    });
  });

  group('ConnectionInfo', () {
    test('fromJson parses correctly', () {
      final conn = ConnectionInfo.fromJson({
        'id': 'abc123',
        'metadata': {
          'host': 'google.com',
          'destinationPort': '443',
          'network': 'tcp',
          'type': 'HTTPS',
        },
        'rule': 'MATCH',
        'rulePayload': 'final',
        'chains': ['HK 01', 'DIRECT'],
        'upload': 1024,
        'download': 4096,
        'start': '2026-01-15T10:30:00Z',
      });

      expect(conn.id, 'abc123');
      expect(conn.host, 'google.com:443');
      expect(conn.network, 'tcp');
      expect(conn.rule, contains('MATCH'));
      expect(conn.rule, contains('final'));
      expect(conn.chains, 'HK 01 → DIRECT');
      expect(conn.upload, 1024);
      expect(conn.download, 4096);
    });

    test('fromJson handles missing fields', () {
      final conn = ConnectionInfo.fromJson({});

      expect(conn.id, '');
      expect(conn.host, ':');
      expect(conn.network, '');
    });
  });
}
