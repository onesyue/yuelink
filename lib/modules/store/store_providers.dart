import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/store/payment_method.dart';
import '../../domain/store/store_order.dart';
import '../../domain/store/store_plan.dart';
import '../../infrastructure/store/store_repository.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
export '../../domain/store/order_list_result.dart';

// ------------------------------------------------------------------
// Repository provider
// ------------------------------------------------------------------

final storeRepositoryProvider = Provider<StoreRepository?>((ref) {
  final token = ref.watch(authProvider).token;
  final api = ref.watch(businessXboardApiProvider);
  if (token == null) return null;
  return StoreRepository(api, token);
});

// ------------------------------------------------------------------
// Plans
// ------------------------------------------------------------------

final storePlansProvider =
    AsyncNotifierProvider<StorePlansNotifier, List<StorePlan>>(
      StorePlansNotifier.new,
    );

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

final paymentMethodsProvider = FutureProvider<List<PaymentMethod>>((ref) async {
  final repo = ref.watch(storeRepositoryProvider);
  if (repo == null) return [];
  return repo.fetchPaymentMethods();
});

// ------------------------------------------------------------------
// Selected period per plan
// ------------------------------------------------------------------

final selectedPeriodProvider =
    NotifierProvider.family<SelectedPeriodNotifier, PlanPeriod?, int>(
      SelectedPeriodNotifier.new,
    );

/// Riverpod 3.x family pattern: the family arg is **constructor-injected**
/// (the legacy `FamilyNotifier.build(arg)` shape no longer exists). `planId`
/// isn't read by current callers — the previous `StateProvider.family`
/// initialiser also ignored it — but it's stored on the instance so future
/// per-plan state initialisation has somewhere to plug in without another
/// signature migration.
class SelectedPeriodNotifier extends Notifier<PlanPeriod?> {
  SelectedPeriodNotifier(this.planId);
  final int planId;

  @override
  PlanPeriod? build() => null;

  /// Replaces the previous `notifier.state = value` write site. Explicit
  /// method so the write surface stays explicit and grep-able.
  void set(PlanPeriod? value) {
    state = value;
  }
}

// ------------------------------------------------------------------
// Order history
// ------------------------------------------------------------------

final orderHistoryProvider =
    AsyncNotifierProvider<OrderHistoryNotifier, List<StoreOrder>>(
      OrderHistoryNotifier.new,
    );

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
      if (!ref.mounted) return;
      _hasMore = result.hasMore;
      _page++;
      final current = state.value ?? [];
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
