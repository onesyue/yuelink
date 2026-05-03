import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuelink/infrastructure/datasources/xboard/client.dart';
import 'package:yuelink/modules/yue_auth/providers/yue_auth_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Map<String, String> secureValues;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('yuelink_auth_login_');
    secureValues = <String, String>{};

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory' ||
                call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final key = call.arguments is Map
                ? (call.arguments as Map)['key'] as String?
                : null;
            switch (call.method) {
              case 'read':
                return key == null ? null : secureValues[key];
              case 'write':
                final value = (call.arguments as Map)['value'] as String?;
                if (key != null && value != null) secureValues[key] = value;
                return null;
              case 'delete':
                if (key != null) secureValues.remove(key);
                return null;
              case 'deleteAll':
                secureValues.clear();
                return null;
              case 'readAll':
                return secureValues;
            }
            return null;
          },
        );
  });

  tearDown(() {
    XBoardHttpClient.testClientFactory = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    tempDir.deleteSync(recursive: true);
  });

  test(
    'login returns after auth token without waiting for subscribe sync',
    () async {
      final subscribeGate = Completer<http.Response>();
      var loginCalls = 0;
      var subscribeCalls = 0;

      XBoardHttpClient.testClientFactory = ({int? proxyPort}) {
        return MockClient((request) async {
          if (request.url.path == '/api/v1/passport/auth/login') {
            loginCalls += 1;
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'auth_data': 'Bearer fast-token',
                  'token': 'raw-token',
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.path == '/api/v1/user/getSubscribe') {
            subscribeCalls += 1;
            return subscribeGate.future;
          }
          return http.Response('Not found', 404);
        });
      };

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final loginOk = await container
          .read(authProvider.notifier)
          .login('user@example.com', 'password')
          .timeout(const Duration(milliseconds: 500));

      expect(loginOk, isTrue);
      expect(container.read(authProvider).status, AuthStatus.loggedIn);
      expect(container.read(authProvider).token, 'Bearer fast-token');
      expect(loginCalls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        subscribeCalls,
        1,
        reason: 'subscribe refresh should still start, just not block login',
      );

      subscribeGate.complete(
        http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'email': 'user@example.com',
              // Deliberately omit subscribe_url so the background sync exits
              // before touching ProfileRepository / subscription download.
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    },
  );

  test(
    'stale subscribe 403 from previous login does not logout new session',
    () async {
      final firstSubscribeGate = Completer<http.Response>();
      var loginCalls = 0;
      var subscribeCalls = 0;

      XBoardHttpClient.testClientFactory = ({int? proxyPort}) {
        return MockClient((request) async {
          if (request.url.path == '/api/v1/passport/auth/login') {
            loginCalls += 1;
            final token = loginCalls == 1
                ? 'Bearer old-token'
                : 'Bearer new-token';
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {'auth_data': token},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.path == '/api/v1/user/getSubscribe') {
            subscribeCalls += 1;
            if (subscribeCalls == 1) return firstSubscribeGate.future;
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'email': 'user@example.com',
                  // Omit subscribe_url so this background sync exits quietly.
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('Not found', 404);
        });
      };

      final container = ProviderContainer(
        overrides: [
          preloadedAuthStateProvider.overrideWithValue(
            const AuthState(status: AuthStatus.loggedOut),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container
            .read(authProvider.notifier)
            .login('old@example.com', 'pw'),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(authProvider).token, 'Bearer old-token');
      expect(subscribeCalls, 1);

      expect(
        await container
            .read(authProvider.notifier)
            .login('new@example.com', 'pw'),
        isTrue,
      );
      expect(container.read(authProvider).token, 'Bearer new-token');

      firstSubscribeGate.complete(
        http.Response(
          jsonEncode({'message': 'old session expired'}),
          403,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(authProvider).status, AuthStatus.loggedIn);
      expect(container.read(authProvider).token, 'Bearer new-token');
    },
  );
}
