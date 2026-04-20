import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/store/coupon_result.dart';
import '../../domain/store/payment_outcome.dart';
import '../../domain/store/purchase_state.dart';
import '../../domain/store/store_error.dart';
import '../../domain/store/store_order.dart';
import '../../domain/store/store_plan.dart';
import '../../infrastructure/store/payment_launcher.dart';
import '../../infrastructure/store/plan_period_mapping.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../shared/telemetry.dart';
import 'store_providers.dart';

final paymentLauncherProvider = Provider<PaymentLauncher>(
  (_) => const UrlLauncherPaymentLauncher(),
);

final purchaseProvider = NotifierProvider<PurchaseNotifier, PurchaseState>(
  PurchaseNotifier.new,
);

class PurchaseNotifier extends Notifier<PurchaseState> {
  /// True while a poll loop is actively running. Guards against concurrent polls.
  bool _polling = false;

  @override
  PurchaseState build() => const PurchaseIdle();

  /// Start purchase: create order → checkout → open payment URL.
  Future<void> purchase({
    required int planId,
    required PlanPeriod period,
    String? couponCode,
    int? methodId,
  }) async {
    if (state is PurchaseLoading ||
        state is PurchasePolling ||
        state is PurchaseAwaitingPayment) {
      return;
    }

    final repo = ref.read(storeRepositoryProvider);
    if (repo == null) {
      _setFailed(
        '未登录',
        context: 'purchase.no_repo',
        planId: planId,
        period: period,
      );
      return;
    }

    _trackPurchaseStart(
      planId: planId,
      period: period,
      methodId: methodId,
      hasCoupon: couponCode?.trim().isNotEmpty == true,
    );

    try {
      final List<StoreOrder> orders =
          ref.read(orderHistoryProvider).value ??
          (await repo.fetchOrders(page: 1)).orders;
      final pending = orders
          .where((o) => o.planId == planId && o.status == OrderStatus.pending)
          .firstOrNull;
      if (pending != null) {
        debugPrint(
          '[Store] Found pending order ${pending.tradeNo} for plan $planId — reusing',
        );
        _trackPendingOrderReuse(planId: planId, period: period);
        await payExistingOrder(tradeNo: pending.tradeNo, methodId: methodId);
        return;
      }
    } catch (e) {
      // Non-blocking: if history check fails, proceed with normal flow.
      debugPrint('[Store] Pending order check failed: $e');
    }

    String? tradeNo;
    try {
      state = const PurchaseLoading('创建订单中...');
      tradeNo = await repo.createOrder(
        planId: planId,
        period: period,
        couponCode: couponCode,
      );

      state = const PurchaseLoading('获取支付链接...');
      final outcome = await repo.checkoutOrder(tradeNo, methodId: methodId);
      await _handleCheckoutOutcome(
        outcome,
        tradeNo: tradeNo,
        context: 'purchase',
      );
    } on Exception catch (e) {
      _setFailed(
        _extractMessage(e),
        tradeNo: tradeNo,
        error: e,
        context: 'purchase.exception',
        planId: planId,
        period: period,
      );
    }
  }

  /// Called when user returns to the app after payment.
  /// Polls order status up to [maxAttempts] times with [interval] delay.
  ///
  /// Only one poll loop can run at a time per notifier instance.
  /// Concurrent callers (e.g. repeated app-resume events) return immediately.
  Future<void> pollOrderResult(
    String tradeNo, {
    int maxAttempts = 6,
    Duration interval = const Duration(seconds: 3),
  }) async {
    if (_polling) return;
    _polling = true;

    final repo = ref.read(storeRepositoryProvider);
    if (repo == null) {
      _polling = false;
      return;
    }

    final originalPaymentUrl = state is PurchaseAwaitingPayment
        ? (state as PurchaseAwaitingPayment).paymentUrl
        : '';

    try {
      for (var i = 1; i <= maxAttempts; i++) {
        if (state is PurchaseIdle) return;

        state = PurchasePolling(tradeNo, i);
        try {
          final order = await repo.fetchOrderDetail(tradeNo);
          if (order.status.isSuccess) {
            _completeSuccess(order, context: 'poll');
            return;
          }
          if (order.status == OrderStatus.cancelled) {
            _setFailed('订单已取消', tradeNo: tradeNo, context: 'poll.cancelled');
            return;
          }
        } catch (e) {
          debugPrint('[Store] pollOrderResult failed: $e');
        }

        if (i < maxAttempts) await Future.delayed(interval);
      }

      state = PurchaseAwaitingPayment(
        tradeNo: tradeNo,
        paymentUrl: originalPaymentUrl,
      );
    } finally {
      _polling = false;
    }
  }

  /// Resume payment for an existing unpaid order (from order history).
  /// Skips the createOrder step — uses the already-known [tradeNo].
  Future<void> payExistingOrder({
    required String tradeNo,
    int? methodId,
  }) async {
    if (state is PurchaseLoading ||
        state is PurchasePolling ||
        state is PurchaseAwaitingPayment) {
      return;
    }

    final repo = ref.read(storeRepositoryProvider);
    if (repo == null) {
      _setFailed('未登录', tradeNo: tradeNo, context: 'pay_existing.no_repo');
      return;
    }

    try {
      state = const PurchaseLoading('获取支付链接...');
      final outcome = await repo.checkoutOrder(tradeNo, methodId: methodId);
      await _handleCheckoutOutcome(
        outcome,
        tradeNo: tradeNo,
        context: 'pay_existing',
      );
    } on Exception catch (e) {
      _setFailed(
        _extractMessage(e),
        tradeNo: tradeNo,
        error: e,
        context: 'pay_existing.exception',
      );
    }
  }

  Future<void> cancelCurrentOrder() async {
    final tradeNo = _currentTradeNo();
    if (tradeNo == null) return;
    final repo = ref.read(storeRepositoryProvider);
    try {
      await repo?.cancelOrder(tradeNo);
      Telemetry.event(
        TelemetryEvents.orderCancel,
        props: {'ctx': 'current_order'},
      );
      state = const PurchaseIdle();
    } on StoreError catch (e) {
      _setFailed(
        e.message,
        tradeNo: tradeNo,
        error: e,
        context: 'cancel_current',
      );
    } on Exception catch (e) {
      _setFailed(
        _extractMessage(e),
        tradeNo: tradeNo,
        error: e,
        context: 'cancel_current.exception',
      );
    }
  }

  Future<void> cancelOrderFromHistory(String tradeNo) async {
    final repo = ref.read(storeRepositoryProvider);
    if (repo == null) throw Exception('未登录');
    await repo.cancelOrder(tradeNo);
    Telemetry.event(TelemetryEvents.orderCancel, props: {'ctx': 'history'});
    ref.invalidate(orderHistoryProvider);
  }

  Future<CouponResult> validateCoupon(String code, int planId) async {
    final repo = ref.read(storeRepositoryProvider);
    if (repo == null) throw Exception('未登录');
    return repo.checkCoupon(code, planId);
  }

  void reset() => state = const PurchaseIdle();

  Future<void> _handleCheckoutOutcome(
    PaymentOutcome outcome, {
    required String tradeNo,
    required String context,
  }) async {
    final repo = ref.read(storeRepositoryProvider);
    if (repo == null) {
      _setFailed('未登录', tradeNo: tradeNo, context: '$context.no_repo');
      return;
    }

    switch (outcome) {
      case FreeActivated():
        final order = await repo.fetchOrderDetail(tradeNo);
        if (order.status.isSuccess) {
          _completeSuccess(order, context: '$context.free_immediate');
          return;
        }
        await pollOrderResult(
          tradeNo,
          maxAttempts: 3,
          interval: const Duration(seconds: 2),
        );
        return;
      case AwaitingExternalPayment(:final url):
        state = PurchaseAwaitingPayment(tradeNo: tradeNo, paymentUrl: url);
        await _openPaymentUrl(url, tradeNo, context: context);
      case PaymentDeclined(:final error):
        _setFailed(
          error.message,
          tradeNo: tradeNo,
          error: error,
          context: '$context.declined',
        );
        return;
    }
  }

  String? _currentTradeNo() {
    final s = state;
    if (s is PurchaseAwaitingPayment) return s.tradeNo;
    if (s is PurchasePolling) return s.tradeNo;
    if (s is PurchaseFailed) return s.tradeNo;
    return null;
  }

  Future<void> _openPaymentUrl(
    String url,
    String tradeNo, {
    required String context,
  }) async {
    if (url.isEmpty) return;
    final ok = await ref.read(paymentLauncherProvider).launch(url);
    if (!ok) {
      _setFailed(
        '无法打开支付页面，请稍后重试',
        tradeNo: tradeNo,
        context: '$context.open_url_failed',
      );
    }
  }

  void _completeSuccess(StoreOrder order, {required String context}) {
    state = PurchaseSuccess(order);
    Telemetry.event(
      TelemetryEvents.purchaseSuccess,
      props: {
        'ctx': context,
        'plan_id': order.planId,
        'period': _orderPeriodName(order),
      },
    );
    _refreshUserSubscription();
  }

  void _setFailed(
    String message, {
    String? tradeNo,
    Object? error,
    required String context,
    int? planId,
    PlanPeriod? period,
  }) {
    state = PurchaseFailed(message, tradeNo: tradeNo);
    Telemetry.event(
      TelemetryEvents.purchaseFail,
      props: {
        'ctx': context,
        ...?_optionalProp('plan_id', planId),
        ...?_optionalProp('period', period?.name),
        ..._errorProps(error),
      },
    );
  }

  void _trackPurchaseStart({
    required int planId,
    required PlanPeriod period,
    int? methodId,
    required bool hasCoupon,
  }) {
    Telemetry.event(
      TelemetryEvents.purchaseStart,
      props: {
        'plan_id': planId,
        'period': period.name,
        'has_coupon': hasCoupon,
        ...?_optionalProp('method_id', methodId),
      },
    );
  }

  void _trackPendingOrderReuse({
    required int planId,
    required PlanPeriod period,
  }) {
    Telemetry.event(
      TelemetryEvents.pendingOrderReuse,
      props: {'plan_id': planId, 'period': period.name},
    );
  }

  Map<String, dynamic> _errorProps(Object? error) {
    switch (error) {
      case StoreErrorNetwork():
        return {'error_type': 'network'};
      case StoreErrorUnauthorized(:final statusCode):
        return {'error_type': 'unauthorized', 'status_code': statusCode};
      case StoreErrorApi(:final statusCode):
        return {'error_type': 'api', 'status_code': statusCode};
      case StoreErrorUnknown():
        return {'error_type': 'unknown'};
      case Exception():
        return {'error_type': error.runtimeType.toString()};
      case null:
        return {'error_type': 'state'};
      default:
        return {'error_type': error.runtimeType.toString()};
    }
  }

  String _orderPeriodName(StoreOrder order) {
    return planPeriodFromApiKey(order.period)?.name ?? order.period;
  }

  Map<String, dynamic>? _optionalProp(String key, Object? value) {
    return value == null ? null : {key: value};
  }

  void _refreshUserSubscription() {
    // Trigger subscription sync so traffic/expiry reflects the new plan.
    ref.read(authProvider.notifier).syncSubscription().ignore();
    // Refresh order history so the paid order shows updated status.
    ref.invalidate(orderHistoryProvider);
  }

  String _extractMessage(Object e) {
    if (e is StoreError) return e.message;
    if (e is Exception) {
      final s = e.toString();
      return s.startsWith('Exception: ') ? s.substring(11) : s;
    }
    return e.toString();
  }
}
