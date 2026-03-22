import 'store_order.dart';

/// Paginated order list result from XBoard API.
class OrderListResult {
  final List<StoreOrder> orders;
  final bool hasMore;
  const OrderListResult({required this.orders, required this.hasMore});
}
