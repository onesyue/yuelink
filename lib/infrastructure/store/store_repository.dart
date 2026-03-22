import '../../domain/store/coupon_result.dart';
import '../../domain/store/order_list_result.dart';
import '../../domain/store/payment_method.dart';
import '../../domain/store/store_order.dart';
import '../../domain/store/store_plan.dart';
import '../datasources/xboard_api.dart';

/// Thin wrapper around [XBoardApi] for all store-related operations.
///
/// Centralises store API calls so providers don't import XBoardApi directly.
class StoreRepository {
  final XBoardApi _api;
  final String _token;

  StoreRepository(this._api, this._token);

  Future<List<StorePlan>> fetchPlans() => _api.getPlans(_token);

  Future<String> createOrder({
    required int planId,
    required PlanPeriod period,
    String? couponCode,
  }) =>
      _api.createOrder(
        token: _token,
        planId: planId,
        period: period.apiKey,
        couponCode: couponCode,
      );

  Future<StoreOrder> fetchOrderDetail(String tradeNo) =>
      _api.getOrderDetail(token: _token, tradeNo: tradeNo);

  Future<CheckoutResult> checkoutOrder(String tradeNo, {int? methodId}) =>
      _api.checkoutOrder(token: _token, tradeNo: tradeNo, method: methodId);

  Future<List<PaymentMethod>> fetchPaymentMethods() =>
      _api.getPaymentMethods(_token);

  Future<void> cancelOrder(String tradeNo) =>
      _api.cancelOrder(token: _token, tradeNo: tradeNo);

  Future<CouponResult> checkCoupon(String code, int planId) =>
      _api.checkCoupon(token: _token, code: code, planId: planId);

  Future<OrderListResult> fetchOrders({int page = 1}) =>
      _api.fetchOrders(token: _token, page: page);
}
