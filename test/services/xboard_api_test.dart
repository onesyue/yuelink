import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:yuelink/infrastructure/datasources/xboard/client.dart';
import 'package:yuelink/infrastructure/datasources/xboard/index.dart';

void main() {
  const baseUrl = 'https://example.com';
  late XBoardApi api;

  setUp(() {
    api = XBoardApi(baseUrl: baseUrl);
  });

  tearDown(() {
    XBoardHttpClient.testClientFactory = null;
  });

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Install a [MockClient] that returns [body] with [statusCode] for all requests.
  void mockResponse(String body, {int statusCode = 200}) {
    XBoardHttpClient.testClientFactory = () => MockClient((_) async =>
        http.Response(body, statusCode,
            headers: {'content-type': 'application/json; charset=utf-8'}));
  }

  // ====================================================================
  // Login API
  // ====================================================================

  group('login', () {
    test('success — returns token from auth_data', () async {
      mockResponse(jsonEncode({
        'status': 'success',
        'data': {
          'auth_data': 'Bearer abc123',
          'token': 'raw_token',
        },
      }));

      final result = await api.login('user@test.com', 'pass');
      expect(result.token, 'Bearer abc123');
      expect(result.authData, 'Bearer abc123');
    });

    test('success — falls back to token when auth_data empty', () async {
      mockResponse(jsonEncode({
        'status': 'success',
        'data': {
          'auth_data': '',
          'token': 'raw_token',
        },
      }));

      final result = await api.login('user@test.com', 'pass');
      expect(result.token, 'raw_token');
    });

    test('failure — XBoard returns status:fail', () async {
      mockResponse(jsonEncode({
        'status': 'fail',
        'message': '邮箱或密码错误',
      }));

      expect(
        () => api.login('user@test.com', 'wrong'),
        throwsA(isA<XBoardApiException>().having(
          (e) => e.message,
          'message',
          '邮箱或密码错误',
        )),
      );
    });

    test('failure — HTTP 500 retries and throws', () async {
      var attempts = 0;
      XBoardHttpClient.testClientFactory = () => MockClient((_) async {
            attempts++;
            return http.Response('Internal Server Error', 500);
          });

      await expectLater(
        () => api.login('user@test.com', 'pass'),
        throwsA(isA<XBoardApiException>().having(
          (e) => e.statusCode,
          'statusCode',
          500,
        )),
      );
      expect(attempts, 3); // all 3 retries exhausted
    });

    test('failure — empty token in response', () async {
      mockResponse(jsonEncode({
        'status': 'success',
        'data': {
          'auth_data': '',
          'token': '',
        },
      }));

      expect(
        () => api.login('user@test.com', 'pass'),
        throwsA(isA<XBoardApiException>().having(
          (e) => e.message,
          'message',
          contains('No token'),
        )),
      );
    });
  });

  // ====================================================================
  // Subscribe Data API
  // ====================================================================

  group('getSubscribeData', () {
    test('success — parses profile and subscribe URL', () async {
      mockResponse(jsonEncode({
        'status': 'success',
        'data': {
          'plan_id': 1,
          'plan': {'name': '月付套餐', 'device_limit': 3},
          'transfer_enable': 107374182400, // 100 GB
          'u': 1073741824, // 1 GB upload
          'd': 5368709120, // 5 GB download
          'expired_at': 1735689600,
          'email': 'user@test.com',
          'uuid': 'abc-123',
          'online_count': 1,
          'subscribe_url': 'https://sub.example.com/api/v1/client/subscribe?token=xyz',
        },
      }));

      final data = await api.getSubscribeData('Bearer token');
      expect(data.subscribeUrl, contains('subscribe'));
      expect(data.profile.planName, '月付套餐');
      expect(data.profile.transferEnable, 107374182400);
      expect(data.profile.uploadUsed, 1073741824);
      expect(data.profile.downloadUsed, 5368709120);
      expect(data.profile.deviceLimit, 3);
    });

    test('failure — no subscribe_url in response', () async {
      mockResponse(jsonEncode({
        'status': 'success',
        'data': {
          'plan_id': 1,
          'email': 'user@test.com',
          // subscribe_url missing
        },
      }));

      expect(
        () => api.getSubscribeData('Bearer token'),
        throwsA(isA<XBoardApiException>().having(
          (e) => e.message,
          'message',
          contains('No subscribe URL'),
        )),
      );
    });

    test('failure — status:fail (e.g., token expired)', () async {
      mockResponse(jsonEncode({
        'status': 'fail',
        'message': 'Token expired',
      }));

      expect(
        () => api.getSubscribeData('Bearer expired_token'),
        throwsA(isA<XBoardApiException>().having(
          (e) => e.message,
          'message',
          'Token expired',
        )),
      );
    });
  });

  // ====================================================================
  // UserProfile model
  // ====================================================================

  group('UserProfile', () {
    test('handles PHP tinyint(1) bool conversion', () {
      final profile = UserProfile.fromJson({
        'plan_id': true, // tinyint(1) → bool
        'transfer_enable': 100.0, // sometimes double
        'u': 50,
        'd': 30,
      });
      expect(profile.planId, 1);
      expect(profile.transferEnable, 100);
      expect(profile.uploadUsed, 50);
      expect(profile.downloadUsed, 30);
    });

    test('extracts plan name from nested plan object', () {
      final profile = UserProfile.fromJson({
        'plan': {'name': '年付VIP', 'device_limit': 5},
      });
      expect(profile.planName, '年付VIP');
      expect(profile.deviceLimit, 5);
    });

    test('usagePercent calculation', () {
      final profile = UserProfile.fromJson({
        'transfer_enable': 1000,
        'u': 300,
        'd': 200,
      });
      expect(profile.usagePercent, closeTo(0.5, 0.001));
      expect(profile.remaining, 500);
    });

    test('usagePercent null when transferEnable is 0', () {
      final profile = UserProfile.fromJson({
        'transfer_enable': 0,
        'u': 0,
        'd': 0,
      });
      expect(profile.usagePercent, isNull);
    });

    test('toJson round-trip', () {
      final original = UserProfile(
        planId: 1,
        planName: 'Test',
        transferEnable: 1000,
        uploadUsed: 100,
        downloadUsed: 200,
        email: 'a@b.com',
      );
      final restored = UserProfile.fromJson(original.toJson());
      expect(restored.planId, original.planId);
      expect(restored.planName, original.planName);
      expect(restored.transferEnable, original.transferEnable);
      expect(restored.uploadUsed, original.uploadUsed);
      expect(restored.downloadUsed, original.downloadUsed);
      expect(restored.email, original.email);
    });
  });

  // ====================================================================
  // _assertSuccess
  // ====================================================================

  group('_assertSuccess (via API calls)', () {
    test('status: false triggers exception', () async {
      mockResponse(jsonEncode({
        'status': false,
        'message': 'Unauthorized',
      }));

      expect(
        () => api.login('a@b.com', 'p'),
        throwsA(isA<XBoardApiException>().having(
          (e) => e.message,
          'message',
          'Unauthorized',
        )),
      );
    });

    test('status: 0 triggers exception', () async {
      mockResponse(jsonEncode({
        'status': 0,
        'error': 'Rate limited',
      }));

      expect(
        () => api.login('a@b.com', 'p'),
        throwsA(isA<XBoardApiException>().having(
          (e) => e.message,
          'message',
          'Rate limited',
        )),
      );
    });

    test('fallback message when no message or error field', () async {
      mockResponse(jsonEncode({
        'status': 'fail',
      }));

      expect(
        () => api.login('a@b.com', 'p'),
        throwsA(isA<XBoardApiException>().having(
          (e) => e.message,
          'message',
          'Request failed',
        )),
      );
    });
  });

  // ====================================================================
  // Retry logic (_withRetry)
  // ====================================================================

  group('retry logic', () {
    test('retries on SocketException (transient)', () async {
      var attempts = 0;
      XBoardHttpClient.testClientFactory = () => MockClient((_) async {
            attempts++;
            if (attempts < 3) throw const SocketException('Connection refused');
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'auth_data': 'Bearer ok',
                  'token': 'ok',
                },
              }),
              200,
            );
          });

      final result = await api.login('a@b.com', 'p');
      expect(result.token, 'Bearer ok');
      expect(attempts, 3); // 2 failures + 1 success
    });

    test('does NOT retry on XBoardApiException with status < 500', () async {
      var attempts = 0;
      XBoardHttpClient.testClientFactory = () => MockClient((_) async {
            attempts++;
            return http.Response('{"status":"fail","message":"Bad"}', 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          });

      await expectLater(
        () => api.login('a@b.com', 'p'),
        throwsA(isA<XBoardApiException>()),
      );
      // XBoardApiException from _assertSuccess has statusCode=0 (< 500),
      // so it should NOT be retried.
      expect(attempts, 1);
    });

    test('retries on HTTP 500 (transient)', () async {
      var attempts = 0;
      XBoardHttpClient.testClientFactory = () => MockClient((_) async {
            attempts++;
            if (attempts < 3) return http.Response('Server Error', 500);
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'auth_data': 'Bearer recovered',
                  'token': 'x',
                },
              }),
              200,
            );
          });

      final result = await api.login('a@b.com', 'p');
      expect(result.token, 'Bearer recovered');
      expect(attempts, 3);
    });

    test('exhausts all retries and rethrows last error', () async {
      var attempts = 0;
      XBoardHttpClient.testClientFactory = () => MockClient((_) async {
            attempts++;
            throw const SocketException('Always fails');
          });

      await expectLater(
        () => api.login('a@b.com', 'p'),
        throwsA(isA<SocketException>()),
      );
      expect(attempts, 3); // _maxRetries = 3
    });
  });

  // ====================================================================
  // XBoardApiException
  // ====================================================================

  group('XBoardApiException', () {
    test('extracts message from JSON body', () {
      final e = XBoardApiException(400, '{"message":"Invalid email"}');
      expect(e.message, 'Invalid email');
      expect(e.statusCode, 400);
    });

    test('returns raw body when not JSON', () {
      final e = XBoardApiException(500, 'Internal Server Error');
      expect(e.message, 'Internal Server Error');
    });

    test('toString includes status code and message', () {
      final e = XBoardApiException(403, 'Forbidden');
      expect(e.toString(), 'XBoardApiException(403): Forbidden');
    });
  });

  // ====================================================================
  // LoginResponse
  // ====================================================================

  group('LoginResponse', () {
    test('prefers auth_data over token', () {
      final lr = LoginResponse.fromJson({
        'auth_data': 'Bearer X',
        'token': 'raw',
      });
      expect(lr.token, 'Bearer X');
      expect(lr.authData, 'Bearer X');
    });

    test('throws when both fields empty', () {
      expect(
        () => LoginResponse.fromJson({'auth_data': '', 'token': ''}),
        throwsA(isA<XBoardApiException>()),
      );
    });
  });
}
