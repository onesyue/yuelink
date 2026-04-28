import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuelink/infrastructure/datasources/mihomo_api.dart';

/// HTTP-roundtrip tests for [MihomoApi]. Uses `package:http/testing.dart`'s
/// `MockClient` to stub responses without binding a real socket — the
/// reason this file exists at all (the pre-3.D MihomoApi used the
/// package-level `http.get` global, which couldn't be mocked).
void main() {
  group('MihomoApi — request shape (auth header / URL / method)', () {
    test('Bearer header is set when secret is provided', () async {
      String? capturedAuth;
      final api = MihomoApi(
        secret: 'sekret',
        client: MockClient((req) async {
          capturedAuth = req.headers['Authorization'];
          return http.Response(jsonEncode({'meta': true}), 200);
        }),
      );
      await api.getProxies();
      expect(capturedAuth, 'Bearer sekret');
    });

    test('Authorization header omitted when secret is null', () async {
      final headers = <String, String>{};
      final api = MihomoApi(
        client: MockClient((req) async {
          headers.addAll(req.headers);
          return http.Response('{}', 200);
        }),
      );
      await api.getProxies();
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('GET /proxies hits the right URL', () async {
      Uri? capturedUrl;
      final api = MihomoApi(
        host: 'localhost',
        port: 7654,
        client: MockClient((req) async {
          capturedUrl = req.url;
          return http.Response('{}', 200);
        }),
      );
      await api.getProxies();
      expect(capturedUrl?.scheme, 'http');
      expect(capturedUrl?.host, 'localhost');
      expect(capturedUrl?.port, 7654);
      expect(capturedUrl?.path, '/proxies');
    });

    test('changeProxy URL-encodes group + sends PUT with JSON body',
        () async {
      String? method;
      Uri? url;
      String? body;
      final api = MihomoApi(
        client: MockClient((req) async {
          method = req.method;
          url = req.url;
          body = req.body;
          return http.Response('', 204);
        }),
      );
      final ok = await api.changeProxy('🇭🇰 香港', 'HK-01');
      expect(ok, isTrue);
      expect(method, 'PUT');
      // Group name with non-ASCII must be percent-encoded in path.
      expect(url?.path, isNot(contains(' ')));
      expect(jsonDecode(body!), {'name': 'HK-01'});
    });
  });

  group('MihomoApi — response handling', () {
    test('200 → success record on healthSnapshot', () async {
      final api = MihomoApi(
        client: MockClient((_) async => http.Response('{"meta":true}', 200)),
      );
      final snap = await api.healthSnapshot();
      expect(snap.ok, isTrue);
      expect(snap.reason, 'ok');
    });

    test('non-200 → http_<code> reason', () async {
      final api = MihomoApi(
        client: MockClient((_) async => http.Response('unauthorized', 401)),
      );
      final snap = await api.healthSnapshot();
      expect(snap.ok, isFalse);
      expect(snap.reason, 'http_401');
    });

    test('SocketException maps to "socket"', () async {
      final api = MihomoApi(
        client: MockClient((_) async {
          throw const SocketException('connection refused');
        }),
      );
      final snap = await api.healthSnapshot();
      expect(snap.reason, 'socket');
    });

    test('TimeoutException maps to "timeout"', () async {
      final api = MihomoApi(
        client: MockClient((_) async {
          // Simulate a hang by returning a future that never resolves
          // until the api's own .timeout() fires.
          await Future<void>.delayed(const Duration(seconds: 5));
          return http.Response('{}', 200);
        }),
      );
      final snap = await api.healthSnapshot();
      expect(snap.reason, 'timeout');
    });

    test('non-200 from a data endpoint throws MihomoApiException', () async {
      final api = MihomoApi(
        client: MockClient((_) async => http.Response('boom', 500)),
      );
      await expectLater(
        api.getProxies(),
        throwsA(isA<MihomoApiException>()
            .having((e) => e.statusCode, 'status', 500)),
      );
    });
  });

  group('MihomoApi — retry behaviour', () {
    test('GET retries up to maxRetries on transient SocketException',
        () async {
      var attempt = 0;
      final api = MihomoApi(
        client: MockClient((_) async {
          attempt++;
          if (attempt < 3) {
            throw const SocketException('flaky');
          }
          return http.Response(jsonEncode({'recovered': true}), 200);
        }),
      );
      final result = await api.getProxies();
      expect(result['recovered'], isTrue);
      expect(attempt, 3, reason: 'two failed attempts + one success');
    });

    test('GET retries on 500 (transient) but not on 4xx (terminal)',
        () async {
      var fiveHundredHits = 0;
      final apiTransient = MihomoApi(
        client: MockClient((_) async {
          fiveHundredHits++;
          return http.Response('boom', 500);
        }),
      );
      await expectLater(apiTransient.getProxies(), throwsA(isA<MihomoApiException>()));
      // Default maxRetries is 3 — three 500s before bailing out.
      expect(fiveHundredHits, 3);

      var fourHundredHits = 0;
      final apiTerminal = MihomoApi(
        client: MockClient((_) async {
          fourHundredHits++;
          return http.Response('bad', 400);
        }),
      );
      await expectLater(apiTerminal.getProxies(), throwsA(isA<MihomoApiException>()));
      // 4xx is terminal — single attempt, no retry.
      expect(fourHundredHits, 1);
    });
  });

  group('MihomoApi — large-response decode', () {
    test('mid-size payload (~30 KB) decodes inline without throwing',
        () async {
      // Threshold lives in mihomo_api.dart and was raised to 256 KB in
      // v1.0.23-pre P1-C-fix after the 20 KB knee put the common
      // `/proxies` payload on the Isolate.run path on every fetch and
      // intermittently hung Android+Windows release builds. 30 KB is
      // representative of a real `/proxies` response; the test pins the
      // round-trip integrity of the inline path.
      final big = 'x' * 30 * 1024;
      final api = MihomoApi(
        client: MockClient((_) async => http.Response(
              jsonEncode({'big': big, 'meta': 1}),
              200,
            )),
      );
      final result = await api.getProxies();
      expect(result['big'], big);
      expect(result['meta'], 1);
    });

    test('small payload decodes inline, same outcome', () async {
      final api = MihomoApi(
        client: MockClient(
            (_) async => http.Response(jsonEncode({'small': 'ok'}), 200)),
      );
      final result = await api.getProxies();
      expect(result['small'], 'ok');
    });

    test('pathological payload (>256 KB) still decodes via isolate path',
        () async {
      // Above the threshold the response is offloaded to Isolate.run.
      // Verifies the isolate path still round-trips without throwing —
      // the path is retained for genuinely huge payloads, just no
      // longer triggered by the typical proxy graph.
      final huge = 'y' * 300 * 1024;
      final api = MihomoApi(
        client: MockClient((_) async => http.Response(
              jsonEncode({'huge': huge}),
              200,
            )),
      );
      final result = await api.getProxies();
      expect(result['huge'], huge);
    });
  });

  group('MihomoApi — body parsing', () {
    test('testDelay reads the `delay` field from the response', () async {
      final api = MihomoApi(
        client: MockClient((_) async =>
            http.Response(jsonEncode({'delay': 142}), 200)),
      );
      expect(await api.testDelay('node-1'), 142);
    });

    test('testDelay returns -1 on non-200 (timeout / unknown node)',
        () async {
      final api = MihomoApi(
        client: MockClient((_) async => http.Response('not found', 404)),
      );
      expect(await api.testDelay('node-1'), -1);
    });

    test('refreshAllRuleProviders aggregates ok/failed counts', () async {
      final calls = <String>[];
      final api = MihomoApi(
        client: MockClient((req) async {
          if (req.url.path == '/providers/rules') {
            return http.Response(
              jsonEncode({
                'providers': {
                  'a': {'name': 'a'},
                  'b': {'name': 'b'},
                  'c': {'name': 'c'},
                }
              }),
              200,
            );
          }
          // PUT /providers/rules/<name>: succeed for a/b, fail for c
          calls.add(req.url.path);
          if (req.url.path.endsWith('/c')) {
            return http.Response('boom', 500);
          }
          return http.Response('', 204);
        }),
      );
      final res = await api.refreshAllRuleProviders();
      expect(res.ok, 2);
      expect(res.failed, 1);
      expect(calls.length, 3);
    });
  });
}
