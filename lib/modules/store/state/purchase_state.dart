import '../../../domain/store/store_order.dart';

sealed class PurchaseState {
  const PurchaseState();
}

class PurchaseIdle extends PurchaseState {
  const PurchaseIdle();
}

class PurchaseLoading extends PurchaseState {
  final String message;
  const PurchaseLoading(this.message);
}

class PurchaseAwaitingPayment extends PurchaseState {
  final String tradeNo;
  final String paymentUrl;
  const PurchaseAwaitingPayment({
    required this.tradeNo,
    required this.paymentUrl,
  });
}

class PurchasePolling extends PurchaseState {
  final String tradeNo;
  final int attempt;
  const PurchasePolling(this.tradeNo, this.attempt);
}

class PurchaseSuccess extends PurchaseState {
  final StoreOrder order;
  const PurchaseSuccess(this.order);
}

class PurchaseFailed extends PurchaseState {
  final String message;
  final String? tradeNo; // set when order was created but checkout failed
  const PurchaseFailed(this.message, {this.tradeNo});
}
