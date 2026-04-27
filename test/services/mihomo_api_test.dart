import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/infrastructure/datasources/mihomo_api.dart';

void main() {
  group('MihomoApi', () {
    test('default configuration', () {
      final api = MihomoApi();
      expect(api.host, '127.0.0.1');
      expect(api.port, 9090);
      expect(api.secret, isNull);
    });

    test('custom configuration', () {
      final api = MihomoApi(host: '192.168.1.1', port: 9091, secret: 'test');
      expect(api.host, '192.168.1.1');
      expect(api.port, 9091);
      expect(api.secret, 'test');
    });

    test('isAvailable returns false when not reachable', () async {
      final api = MihomoApi(port: 1); // unlikely to have anything on port 1
      final available = await api.isAvailable();
      expect(available, false);
    });

    test('healthSnapshot classifies socket failure (port not listening)',
        () async {
      // Port 1 is reserved and almost never has a listener; the OS
      // refuses the connection synchronously, which surfaces as
      // SocketException → reason 'socket'.
      final api = MihomoApi(port: 1);
      final snap = await api.healthSnapshot();
      expect(snap.ok, isFalse);
      expect(
        snap.reason,
        anyOf('socket', 'timeout'),
        reason:
            'connect-refused on most platforms is socket; some sandboxed '
            'CI environments swallow it and surface as timeout instead',
      );
    });
  });

  group('MihomoApiException', () {
    test('toString format', () {
      final e = MihomoApiException(404, 'not found');
      expect(e.toString(), 'MihomoApiException(404): not found');
    });

    test('stores status code and body', () {
      final e = MihomoApiException(500, 'internal error');
      expect(e.statusCode, 500);
      expect(e.body, 'internal error');
    });
  });
}
