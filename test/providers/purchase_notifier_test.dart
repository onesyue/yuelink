import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/storage/settings_service.dart';
import 'package:yuelink/domain/store/coupon_result.dart';
import 'package:yuelink/domain/store/payment_method.dart';
import 'package:yuelink/domain/store/payment_outcome.dart';
import 'package:yuelink/domain/store/purchase_state.dart';
import 'package:yuelink/domain/store/store_error.dart';
import 'package:yuelink/domain/store/store_order.dart';
import 'package:yuelink/domain/store/store_plan.dart';
import 'package:yuelink/infrastructure/store/payment_launcher.dart';
import 'package:yuelink/infrastructure/store/store_repository.dart';
import 'package:yuelink/modules/store/purchase_notifier.dart';
import 'package:yuelink/modules/store/store_providers.dart';
import 'package:yuelink/shared/telemetry.dart';
// ignore: unused_import (AuthState used in overrides)
import 'package:yuelink/modules/yue_auth/providers/yue_auth_providers.dart';

// ── Fake StoreRepository ─────────────────────────────────────────────────────

class FakeStoreRepository implements StoreRepository {
  String? createOrderResult;
  PaymentOutcome? checkoutOutcome;
  StoreOrder? orderDetailResult;
  List<StorePlan>? plansResult;
  List<PaymentMethod>? paymentMethodsResult;
  OrderListResult? ordersResult;
  CouponResult? couponResult;
  bool cancelOrderCalled = false;
  Exception? createOrderError;
  Exception? checkoutError;
  Exception? orderDetailError;

  /// When set, fetchOrderDetail awaits this completer instead of returning
  /// [orderDetailResult]. Lets tests deterministically pause inside the
  /// poll loop and inject reset/cancel before the await resumes.
  Completer<StoreOrder>? orderDetailGate;

  /// When set, cancelOrder awaits this completer before returning. Lets
  /// tests pause cancelCurrentOrder mid-flight to verify the post-await
  /// generation guard.
  Completer<void>? cancelGate;

  @override
  Future<String> createOrder({
    required int planId,
    required PlanPeriod period,
    String? couponCode,
  }) async {
    if (createOrderError != null) throw createOrderError!;
    return createOrderResult ?? 'TRADE_001';
  }

  @override
  Future<PaymentOutcome> checkoutOrder(String tradeNo, {int? methodId}) async {
    if (checkoutError != null) throw checkoutError!;
    return checkoutOutcome ??
        const AwaitingExternalPayment('https://pay.example.com');
  }

  @override
  Future<StoreOrder> fetchOrderDetail(String tradeNo) async {
    if (orderDetailGate != null) {
      return orderDetailGate!.future;
    }
    if (orderDetailError != null) throw orderDetailError!;
    return orderDetailResult ?? _pendingOrder(tradeNo);
  }

  @override
  Future<List<StorePlan>> fetchPlans() async {
    return plansResult ?? [];
  }

  @override
  Future<List<PaymentMethod>> fetchPaymentMethods() async {
    return paymentMethodsResult ?? [];
  }

  @override
  Future<void> cancelOrder(String tradeNo) async {
    cancelOrderCalled = true;
    if (cancelGate != null) {
      await cancelGate!.future;
    }
  }

  @override
  Future<CouponResult> checkCoupon(String code, int planId) async {
    return couponResult ??
        const CouponResult(id: 1, code: 'TEST', type: 1, value: 100);
  }

  @override
  Future<OrderListResult> fetchOrders({int page = 1}) async {
    return ordersResult ?? const OrderListResult(orders: [], hasMore: false);
  }

  @override
  Future<StoreOrder?> fetchPendingOrderForPlan(
    int planId, {
    int maxPages = 5,
  }) async {
    final result = await fetchOrders();
    return result.orders
        .where((o) => o.planId == planId && o.status == OrderStatus.pending)
        .firstOrNull;
  }

  static StoreOrder _pendingOrder(String tradeNo) => StoreOrder(
    tradeNo: tradeNo,
    planId: 1,
    period: 'month_price',
    totalAmount: 1000,
    status: OrderStatus.pending,
    createdAt: 1700000000,
    updatedAt: 1700000000,
  );

  static StoreOrder completedOrder(String tradeNo) => StoreOrder(
    tradeNo: tradeNo,
    planId: 1,
    period: 'month_price',
    totalAmount: 1000,
    status: OrderStatus.completed,
    createdAt: 1700000000,
    updatedAt: 1700000000,
  );

  static StoreOrder cancelledOrder(String tradeNo) => StoreOrder(
    tradeNo: tradeNo,
    planId: 1,
    period: 'month_price',
    totalAmount: 1000,
    status: OrderStatus.cancelled,
    createdAt: 1700000000,
    updatedAt: 1700000000,
  );
}

// ── Fake PaymentLauncher ──────────────────────────────────────────────────────

class FakePaymentLauncher implements PaymentLauncher {
  bool shouldSucceed;
  final List<String> launched = [];

  FakePaymentLauncher({this.shouldSucceed = true});

  @override
  Future<bool> launch(String url) async {
    launched.add(url);
    return shouldSucceed;
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

ProviderContainer _createContainer(
  FakeStoreRepository repo, {
  FakePaymentLauncher? launcher,
}) {
  final fakeLauncher = launcher ?? FakePaymentLauncher();
  return ProviderContainer(
    overrides: [
      storeRepositoryProvider.overrideWithValue(repo),
      paymentLauncherProvider.overrideWithValue(fakeLauncher),
      preloadedAuthStateProvider.overrideWithValue(
        const AuthState(status: AuthStatus.guest),
      ),
    ],
  );
}

List<String> _telemetryEventsSince(int cursor) {
  return Telemetry.recentEvents()
      .skip(cursor)
      .map((event) => event['event'] as String)
      .toList();
}

Future<int> _enableTelemetry() async {
  Telemetry.setEnabled(true);
  await Future<void>.delayed(Duration.zero);
  await SettingsService.flush();
  return Telemetry.recentEvents().length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final telemetryDir = Directory.systemTemp.createTempSync(
    'yuelink_telemetry_test_',
  );
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return telemetryDir.path;
          }
          return null;
        });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (telemetryDir.existsSync()) {
      telemetryDir.deleteSync(recursive: true);
    }
  });

  group('PurchaseNotifier', () {
    test('initial state is PurchaseIdle', () {
      final repo = FakeStoreRepository();
      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final state = container.read(purchaseProvider);
      expect(state, isA<PurchaseIdle>());
    });

    test('purchase transitions to AwaitingPayment on success', () async {
      final repo = FakeStoreRepository();
      repo.createOrderResult = 'TRADE_123';
      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com/123',
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);
      await notifier.purchase(
        planId: 1,
        period: PlanPeriod.monthly,
        methodId: 1,
      );

      final state = container.read(purchaseProvider);
      expect(state, isA<PurchaseAwaitingPayment>());

      if (state is PurchaseAwaitingPayment) {
        expect(state.tradeNo, 'TRADE_123');
        expect(state.paymentUrl, 'https://pay.example.com/123');
      }
    });

    test('purchase transitions to Failed when launcher fails', () async {
      final repo = FakeStoreRepository();
      repo.createOrderResult = 'TRADE_456';
      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com/456',
      );

      final launcher = FakePaymentLauncher(shouldSucceed: false);
      final container = _createContainer(repo, launcher: launcher);
      addTearDown(container.dispose);

      await container
          .read(purchaseProvider.notifier)
          .purchase(planId: 1, period: PlanPeriod.monthly, methodId: 1);

      final state = container.read(purchaseProvider);
      expect(state, isA<PurchaseFailed>());
    });

    test('purchase transitions to Failed on createOrder error', () async {
      final repo = FakeStoreRepository();
      repo.createOrderError = Exception('Plan sold out');

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);
      await notifier.purchase(planId: 1, period: PlanPeriod.monthly);

      final state = container.read(purchaseProvider);
      expect(state, isA<PurchaseFailed>());
      expect((state as PurchaseFailed).message, contains('Plan sold out'));
    });

    test(
      'purchase with free plan (FreeActivated) polls and succeeds',
      () async {
        final repo = FakeStoreRepository();
        repo.createOrderResult = 'FREE_001';
        repo.checkoutOutcome = const FreeActivated();
        repo.orderDetailResult = FakeStoreRepository.completedOrder('FREE_001');

        final container = _createContainer(repo);
        addTearDown(container.dispose);

        final notifier = container.read(purchaseProvider.notifier);
        await notifier.purchase(planId: 1, period: PlanPeriod.monthly);

        final state = container.read(purchaseProvider);
        expect(state, isA<PurchaseSuccess>());
        expect((state as PurchaseSuccess).order.tradeNo, 'FREE_001');
      },
    );

    test('purchase rejects double submit', () async {
      final repo = FakeStoreRepository();
      repo.createOrderError = null;

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);

      // Manually set loading state to simulate in-progress purchase
      notifier.purchase(planId: 1, period: PlanPeriod.monthly);
      // Second call should be ignored (state is already Loading)
      await notifier.purchase(planId: 2, period: PlanPeriod.monthly);

      // Only one order should have been created (first call)
    });

    test('pollOrderResult detects completed order', () async {
      final repo = FakeStoreRepository();
      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com',
      );
      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);
      await notifier.payExistingOrder(tradeNo: 'POLL_001', methodId: 1);
      expect(container.read(purchaseProvider), isA<PurchaseAwaitingPayment>());

      // Now poll with completed order
      repo.orderDetailResult = FakeStoreRepository.completedOrder('POLL_001');
      await notifier.pollOrderResult(
        'POLL_001',
        maxAttempts: 2,
        interval: Duration.zero,
      );

      final state = container.read(purchaseProvider);
      expect(state, isA<PurchaseSuccess>());
    });

    test('pollOrderResult detects cancelled order', () async {
      final repo = FakeStoreRepository();
      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com',
      );
      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);
      await notifier.payExistingOrder(tradeNo: 'CANCEL_001', methodId: 1);
      expect(container.read(purchaseProvider), isA<PurchaseAwaitingPayment>());

      // Now poll with cancelled order
      repo.orderDetailResult = FakeStoreRepository.cancelledOrder('CANCEL_001');
      await notifier.pollOrderResult(
        'CANCEL_001',
        maxAttempts: 2,
        interval: Duration.zero,
      );

      final state = container.read(purchaseProvider);
      expect(state, isA<PurchaseFailed>());
      expect((state as PurchaseFailed).message, contains('取消'));
    });

    test('pollOrderResult exhausts attempts and reverts to awaiting', () async {
      final repo = FakeStoreRepository();
      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);

      // Put notifier into AwaitingPayment state via payExistingOrder with URL outcome
      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com',
      );
      await notifier.payExistingOrder(tradeNo: 'PENDING_001', methodId: 1);

      // Now state should be AwaitingPayment
      expect(container.read(purchaseProvider), isA<PurchaseAwaitingPayment>());

      // Poll with pending order detail (default) — will exhaust attempts
      repo.checkoutOutcome = null;
      await notifier.pollOrderResult(
        'PENDING_001',
        maxAttempts: 2,
        interval: Duration.zero,
      );

      final state = container.read(purchaseProvider);
      expect(state, isA<PurchaseAwaitingPayment>());
      expect((state as PurchaseAwaitingPayment).tradeNo, 'PENDING_001');
    });

    test('pollOrderResult rejects concurrent calls', () async {
      final repo = FakeStoreRepository();
      repo.orderDetailResult = null; // keep pending

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);

      // Start two polls concurrently — second should be rejected by _polling guard
      final f1 = notifier.pollOrderResult(
        'RACE_001',
        maxAttempts: 1,
        interval: Duration.zero,
      );
      final f2 = notifier.pollOrderResult(
        'RACE_001',
        maxAttempts: 1,
        interval: Duration.zero,
      );
      await Future.wait([f1, f2]);
      // No crash = success. The _polling flag prevents double execution.
    });

    test('payExistingOrder uses existing tradeNo (FreeActivated)', () async {
      final repo = FakeStoreRepository();
      repo.checkoutOutcome = const FreeActivated();
      repo.orderDetailResult = FakeStoreRepository.completedOrder(
        'EXISTING_001',
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);
      await notifier.payExistingOrder(tradeNo: 'EXISTING_001', methodId: 1);

      final state = container.read(purchaseProvider);
      expect(state, isA<PurchaseSuccess>());
    });

    test('cancelCurrentOrder transitions to Idle', () async {
      final repo = FakeStoreRepository();
      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com',
      );
      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);

      // Set up awaiting payment state via payExistingOrder
      await notifier.payExistingOrder(tradeNo: 'CANCEL_ME', methodId: 1);
      expect(container.read(purchaseProvider), isA<PurchaseAwaitingPayment>());

      // Now cancel
      await notifier.cancelCurrentOrder();

      final state = container.read(purchaseProvider);
      expect(state, isA<PurchaseIdle>());
      expect(repo.cancelOrderCalled, isTrue);
    });

    test(
      'cancelOrderFromHistory calls repository and refreshes history',
      () async {
        final repo = FakeStoreRepository();
        repo.ordersResult = OrderListResult(
          orders: [FakeStoreRepository.completedOrder('BEFORE')],
          hasMore: false,
        );

        final container = _createContainer(repo);
        addTearDown(container.dispose);

        final sub = container.listen<List<StoreOrder>?>(
          orderHistoryProvider.select((value) => value.value),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);

        await container.read(orderHistoryProvider.future);

        repo.ordersResult = OrderListResult(
          orders: [FakeStoreRepository.completedOrder('AFTER')],
          hasMore: false,
        );

        await container
            .read(purchaseProvider.notifier)
            .cancelOrderFromHistory('CANCEL_HISTORY');

        final orders = await container.read(orderHistoryProvider.future);
        expect(repo.cancelOrderCalled, isTrue);
        expect(orders.first.tradeNo, 'AFTER');
      },
    );

    test('validateCoupon delegates to repository', () async {
      final repo = FakeStoreRepository();
      repo.couponResult = const CouponResult(
        id: 9,
        code: 'SAVE',
        type: 1,
        value: 250,
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final result = await container
          .read(purchaseProvider.notifier)
          .validateCoupon('SAVE', 1);

      expect(result.code, 'SAVE');
      expect(result.value, 250);
    });

    test('reset returns to PurchaseIdle', () {
      final repo = FakeStoreRepository();
      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);
      notifier.reset();

      expect(container.read(purchaseProvider), isA<PurchaseIdle>());
    });

    test('purchase without login returns PurchaseFailed', () async {
      final fakeLauncher = FakePaymentLauncher();
      final container = ProviderContainer(
        overrides: [
          storeRepositoryProvider.overrideWithValue(null),
          paymentLauncherProvider.overrideWithValue(fakeLauncher),
          preloadedAuthStateProvider.overrideWithValue(
            const AuthState(status: AuthStatus.loggedOut),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);
      await notifier.purchase(planId: 1, period: PlanPeriod.monthly);

      final state = container.read(purchaseProvider);
      expect(state, isA<PurchaseFailed>());
      expect((state as PurchaseFailed).message, '未登录');
    });

    test('purchase emits start and success telemetry', () async {
      final cursor = await _enableTelemetry();

      final repo = FakeStoreRepository();
      repo.createOrderResult = 'FREE_002';
      repo.checkoutOutcome = const FreeActivated();
      repo.orderDetailResult = FakeStoreRepository.completedOrder('FREE_002');

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(purchaseProvider.notifier)
          .purchase(planId: 1, period: PlanPeriod.monthly);

      final events = _telemetryEventsSince(cursor);
      expect(events, contains(TelemetryEvents.purchaseStart));
      expect(events, contains(TelemetryEvents.purchaseSuccess));
    });

    test('purchase emits pendingOrderReuse telemetry', () async {
      final cursor = await _enableTelemetry();

      final repo = FakeStoreRepository();
      repo.ordersResult = OrderListResult(
        orders: [FakeStoreRepository._pendingOrder('REUSE_001')],
        hasMore: false,
      );
      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com/reuse',
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      await container.read(orderHistoryProvider.future);
      await container
          .read(purchaseProvider.notifier)
          .purchase(planId: 1, period: PlanPeriod.monthly);

      expect(
        _telemetryEventsSince(cursor),
        contains(TelemetryEvents.pendingOrderReuse),
      );
    });

    test('purchase emits purchaseFail telemetry', () async {
      final cursor = await _enableTelemetry();

      final repo = FakeStoreRepository();
      repo.createOrderError = Exception('payment provider down');

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(purchaseProvider.notifier)
          .purchase(planId: 1, period: PlanPeriod.monthly);

      expect(
        _telemetryEventsSince(cursor),
        contains(TelemetryEvents.purchaseFail),
      );
    });

    test('cancelCurrentOrder emits orderCancel telemetry', () async {
      final cursor = await _enableTelemetry();

      final repo = FakeStoreRepository();
      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com/cancel',
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);
      await notifier.payExistingOrder(tradeNo: 'CANCEL_EVENT', methodId: 1);
      await notifier.cancelCurrentOrder();

      expect(
        _telemetryEventsSince(cursor),
        contains(TelemetryEvents.orderCancel),
      );
    });

    // ── Bug-fix regression tests (S0 PR1) ──────────────────────────────────

    test(
      'reset mid-poll: stale fetchOrderDetail success does not clobber Idle',
      () async {
        final repo = FakeStoreRepository();
        repo.orderDetailGate = Completer<StoreOrder>();
        repo.checkoutOutcome = const AwaitingExternalPayment(
          'https://pay.example.com/reset_mid',
        );

        final container = _createContainer(repo);
        addTearDown(container.dispose);

        final notifier = container.read(purchaseProvider.notifier);
        await notifier.payExistingOrder(tradeNo: 'RESET_MID', methodId: 1);
        expect(
          container.read(purchaseProvider),
          isA<PurchaseAwaitingPayment>(),
        );

        // Start poll without awaiting — fetchOrderDetail blocks on the gate.
        final pollFuture = notifier.pollOrderResult(
          'RESET_MID',
          maxAttempts: 1,
          interval: Duration.zero,
        );
        await Future<void>.delayed(Duration.zero);

        // Race: user resets while fetch is in flight.
        notifier.reset();

        // Release the gate with what looks like success — without the
        // generation guard this would call _completeSuccess and clobber
        // the just-reset Idle state.
        repo.orderDetailGate!.complete(
          FakeStoreRepository.completedOrder('RESET_MID'),
        );
        await pollFuture;

        expect(container.read(purchaseProvider), isA<PurchaseIdle>());
      },
    );

    test('cancelCurrentOrder mid-poll: stale fetchOrderDetail success does not '
        'clobber Idle', () async {
      final repo = FakeStoreRepository();
      repo.orderDetailGate = Completer<StoreOrder>();
      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com/cancel_mid',
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);
      await notifier.payExistingOrder(tradeNo: 'CANCEL_MID', methodId: 1);

      final pollFuture = notifier.pollOrderResult(
        'CANCEL_MID',
        maxAttempts: 1,
        interval: Duration.zero,
      );
      await Future<void>.delayed(Duration.zero);

      // Race: user cancels current order while fetch is gated. Cancel
      // bumps generation before our gate-completion lands.
      await notifier.cancelCurrentOrder();

      repo.orderDetailGate!.complete(
        FakeStoreRepository.completedOrder('CANCEL_MID'),
      );
      await pollFuture;

      expect(container.read(purchaseProvider), isA<PurchaseIdle>());
      expect(repo.cancelOrderCalled, isTrue);
    });

    test('purchase with PaymentDeclined transitions to Failed', () async {
      final repo = FakeStoreRepository();
      repo.createOrderResult = 'DECLINED_001';
      repo.checkoutOutcome = const PaymentDeclined(
        StoreErrorApi('支付链接为空，请稍后重试', statusCode: 0),
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(purchaseProvider.notifier)
          .purchase(planId: 1, period: PlanPeriod.monthly, methodId: 1);

      final state = container.read(purchaseProvider);
      expect(state, isA<PurchaseFailed>());
      expect((state as PurchaseFailed).message, contains('支付链接为空'));
    });

    test(
      'pollOrderResult fails closed when loop exhausts with empty URL',
      () async {
        final repo = FakeStoreRepository();
        // Default fetchOrderDetail returns pending — loop will exhaust.

        final container = _createContainer(repo);
        addTearDown(container.dispose);

        final notifier = container.read(purchaseProvider.notifier);
        // State is Idle at entry, so originalPaymentUrl is captured as ''.
        await notifier.pollOrderResult(
          'NO_URL_001',
          maxAttempts: 1,
          interval: Duration.zero,
        );

        final state = container.read(purchaseProvider);
        expect(state, isA<PurchaseFailed>());
        expect((state as PurchaseFailed).message, contains('支付链接缺失'));
      },
    );

    test('cancelCurrentOrder completion does not clobber newer op', () async {
      final repo = FakeStoreRepository();
      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com/old',
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final notifier = container.read(purchaseProvider.notifier);
      await notifier.payExistingOrder(tradeNo: 'OLD_001', methodId: 1);
      expect(container.read(purchaseProvider), isA<PurchaseAwaitingPayment>());

      // Gate the cancel: cancelCurrentOrder will block inside cancelOrder.
      repo.cancelGate = Completer<void>();
      final cancelFuture = notifier.cancelCurrentOrder();
      await Future<void>.delayed(Duration.zero);

      // While cancel is gated, user resets and starts a new purchase.
      notifier.reset();

      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com/new',
      );
      await notifier.payExistingOrder(tradeNo: 'NEW_001', methodId: 1);

      final mid = container.read(purchaseProvider);
      expect(mid, isA<PurchaseAwaitingPayment>());
      expect((mid as PurchaseAwaitingPayment).tradeNo, 'NEW_001');

      // Release the cancel response. Without the post-await gen guard,
      // this would write PurchaseIdle and clobber the new awaiting state.
      repo.cancelGate!.complete();
      await cancelFuture;

      final after = container.read(purchaseProvider);
      expect(after, isA<PurchaseAwaitingPayment>());
      expect((after as PurchaseAwaitingPayment).tradeNo, 'NEW_001');
    });

    test('cancelCurrentOrder invalidates orderHistoryProvider', () async {
      final repo = FakeStoreRepository();
      repo.checkoutOutcome = const AwaitingExternalPayment(
        'https://pay.example.com/inv',
      );
      repo.ordersResult = OrderListResult(
        orders: [FakeStoreRepository.completedOrder('BEFORE')],
        hasMore: false,
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final sub = container.listen<List<StoreOrder>?>(
        orderHistoryProvider.select((value) => value.value),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // Prime cache with [BEFORE]
      final before = await container.read(orderHistoryProvider.future);
      expect(before.first.tradeNo, 'BEFORE');

      // Set up an awaiting-payment state so cancelCurrentOrder has work to do.
      final notifier = container.read(purchaseProvider.notifier);
      await notifier.payExistingOrder(tradeNo: 'INVAL_001', methodId: 1);
      expect(container.read(purchaseProvider), isA<PurchaseAwaitingPayment>());

      // Server-side state changes to [AFTER]; cache is stale.
      repo.ordersResult = OrderListResult(
        orders: [FakeStoreRepository.completedOrder('AFTER')],
        hasMore: false,
      );

      await notifier.cancelCurrentOrder();

      // After invalidation the next read must refetch.
      final after = await container.read(orderHistoryProvider.future);
      expect(after.first.tradeNo, 'AFTER');
      expect(repo.cancelOrderCalled, isTrue);
    });
  });

  group('OrderHistoryNotifier', () {
    test('build fetches first page', () async {
      final repo = FakeStoreRepository();
      repo.ordersResult = OrderListResult(
        orders: [FakeStoreRepository.completedOrder('O1')],
        hasMore: false,
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      final future = container.read(orderHistoryProvider.future);
      final orders = await future;

      expect(orders.length, 1);
      expect(orders.first.tradeNo, 'O1');
    });

    test('loadMore appends next page', () async {
      final repo = FakeStoreRepository();
      repo.ordersResult = OrderListResult(
        orders: List.generate(
          15,
          (i) => FakeStoreRepository.completedOrder('O$i'),
        ),
        hasMore: true,
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      await container.read(orderHistoryProvider.future);

      final notifier = container.read(orderHistoryProvider.notifier);
      expect(notifier.hasMore, isTrue);

      // Update repo for page 2
      repo.ordersResult = OrderListResult(
        orders: [FakeStoreRepository.completedOrder('P2_O1')],
        hasMore: false,
      );

      await notifier.loadMore();
      expect(notifier.hasMore, isFalse);

      final orders = container.read(orderHistoryProvider).value;
      expect(orders, isNotNull);
      expect(orders!.length, 16); // 15 from page 1 + 1 from page 2
    });

    test('refresh resets to first page', () async {
      final repo = FakeStoreRepository();
      repo.ordersResult = OrderListResult(
        orders: [FakeStoreRepository.completedOrder('R1')],
        hasMore: false,
      );

      final container = _createContainer(repo);
      addTearDown(container.dispose);

      await container.read(orderHistoryProvider.future);
      final notifier = container.read(orderHistoryProvider.notifier);

      // Update repo with new data
      repo.ordersResult = OrderListResult(
        orders: [FakeStoreRepository.completedOrder('R2')],
        hasMore: false,
      );

      await notifier.refresh();
      final orders = container.read(orderHistoryProvider).value;
      expect(orders!.first.tradeNo, 'R2');
    });

    test('empty when not logged in', () async {
      final container = ProviderContainer(
        overrides: [
          storeRepositoryProvider.overrideWithValue(null),
          preloadedAuthStateProvider.overrideWithValue(
            const AuthState(status: AuthStatus.loggedOut),
          ),
        ],
      );
      addTearDown(container.dispose);

      final orders = await container.read(orderHistoryProvider.future);
      expect(orders, isEmpty);
    });
  });
}
