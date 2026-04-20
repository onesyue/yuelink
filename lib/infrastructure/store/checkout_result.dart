/// DTO for POST /api/v1/user/order/checkout response.
/// Lives in infrastructure — it is a direct XBoard schema mapping.
/// [StoreRepository.checkoutOrder] translates it into [PaymentOutcome]
/// before exposing results to callers.
class CheckoutResult {
  /// -1 = free/instant, 0 = QR code URL, 1 = redirect URL
  final int type;
  final String data;

  const CheckoutResult({required this.type, required this.data});

  bool get isFree => type == -1;

  String get paymentUrl => isFree ? '' : data;

  bool get isUrl => (type == 1 || type == 0) && data.isNotEmpty;

  factory CheckoutResult.fromJson(Map<String, dynamic> json) {
    final type = _toInt(json['type']) ?? 1;
    final rawData = json['data'];
    final data = rawData is String ? rawData : '';
    return CheckoutResult(type: type, data: data);
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return null;
  }
}
