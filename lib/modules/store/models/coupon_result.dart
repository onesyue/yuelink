/// Result from POST /api/v1/user/coupon/check.
///
/// XBoard validates the coupon server-side. The client does not compute
/// eligibility — it only displays what the server returns.
class CouponResult {
  final int id;
  final String code;

  /// 1 = fixed amount deduction (value is in fen)
  /// 2 = percentage discount (value is 0-100)
  final int type;

  /// Discount value. Fen for type 1; integer percent for type 2.
  final int value;

  const CouponResult({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
  });

  /// Actual discount amount in fen for an order of [originalFen].
  int discountFor(int originalFen) {
    if (type == 1) return value.clamp(0, originalFen);
    if (type == 2) return (originalFen * value / 100).round().clamp(0, originalFen);
    return 0;
  }

  /// Final amount after discount, in fen.
  int finalAmountFor(int originalFen) =>
      (originalFen - discountFor(originalFen)).clamp(0, originalFen);

  /// Human-readable discount label, e.g. "-¥5.00" or "-10%".
  String discountLabel(int originalFen) {
    final discount = discountFor(originalFen);
    final yuan = discount / 100.0;
    return '-¥${yuan.toStringAsFixed(yuan == yuan.truncate() ? 0 : 2)}';
  }

  factory CouponResult.fromJson(Map<String, dynamic> json) {
    return CouponResult(
      id: _toInt(json['id']) ?? 0,
      code: json['code'] as String? ?? '',
      type: _toInt(json['type']) ?? 1,
      value: _toInt(json['value']) ?? 0,
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
