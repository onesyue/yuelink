/// A subscription plan available for purchase.
///
/// Prices are stored in fen (分, 1/100 yuan). null price means that period
/// is unavailable for this plan.
class StorePlan {
  final int id;
  final String name;
  final String? content; // Rich-text feature description (may be HTML or plain)

  /// Total traffic quota in bytes. null = unlimited.
  final int? transferEnable;

  /// Download speed cap in Mbps. null = unlimited.
  final int? speedLimit;

  /// Maximum simultaneous devices. null = unlimited.
  final int? deviceLimit;

  final bool show;
  final bool sell;
  final int sort;

  // ── Prices in fen (cents for ¥). null = period not offered. ─────────
  final int? monthPrice;
  final int? quarterPrice;
  final int? halfYearPrice;
  final int? yearPrice;
  final int? twoYearPrice;
  final int? threeYearPrice;
  final int? onetimePrice;
  final int? resetPrice; // 重置流量单价

  const StorePlan({
    required this.id,
    required this.name,
    this.content,
    this.transferEnable,
    this.speedLimit,
    this.deviceLimit,
    this.show = true,
    this.sell = true,
    this.sort = 0,
    this.monthPrice,
    this.quarterPrice,
    this.halfYearPrice,
    this.yearPrice,
    this.twoYearPrice,
    this.threeYearPrice,
    this.onetimePrice,
    this.resetPrice,
  });

  /// Available billing periods — those with a non-null price.
  List<PlanPeriod> get availablePeriods => PlanPeriod.values
      .where((p) => priceForPeriod(p) != null)
      .toList();

  /// Price in fen for the given period, or null if unavailable.
  int? priceForPeriod(PlanPeriod period) {
    switch (period) {
      case PlanPeriod.monthly:
        return monthPrice;
      case PlanPeriod.quarterly:
        return quarterPrice;
      case PlanPeriod.halfYearly:
        return halfYearPrice;
      case PlanPeriod.yearly:
        return yearPrice;
      case PlanPeriod.twoYearly:
        return twoYearPrice;
      case PlanPeriod.threeYearly:
        return threeYearPrice;
      case PlanPeriod.onetime:
        return onetimePrice;
    }
  }

  /// Display price string, e.g. "¥18.00".
  String formattedPrice(PlanPeriod period) {
    final fen = priceForPeriod(period);
    if (fen == null) return '-';
    if (fen == 0) return '免费';
    final yuan = fen / 100.0;
    return '¥${yuan.toStringAsFixed(yuan == yuan.truncate() ? 0 : 2)}';
  }

  /// Human-readable traffic quota, e.g. "100 GB" or "不限".
  /// XBoard plan API returns transfer_enable in GB (raw DB value), not bytes.
  String get trafficLabel {
    if (transferEnable == null || transferEnable! <= 0) return '不限';
    return '$transferEnable GB';
  }

  /// Human-readable speed cap.
  String get speedLabel {
    if (speedLimit == null || speedLimit! <= 0) return '不限';
    if (speedLimit! >= 1000) return '${(speedLimit! / 1000).toStringAsFixed(1)} Gbps';
    return '$speedLimit Mbps';
  }

  /// Human-readable device limit.
  String get deviceLabel {
    if (deviceLimit == null || deviceLimit! <= 0) return '不限';
    return '$deviceLimit 台';
  }

  /// XBoard may return numeric fields as int, double, or bool (tinyint(1)).
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return null;
  }

  static bool _toBool(dynamic v, {bool fallback = true}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is double) return v != 0;
    return fallback;
  }

  factory StorePlan.fromJson(Map<String, dynamic> json) {
    return StorePlan(
      id: _toInt(json['id']) ?? 0,
      name: json['name'] as String? ?? '',
      content: json['content'] as String?,
      transferEnable: _toInt(json['transfer_enable']),
      speedLimit: _toInt(json['speed_limit']),
      deviceLimit: _toInt(json['device_limit']),
      show: _toBool(json['show']),
      sell: _toBool(json['sell']),
      sort: _toInt(json['sort']) ?? 0,
      monthPrice: _toInt(json['month_price']),
      quarterPrice: _toInt(json['quarter_price']),
      halfYearPrice: _toInt(json['half_year_price']),
      yearPrice: _toInt(json['year_price']),
      twoYearPrice: _toInt(json['two_year_price']),
      threeYearPrice: _toInt(json['three_year_price']),
      onetimePrice: _toInt(json['onetime_price']),
      resetPrice: _toInt(json['reset_price']),
    );
  }
}

// ── Billing period ────────────────────────────────────────────────────────────

enum PlanPeriod {
  monthly,
  quarterly,
  halfYearly,
  yearly,
  twoYearly,
  threeYearly,
  onetime;

  /// The value sent to /api/v1/user/order/save as the `period` field.
  String get apiKey {
    switch (this) {
      case PlanPeriod.monthly:
        return 'month_price';
      case PlanPeriod.quarterly:
        return 'quarter_price';
      case PlanPeriod.halfYearly:
        return 'half_year_price';
      case PlanPeriod.yearly:
        return 'year_price';
      case PlanPeriod.twoYearly:
        return 'two_year_price';
      case PlanPeriod.threeYearly:
        return 'three_year_price';
      case PlanPeriod.onetime:
        return 'onetime_price';
    }
  }

  String label(bool isEn) {
    if (isEn) {
      switch (this) {
        case PlanPeriod.monthly:
          return '1 Month';
        case PlanPeriod.quarterly:
          return '3 Months';
        case PlanPeriod.halfYearly:
          return '6 Months';
        case PlanPeriod.yearly:
          return '1 Year';
        case PlanPeriod.twoYearly:
          return '2 Years';
        case PlanPeriod.threeYearly:
          return '3 Years';
        case PlanPeriod.onetime:
          return 'One-time';
      }
    } else {
      switch (this) {
        case PlanPeriod.monthly:
          return '月付';
        case PlanPeriod.quarterly:
          return '季付';
        case PlanPeriod.halfYearly:
          return '半年付';
        case PlanPeriod.yearly:
          return '年付';
        case PlanPeriod.twoYearly:
          return '两年付';
        case PlanPeriod.threeYearly:
          return '三年付';
        case PlanPeriod.onetime:
          return '一次性';
      }
    }
  }

  /// Short label for chips/pills.
  String get shortLabel {
    switch (this) {
      case PlanPeriod.monthly:
        return '月';
      case PlanPeriod.quarterly:
        return '季';
      case PlanPeriod.halfYearly:
        return '半年';
      case PlanPeriod.yearly:
        return '年';
      case PlanPeriod.twoYearly:
        return '2年';
      case PlanPeriod.threeYearly:
        return '3年';
      case PlanPeriod.onetime:
        return '买断';
    }
  }
}
