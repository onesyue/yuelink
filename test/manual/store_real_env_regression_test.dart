import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/storage/settings_service.dart';
import 'package:yuelink/domain/store/purchase_state.dart';
import 'package:yuelink/domain/store/store_plan.dart';
import 'package:yuelink/infrastructure/store/payment_launcher.dart';
import 'package:yuelink/modules/store/purchase_notifier.dart';
import 'package:yuelink/modules/store/store_providers.dart';
import 'package:yuelink/modules/yue_auth/providers/yue_auth_providers.dart';
import 'package:yuelink/shared/telemetry.dart';

const _kPathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

bool get _isConfigured => [
  'STORE_REAL_EMAIL',
  'STORE_REAL_PASSWORD',
  'STORE_REAL_COUPON',
  'STORE_DB_SSH_HOST',
  'STORE_PANEL_SSH_HOST',
  'STORE_SSH_PASSWORD',
].every((key) => (Platform.environment[key] ?? '').isNotEmpty);

String _env(String key, {String? fallback}) {
  final value = Platform.environment[key];
  if (value != null && value.isNotEmpty) return value;
  if (fallback != null) return fallback;
  throw StateError('Missing env: $key');
}

String _shQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

class _FakePaymentLauncher implements PaymentLauncher {
  final launchedUrls = <String>[];

  @override
  Future<bool> launch(String url) async {
    launchedUrls.add(url);
    return true;
  }

  void clear() => launchedUrls.clear();
}

Future<String> _run(List<String> command) async {
  final result = await Process.run(command.first, command.sublist(1));
  if (result.exitCode != 0) {
    throw StateError(
      'Command failed (${result.exitCode}): ${command.join(' ')}\n'
      'stdout=${result.stdout}\n'
      'stderr=${result.stderr}',
    );
  }
  return result.stdout.toString().trim();
}

Future<String> _remotePsql(String sql) async {
  final host = _env('STORE_DB_SSH_HOST');
  final password = _env('STORE_SSH_PASSWORD');
  final sqlBase64 = base64Encode(utf8.encode(sql));
  final remoteCommand =
      'echo ${_shQuote(sqlBase64)} | base64 -d | '
      'PGPASSWORD=${_shQuote(password)} '
      "psql -P pager=off -h 127.0.0.1 -U root -d 'yue-to' -Atf -";
  return _run([
    'sshpass',
    '-p',
    password,
    'ssh',
    '-o',
    'StrictHostKeyChecking=no',
    'root@$host',
    remoteCommand,
  ]);
}

Future<void> _remoteOpenOrder(String tradeNo) async {
  final host = _env('STORE_PANEL_SSH_HOST');
  final password = _env('STORE_SSH_PASSWORD');
  final php =
      '''
<?php
require "/www/vendor/autoload.php";
\$app = require "/www/bootstrap/app.php";
\$kernel = \$app->make(Illuminate\\Contracts\\Console\\Kernel::class);
\$kernel->bootstrap();
\$order = App\\Models\\Order::where("trade_no", "$tradeNo")->firstOrFail();
(new App\\Services\\OrderService(\$order))->open();
echo "ok";
''';
  final phpBase64 = base64Encode(utf8.encode(php));
  final remoteCommand =
      'echo ${_shQuote(phpBase64)} | base64 -d | '
      'docker exec -i yue-to-web-1 php';
  final output = await _run([
    'sshpass',
    '-p',
    password,
    'ssh',
    '-o',
    'StrictHostKeyChecking=no',
    'root@$host',
    remoteCommand,
  ]);
  expect(output, contains('ok'));
}

Future<void> _cleanupOrders(String email) async {
  final quotedEmail = email.replaceAll("'", "''");
  await _remotePsql('''
delete from v2_order
where user_id = (select id from v2_user where email = '$quotedEmail');
''');
}

Future<String> _loginToken() async {
  final api = XBoardApi(
    baseUrl: _env('STORE_API_HOST', fallback: 'http://66.55.76.208:8001'),
  );
  final login = await api.login(
    _env('STORE_REAL_EMAIL'),
    _env('STORE_REAL_PASSWORD'),
  );
  return login.authData ?? login.token;
}

Future<int> _enableTelemetry() async {
  Telemetry.setEnabled(true);
  await Future<void>.delayed(Duration.zero);
  await SettingsService.flush();
  return Telemetry.recentEvents().length;
}

List<String> _telemetryEventsSince(int cursor) {
  return Telemetry.recentEvents()
      .skip(cursor)
      .map((event) => event['event'] as String)
      .toList();
}

ProviderContainer _container({
  required String token,
  required _FakePaymentLauncher launcher,
}) {
  return ProviderContainer(
    overrides: [
      preloadedAuthStateProvider.overrideWithValue(
        AuthState(status: AuthStatus.loggedIn, token: token),
      ),
      paymentLauncherProvider.overrideWithValue(launcher),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync(
    'yuelink_store_real_env_',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kPathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return tempDir.path;
          }
          return null;
        });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kPathProviderChannel, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('runs R1-R5 against real XBoard store environment', () async {
    final email = _env('STORE_REAL_EMAIL');
    final coupon = _env('STORE_REAL_COUPON');
    await _cleanupOrders(email);

    final token = await _loginToken();
    final api = XBoardApi(
      baseUrl: _env('STORE_API_HOST', fallback: 'http://66.55.76.208:8001'),
    );
    final launcher = _FakePaymentLauncher();
    final container = _container(token: token, launcher: launcher);
    addTearDown(container.dispose);

    final notifier = container.read(purchaseProvider.notifier);
    final repo = container.read(storeRepositoryProvider)!;

    final telemetryCursor = await _enableTelemetry();

    // R1: free purchase success via 100% coupon.
    await notifier.purchase(
      planId: 2,
      period: PlanPeriod.monthly,
      couponCode: coupon,
    );
    final r1State = container.read(purchaseProvider);
    expect(r1State, isA<PurchaseSuccess>());
    final r1TradeNo = (r1State as PurchaseSuccess).order.tradeNo;
    final r1Order = await repo.fetchOrderDetail(r1TradeNo);
    expect(r1Order.status.isSuccess, isTrue);
    final subAfterR1 = await api.getSubscribeData(token);
    expect(subAfterR1.profile.planId, 2);

    // R4 + pending precondition for R3: create a pending order, then reuse it.
    launcher.clear();
    notifier.reset();
    await notifier.purchase(planId: 3, period: PlanPeriod.monthly, methodId: 1);
    final pendingState = container.read(purchaseProvider);
    expect(pendingState, isA<PurchaseAwaitingPayment>());
    final pendingTradeNo = (pendingState as PurchaseAwaitingPayment).tradeNo;
    expect(launcher.launchedUrls, isNotEmpty);

    final orderCountBeforeReuse = (await repo.fetchOrders(
      page: 1,
    )).orders.length;
    launcher.clear();
    notifier.reset();
    await notifier.purchase(planId: 3, period: PlanPeriod.monthly, methodId: 1);
    final reusedState = container.read(purchaseProvider);
    expect(reusedState, isA<PurchaseAwaitingPayment>());
    expect((reusedState as PurchaseAwaitingPayment).tradeNo, pendingTradeNo);
    final orderCountAfterReuse = (await repo.fetchOrders(
      page: 1,
    )).orders.length;
    expect(orderCountAfterReuse, orderCountBeforeReuse);

    // R3: cancel pending order.
    await notifier.cancelCurrentOrder();
    final cancelled = await repo.fetchOrderDetail(pendingTradeNo);
    expect(cancelled.status.name, 'cancelled');

    // R2: pending order completed externally, then poll succeeds.
    launcher.clear();
    notifier.reset();
    await notifier.purchase(planId: 4, period: PlanPeriod.monthly, methodId: 1);
    final r2Pending = container.read(purchaseProvider);
    expect(r2Pending, isA<PurchaseAwaitingPayment>());
    final r2TradeNo = (r2Pending as PurchaseAwaitingPayment).tradeNo;
    await _remoteOpenOrder(r2TradeNo);
    await notifier.pollOrderResult(
      r2TradeNo,
      maxAttempts: 3,
      interval: const Duration(milliseconds: 200),
    );
    final r2Final = container.read(purchaseProvider);
    expect(r2Final, isA<PurchaseSuccess>());
    final r2Order = await repo.fetchOrderDetail(r2TradeNo);
    expect(r2Order.status.isSuccess, isTrue);

    // R5: logout clears auth + store access.
    await container.read(authProvider.notifier).logout();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(authProvider).status, AuthStatus.loggedOut);
    expect(container.read(storeRepositoryProvider), isNull);
    container.invalidate(orderHistoryProvider);
    expect(await container.read(orderHistoryProvider.future), isEmpty);

    // Telemetry preview backing data: real events are present in the buffer.
    final events = _telemetryEventsSince(telemetryCursor);
    expect(events, contains(TelemetryEvents.purchaseStart));
    expect(events, contains(TelemetryEvents.purchaseSuccess));
    expect(events, contains(TelemetryEvents.pendingOrderReuse));
    expect(events, contains(TelemetryEvents.orderCancel));
    expect(Telemetry.recentEvents(), isNotEmpty);
  }, skip: !_isConfigured);
}
