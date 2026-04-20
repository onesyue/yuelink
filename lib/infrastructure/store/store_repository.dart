import 'dart:async';
import 'dart:io';

import '../../domain/store/coupon_result.dart';
import '../../domain/store/order_list_result.dart';
import '../../domain/store/payment_method.dart';
import '../../domain/store/store_error.dart';
import '../../domain/store/store_order.dart';
import '../../domain/store/store_plan.dart';
import '../datasources/xboard/index.dart';

/// Thin wrapper around [XBoardApi] for all store-related operations.
///
/// Centralises store API calls so providers don't import XBoardApi directly.
/// Every method traps infrastructure exceptions (`XBoardApiException`,
/// `SocketException`, `TimeoutException`) and rethrows a typed
/// [StoreError] — consumers (modules/ + widgets/) only ever `catch` on
/// domain types.
class StoreRepository {
  final XBoardApi _api;
  final String _token;

  StoreRepository(this._api, this._token);

  Future<List<StorePlan>> fetchPlans() =>
      _guard(() => _api.getPlans(_token));

  Future<String> createOrder({
    required int planId,
    required PlanPeriod period,
    String? couponCode,
  }) =>
      _guard(() => _api.createOrder(
            token: _token,
            planId: planId,
            period: period.apiKey,
            couponCode: couponCode,
          ));

  Future<StoreOrder> fetchOrderDetail(String tradeNo) =>
      _guard(() => _api.getOrderDetail(token: _token, tradeNo: tradeNo));

  Future<CheckoutResult> checkoutOrder(String tradeNo, {int? methodId}) =>
      _guard(() => _api.checkoutOrder(
            token: _token,
            tradeNo: tradeNo,
            method: methodId,
          ));

  Future<List<PaymentMethod>> fetchPaymentMethods() =>
      _guard(() => _api.getPaymentMethods(_token));

  Future<void> cancelOrder(String tradeNo) =>
      _guard(() => _api.cancelOrder(token: _token, tradeNo: tradeNo));

  Future<CouponResult> checkCoupon(String code, int planId) =>
      _guard(() => _api.checkCoupon(token: _token, code: code, planId: planId));

  Future<OrderListResult> fetchOrders({int page = 1}) =>
      _guard(() => _api.fetchOrders(token: _token, page: page));
}

/// Run [op] and translate any thrown object into a [StoreError] subtype.
/// Kept local to this file so the mapping rules live next to the repo
/// methods that throw them.
Future<T> _guard<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on XBoardApiException catch (e) {
    if (e.statusCode == 401 || e.statusCode == 403) {
      throw StoreErrorUnauthorized(e.message, statusCode: e.statusCode);
    }
    throw StoreErrorApi(e.message, statusCode: e.statusCode);
  } on SocketException catch (e) {
    throw StoreErrorNetwork(e.message);
  } on TimeoutException catch (e) {
    throw StoreErrorNetwork(e.message ?? 'timeout');
  } on HttpException catch (e) {
    throw StoreErrorNetwork(e.message);
  } catch (e) {
    throw StoreErrorUnknown(e.toString());
  }
}
