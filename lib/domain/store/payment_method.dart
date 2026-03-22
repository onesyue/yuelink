/// A payment channel returned by /api/v1/user/order/getPaymentMethod.
class PaymentMethod {
  final int id;
  final String name;
  final String? icon;
  final String payment; // payment channel identifier, e.g. "alipay", "stripe"

  /// Fixed handling fee in fen (e.g. 50 = ¥0.50). null = no fee.
  final int? handlingFeeFixed;

  /// Percentage handling fee as integer 0-100. null = no fee.
  final int? handlingFeePercent;

  const PaymentMethod({
    required this.id,
    required this.name,
    this.icon,
    this.payment = '',
    this.handlingFeeFixed,
    this.handlingFeePercent,
  });

  /// Returns a display string for the handling fee given the order amount [fen].
  /// Returns null if there is no fee.
  String? handlingFeeLabel(int amountFen) {
    if (handlingFeeFixed != null && handlingFeeFixed! > 0) {
      final yuan = handlingFeeFixed! / 100.0;
      return '+¥${yuan.toStringAsFixed(2)}';
    }
    if (handlingFeePercent != null && handlingFeePercent! > 0) {
      final fee = (amountFen * handlingFeePercent! / 100).round();
      final yuan = fee / 100.0;
      return '+¥${yuan.toStringAsFixed(2)} ($handlingFeePercent%)';
    }
    return null;
  }

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String?,
      payment: json['payment'] as String? ?? '',
      handlingFeeFixed: _toInt(json['handling_fee_fixed']),
      handlingFeePercent: _toInt(json['handling_fee_percent']),
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return null;
  }
}
