import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/models/connection.dart';

void main() {
  group('ActiveConnection', () {
    test('fromJson parses full response', () {
      final conn = ActiveConnection.fromJson({
        'id': 'abc-123',
        'metadata': {
          'host': 'example.com',
          'destinationIP': '1.2.3.4',
          'destinationPort': '443',
          'sourceIP': '192.168.1.1',
          'sourcePort': '50000',
          'network': 'tcp',
          'type': 'HTTPS',
          'processPath': '/usr/bin/curl',
        },
        'rule': 'Domain',
        'rulePayload': 'example.com',
        'chains': ['HK-01', 'Proxy'],
        'upload': 2048,
        'download': 8192,
        'curUploadSpeed': 100,
        'curDownloadSpeed': 500,
        'start': '2026-03-20T10:30:00Z',
      });

      expect(conn.id, 'abc-123');
      expect(conn.network, 'tcp');
      expect(conn.type, 'HTTPS');
      expect(conn.host, 'example.com');
      expect(conn.destinationIp, '1.2.3.4');
      expect(conn.sourceIp, '192.168.1.1');
      expect(conn.processPath, '/usr/bin/curl');
      expect(conn.processName, 'curl');
      expect(conn.rule, 'Domain');
      expect(conn.rulePayload, 'example.com');
      expect(conn.chains, ['HK-01', 'Proxy']);
      expect(conn.upload, 2048);
      expect(conn.download, 8192);
      expect(conn.curUploadSpeed, 100);
      expect(conn.curDownloadSpeed, 500);
      expect(conn.target, 'example.com');
    });

    test('target falls back to destinationIp:port when host empty', () {
      final conn = ActiveConnection.fromJson({
        'id': '1',
        'metadata': {
          'destinationIP': '8.8.8.8',
          'destinationPort': '53',
          'network': 'udp',
          'type': 'DNS',
        },
        'rule': 'MATCH',
        'chains': ['DIRECT'],
        'upload': 0,
        'download': 0,
        'start': '2026-01-01T00:00:00Z',
      });

      // host falls back to destinationIP in fromJson
      expect(conn.host, '8.8.8.8');
      expect(conn.target, '8.8.8.8');
    });

    test('processName extracts basename from Windows path', () {
      final conn = ActiveConnection.fromJson({
        'id': '2',
        'metadata': {
          'host': 'test.com',
          'destinationPort': '443',
          'network': 'tcp',
          'type': 'TLS',
          'processPath': r'C:\Windows\System32\svchost.exe',
        },
        'rule': 'MATCH',
        'chains': [],
        'upload': 0,
        'download': 0,
        'start': '2026-01-01T00:00:00Z',
      });

      expect(conn.processName, 'svchost.exe');
    });

    test('handles empty JSON gracefully', () {
      final conn = ActiveConnection.fromJson({});

      expect(conn.id, '');
      expect(conn.network, '');
      expect(conn.host, '');
      expect(conn.target, '');
      expect(conn.processName, '');
      expect(conn.upload, 0);
      expect(conn.download, 0);
    });

    test('durationText formats correctly', () {
      final now = DateTime.now();
      final conn = ActiveConnection(
        id: '1',
        network: 'tcp',
        type: 'HTTP',
        host: 'test.com',
        destinationIp: '',
        destinationPort: '80',
        sourceIp: '',
        sourcePort: '',
        processPath: '',
        rule: 'MATCH',
        rulePayload: '',
        chains: const [],
        upload: 0,
        download: 0,
        curUploadSpeed: 0,
        curDownloadSpeed: 0,
        start: now.subtract(const Duration(hours: 2, minutes: 30)),
        processName: '',
        target: 'test.com',
      );

      expect(conn.durationText, contains('h'));
      expect(conn.durationText, contains('m'));
    });

    test('copyWithCounters reuses string fields', () {
      final orig = ActiveConnection.fromJson({
        'id': 'x',
        'metadata': {
          'host': 'foo.com',
          'destinationPort': '443',
          'network': 'tcp',
          'type': 'TLS',
          'processPath': '/usr/bin/curl',
        },
        'rule': 'MATCH',
        'chains': ['Proxy'],
        'upload': 100,
        'download': 200,
        'start': '2026-01-01T00:00:00Z',
      });
      final next = orig.copyWithCounters(
        upload: 500,
        download: 800,
        curUploadSpeed: 10,
        curDownloadSpeed: 20,
      );
      expect(next.upload, 500);
      expect(next.download, 800);
      // Reference equality on shared immutable fields
      expect(identical(next.host, orig.host), isTrue);
      expect(identical(next.processName, orig.processName), isTrue);
      expect(identical(next.target, orig.target), isTrue);
      expect(identical(next.chains, orig.chains), isTrue);
    });
  });

  group('ConnectionsSnapshot', () {
    test('fromJson parses connections array', () {
      final snapshot = ConnectionsSnapshot.fromJson({
        'connections': [
          {
            'id': 'c1',
            'metadata': {'host': 'a.com', 'destinationPort': '443', 'network': 'tcp', 'type': 'TLS'},
            'rule': 'MATCH',
            'chains': ['DIRECT'],
            'upload': 100,
            'download': 200,
            'start': '2026-01-01T00:00:00Z',
          },
          {
            'id': 'c2',
            'metadata': {'host': 'b.com', 'destinationPort': '80', 'network': 'tcp', 'type': 'HTTP'},
            'rule': 'Domain',
            'chains': ['Proxy'],
            'upload': 50,
            'download': 100,
            'start': '2026-01-01T00:00:00Z',
          },
        ],
        'downloadTotal': 1048576,
        'uploadTotal': 524288,
      });

      expect(snapshot.connections.length, 2);
      expect(snapshot.connections[0].id, 'c1');
      expect(snapshot.connections[1].id, 'c2');
      expect(snapshot.downloadTotal, 1048576);
      expect(snapshot.uploadTotal, 524288);
    });

    test('fromJson handles null connections', () {
      final snapshot = ConnectionsSnapshot.fromJson({});

      expect(snapshot.connections, isEmpty);
      expect(snapshot.downloadTotal, 0);
      expect(snapshot.uploadTotal, 0);
    });
  });
}
