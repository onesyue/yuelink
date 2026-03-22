import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/store/payment_method.dart';
import '../../domain/store/store_order.dart';
import '../../domain/store/store_plan.dart';
import '../../infrastructure/datasources/xboard_api.dart';
import '../../infrastructure/store/store_repository.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import 'state/purchase_state.dart';
export 'state/purchase_state.dart';
export '../../domain/store/order_list_result.dart';

// ------------------------------------------------------------------
// Repository provider
// ------------------------------------------------------------------

final storeRepositoryProvider = Provider<StoreRepository?>((ref) {
  final token = ref.watch(authProvider).token;
  final api = ref.watch(xboardApiProvider);
  if (token == null) return null;
  return StoreRepository(api, token);
});

// ------------------------------------------------------------------
// Plans
// ------------------------------------------------------------------

final storePlansProvider =
    AsyncNotifierProvider<StorePlansNotifier, List<StorePlan>>(
        StorePlansNotifier.new);

class StorePlansNotifier extends AsyncNotifier<List<StorePlan>> {
  @override
  Future<List<StorePlan>> build() async {
    final repo = ref.watch(storeRepositoryProvider);
    if (repo == null) return [];
    return repo.fetchPlans();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(storeRepositoryProvider);
      if (repo == null) return [];
      return repo.fetchPlans();
    });
  }
}

// ------------------------------------------------------------------
// Payment methods (cached for the session)
// ------------------------------------------------------------------

final paymentMethodsProvider =
    FutureProvider<List<PaymentMethod>>((ref) async {
  final repo = ref.watch(storeRepositoryProvider);
  if (repo == null) return [];
  return repo.fetchPaymentMethods();
});

// ------------------------------------------------------------------
// Selected period per plan
// ------------------------------------------------------------------

final selectedPeriodProvider =
    StateProvider.family<PlanPeriod?, int>((ref, planId) => null);

// ------------------------------------------------------------------
// Purchase state machine (defined in state/purchase_state.dart)
// ------------------------------------------------------------------

final purchaseProvider =
    NotifierProvider<PurchaseNotifier, PurchaseState>(PurchaseNotifier.new);

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
    // Prevent double submit during loading, polling, or awaiting payment
    if (state is PurchaseLoading || state is PurchasePolling ||
        state is PurchaseAwaitingPayment) {
      return;
    }

    final repo = ref.read(storeRepositoryProvider);
    if (repo == null) {
      state = const PurchaseFailed('未登录');
      return;
    }

    // Idempotency: check for existing pending order for same plan
    try {
      final List<StoreOrder> orders = ref.read(orderHistoryProvider).valueOrNull ??
          (await repo.fetchOrders(page: 1)).orders;
      final pending = orders
          .where((o) => o.planId == planId && o.status == OrderStatus.pending)
          .firstOrNull;
      if (pending != null) {
        // Reuse existing pending order instead of creating a duplicate
        debugPrint('[Store] Found pending order ${pending.tradeNo} for plan $planId — reusing');
        await payExistingOrder(tradeNo: pending.tradeNo, methodId: methodId);
        return;
      }
    } catch (e) {
      // Non-blocking: if history check fails, proceed with normal flow
      debugPrint('[Store] Pending order check failed: $e');
    }

    String? tradeNo; // captured early so error handler can reference it
    try {
      // 1. Create order
      state = const PurchaseLoading('创建订单中...');
      tradeNo = await repo.createOrder(
        planId: planId,
        period: period,
        couponCode: couponCode,
      );

      // 3. Checkout → payment URL
      state = const PurchaseLoading('获取支付链接...');
      final checkout = await repo.checkoutOrder(tradeNo, methodId: methodId);

      // 4. No payment URL — free plan or instant activation path.
      //    Attempt to confirm the order before surfacing any payment UI.
      //    Never land on an empty AwaitingPayment screen without trying first.
      if (checkout.paymentUrl.isEmpty) {
        final order = await repo.fetchOrderDetail(tradeNo);
        if (order.status.isSuccess) {
          state = PurchaseSuccess(order);
          _refreshUserSubscription();
          return;
        }
        // Backend hasn't activated yet (eventual consistency).
        // Run a short poll (3 × 2 s) before exposing the awaiting UI.
        // pollOrderResult sets the final state; we return here to avoid
        // the normal AwaitingPayment path below.
        await pollOrderResult(
          tradeNo,
          maxAttempts: 3,
          interval: const Duration(seconds: 2),
        );
        return;
      }

      state = PurchaseAwaitingPayment(
        tradeNo: tradeNo,
        paymentUrl: checkout.paymentUrl,
      );

      // 5. Open payment URL (Fix 1: surface failure instead of silent drop)
      await _openPaymentUrl(checkout.paymentUrl, tradeNo);
    } on Exception catch (e) {
      state = PurchaseFailed(_extractMessage(e), tradeNo: tradeNo);
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
    if (_polling) return; // Fix 2: reject concurrent poll requests
    _polling = true;

    final repo = ref.read(storeRepositoryProvider);
    if (repo == null) {
      _polling = false;
      return;
    }

    // Preserve the paymentUrl so it stays accessible after polling ends.
    final originalPaymentUrl = state is PurchaseAwaitingPayment
        ? (state as PurchaseAwaitingPayment).paymentUrl
        : '';

    try {
      for (var i = 1; i <= maxAttempts; i++) {
        // Check if order was cancelled mid-poll (user tapped 取消订单).
        if (state is PurchaseIdle) return;

        state = PurchasePolling(tradeNo, i);
        try {
          final order = await repo.fetchOrderDetail(tradeNo);
          if (order.status.isSuccess) {
            state = PurchaseSuccess(order);
            _refreshUserSubscription();
            return;
          }
          if (order.status == OrderStatus.cancelled) {
            state = PurchaseFailed('订单已取消', tradeNo: tradeNo);
            return;
          }
        } catch (e) {
          debugPrint('[Store] pollOrderResult failed: $e');
        }

        if (i < maxAttempts) await Future.delayed(interval);
      }

      // After exhausting attempts, leave user in awaiting state with the
      // original payment URL intact so user can re-open or manually check.
      state = PurchaseAwaitingPayment(
        tradeNo: tradeNo,
        paymentUrl: originalPaymentUrl,
      );
    } finally {
      _polling = false; // Always release the lock, even on early return
    }
  }

  /// Resume payment for an existing unpaid order (from order history).
  /// Skips the createOrder step — uses the already-known [tradeNo].
  Future<void> payExistingOrder({
    required String tradeNo,
    int? methodId,
  }) async {
    if (state is PurchaseLoading || state is PurchasePolling ||
        state is PurchaseAwaitingPayment) {
      return;
    }
    final repo = ref.read(storeRepositoryProvider);
    if (repo == null) {
      state = const PurchaseFailed('未登录');
      return;
    }
    try {
      state = const PurchaseLoading('获取支付链接...');
      final checkout = await repo.checkoutOrder(tradeNo, methodId: methodId);

      if (checkout.paymentUrl.isEmpty) {
        final order = await repo.fetchOrderDetail(tradeNo);
        if (order.status.isSuccess) {
          state = PurchaseSuccess(order);
          _refreshUserSubscription();
          return;
        }
        await pollOrderResult(
          tradeNo,
          maxAttempts: 3,
          interval: const Duration(seconds: 2),
        );
        return;
      }

      state = PurchaseAwaitingPayment(
        tradeNo: tradeNo,
        paymentUrl: checkout.paymentUrl,
      );
      await _openPaymentUrl(checkout.paymentUrl, tradeNo);
    } on Exception catch (e) {
      state = PurchaseFailed(_extractMessage(e), tradeNo: tradeNo);
    }
  }

  Future<void> cancelCurrentOrder() async {
    final tradeNo = _currentTradeNo();
    if (tradeNo == null) return;
    final repo = ref.read(storeRepositoryProvider);
    try {
      await repo?.cancelOrder(tradeNo);
      state = const PurchaseIdle();
    } on XBoardApiException catch (e) {
      state = PurchaseFailed(e.message, tradeNo: tradeNo);
    } on Exception catch (e) {
      state = PurchaseFailed(_extractMessage(e), tradeNo: tradeNo);
    }
  }

  void reset() => state = const PurchaseIdle();

  // ── helpers ───────────────────────────────────────────────────────

  String? _currentTradeNo() {
    final s = state;
    if (s is PurchaseAwaitingPayment) return s.tradeNo;
    if (s is PurchasePolling) return s.tradeNo;
    if (s is PurchaseFailed) return s.tradeNo;
    return null;
  }

  Future<void> _openPaymentUrl(String url, String tradeNo) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    // Fix 1: surface a visible error instead of silent failure.
    // State is already PurchaseAwaitingPayment; if the browser can't open,
    // transition to PurchaseFailed so the user sees what happened.
    if (uri == null || !await canLaunchUrl(uri)) {
      state = PurchaseFailed('无法打开支付页面，请稍后重试', tradeNo: tradeNo);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _refreshUserSubscription() {
    // Trigger subscription sync so traffic/expiry reflects the new plan.
    ref.read(authProvider.notifier).syncSubscription().ignore();
    // Refresh order history so the paid order shows updated status.
    ref.invalidate(orderHistoryProvider);
  }

  String _extractMessage(Object e) {
    if (e is XBoardApiException) return e.message;
    if (e is Exception) {
      final s = e.toString();
      return s.startsWith('Exception: ') ? s.substring(11) : s;
    }
    return e.toString();
  }
}

// ------------------------------------------------------------------
// Order history
// ------------------------------------------------------------------

final orderHistoryProvider =
    AsyncNotifierProvider<OrderHistoryNotifier, List<StoreOrder>>(
        OrderHistoryNotifier.new);

class OrderHistoryNotifier extends AsyncNotifier<List<StoreOrder>> {
  static const _perPage = 15;
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _loadingMore;

  @override
  Future<List<StoreOrder>> build() async {
    _page = 1;
    _hasMore = true;
    _loadingMore = false;
    final repo = ref.watch(storeRepositoryProvider);
    if (repo == null) return [];
    final result = await repo.fetchOrders(page: 1);
    // Trust server's hasMore when available (paginated response).
    // Only use length heuristic as fallback — if the first page returns
    // fewer items than _perPage, there are definitely no more pages.
    _hasMore = result.hasMore;
    if (!_hasMore && result.orders.length >= _perPage) {
      // Server says no more, but we got a full page — could be exact fit.
      // Keep _hasMore = false; server is authoritative.
    }
    return result.orders;
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final repo = ref.read(storeRepositoryProvider);
    if (repo == null) return;
    _loadingMore = true;
    try {
      final result = await repo.fetchOrders(page: _page + 1);
      _page++;
      _hasMore = result.hasMore;
      final current = state.valueOrNull ?? [];
      state = AsyncData([...current, ...result.orders]);
    } catch (e) {
      // Do NOT change _hasMore — the page is still retrievable on retry.
      // Rethrow so the UI (_LoadMoreFooter) can show a visible error and
      // offer a retry button, preventing the permanently-stuck state.
      rethrow;
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> refresh() async {
    _page = 1;
    _hasMore = true;
    _loadingMore = false;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(storeRepositoryProvider);
      if (repo == null) return [];
      final result = await repo.fetchOrders(page: 1);
      _hasMore = result.hasMore;
      return result.orders;
    });
  }
}
