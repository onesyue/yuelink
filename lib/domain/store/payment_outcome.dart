import 'store_error.dart';

sealed class PaymentOutcome {
  const PaymentOutcome();
}

/// Free or instantly activated — no payment URL required.
/// Notifier polls briefly to confirm activation.
class FreeActivated extends PaymentOutcome {
  const FreeActivated();
}

/// An external payment URL was returned; user must open browser to pay.
class AwaitingExternalPayment extends PaymentOutcome {
  final String url;
  const AwaitingExternalPayment(this.url);
}

/// Checkout declined by the backend with a typed error.
class PaymentDeclined extends PaymentOutcome {
  final StoreError error;
  const PaymentDeclined(this.error);
}
