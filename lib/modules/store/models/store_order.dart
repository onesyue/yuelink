/// An XBoard order.
class StoreOrder {
  final String tradeNo;
  final int planId;
  final String? planName;
  final String period; // e.g. "month_price"
  final int totalAmount; // fen
  final OrderStatus status;
  final int createdAt;
  final int updatedAt;
  final String? couponCode;

  const StoreOrder({
    required this.tradeNo,
    required this.planId,
    this.planName,
    required this.period,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.couponCode,
  });

  String get formattedAmount {
    if (totalAmount == 0) return '免费';
    final yuan = totalAmount / 100.0;
    return '¥${yuan.toStringAsFixed(yuan == yuan.truncate() ? 0 : 2)}';
  }

  DateTime get createdDate =>
      DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return null;
  }

  factory StoreOrder.fromJson(Map<String, dynamic> json) {
    return StoreOrder(
      tradeNo: json['trade_no'] as String? ?? '',
      planId: _toInt(json['plan_id']) ?? 0,
      planName: _extractPlanName(json),
      period: json['period'] as String? ?? '',
      totalAmount: _toInt(json['total_amount']) ?? 0,
      status: OrderStatus.fromInt(_toInt(json['status'])),
      createdAt: _toInt(json['created_at']) ?? 0,
      updatedAt: _toInt(json['updated_at']) ?? 0,
      couponCode: json['coupon_code'] as String?,
    );
  }

  static String? _extractPlanName(Map<String, dynamic> json) {
    if (json['plan'] is Map) {
      return (json['plan'] as Map)['name'] as String?;
    }
    return json['plan_name'] as String?;
  }
}

// ── Order status ──────────────────────────────────────────────────────────────

enum OrderStatus {
  pending,    // 0 — awaiting payment
  processing, // 1 — processing / activating
  cancelled,  // 2 — cancelled
  completed,  // 3 — paid and active
  discounted; // 4 — applied discount / free

  static OrderStatus fromInt(int? v) {
    switch (v) {
      case 0:
        return OrderStatus.pending;
      case 1:
        return OrderStatus.processing;
      case 2:
        return OrderStatus.cancelled;
      case 3:
        return OrderStatus.completed;
      case 4:
        return OrderStatus.discounted;
      default:
        return OrderStatus.pending;
    }
  }

  bool get isTerminal =>
      this == OrderStatus.cancelled ||
      this == OrderStatus.completed ||
      this == OrderStatus.discounted;

  bool get isSuccess =>
      this == OrderStatus.processing ||
      this == OrderStatus.completed ||
      this == OrderStatus.discounted;
}

// ── Checkout result ───────────────────────────────────────────────────────────

/// Result from POST /api/v1/user/order/checkout.
class CheckoutResult {
  /// 0 = QR code image URL, 1 = redirect URL, 2 = HTML form
  final int type;
  final String data;

  const CheckoutResult({required this.type, required this.data});

  /// Whether this is a free/instant order (no payment URL needed).
  bool get isFree => type == -1;

  /// The URL to open in browser (type 1) or display as QR (type 0).
  /// Empty string for free orders (type -1).
  String get paymentUrl => isFree ? '' : data;

  bool get isUrl => (type == 1 || type == 0) && data.isNotEmpty;

  factory CheckoutResult.fromJson(Map<String, dynamic> json) {
    final type = StoreOrder._toInt(json['type']) ?? 1;
    // data can be: a URL string (type 0/1), bool true (type -1, free), or null
    final rawData = json['data'];
    final data = rawData is String ? rawData : '';
    return CheckoutResult(type: type, data: data);
  }
}
