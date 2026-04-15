/// 账户总览数据模型（来自 YueLink Checkin API）。
///
/// GET https://yue.yuebao.website/api/client/account/overview
class AccountOverview {
  final String email;
  final String planName;
  final int transferUsedBytes;
  final int transferTotalBytes;
  final int transferRemainingBytes;
  final DateTime? expireAt;
  final int? daysRemaining;
  final String renewalUrl;
  // Device-online counters, sourced from v2_user.online_count / device_limit
  // via the Checkin API (applies a 10-min freshness filter matching the
  // yuebot DAO and XBoard plugin).
  final int? onlineCount;
  final int? deviceLimit;
  final DateTime? lastOnlineAt;

  const AccountOverview({
    required this.email,
    required this.planName,
    required this.transferUsedBytes,
    required this.transferTotalBytes,
    required this.transferRemainingBytes,
    this.expireAt,
    this.daysRemaining,
    required this.renewalUrl,
    this.onlineCount,
    this.deviceLimit,
    this.lastOnlineAt,
  });

  factory AccountOverview.fromJson(Map<String, dynamic> json) {
    DateTime? expireAt;
    final rawExpire = json['expire_at'];
    if (rawExpire != null && rawExpire is String && rawExpire.isNotEmpty) {
      try {
        expireAt = DateTime.parse(rawExpire).toLocal();
      } catch (_) {}
    }

    DateTime? lastOnlineAt;
    final rawLastOnline = json['last_online_at'];
    if (rawLastOnline is String && rawLastOnline.isNotEmpty) {
      try {
        lastOnlineAt = DateTime.parse(rawLastOnline).toLocal();
      } catch (_) {}
    }

    final used = _toInt(json['transfer_used_bytes']) ?? 0;
    final total = _toInt(json['transfer_total_bytes']) ?? 0;
    final remaining = _toInt(json['transfer_remaining_bytes']) ?? (total - used).clamp(0, total);

    final rawPlanName = json['plan_name'] as String?;
    return AccountOverview(
      email: json['email'] as String? ?? '—',
      planName: (rawPlanName == null || rawPlanName.trim().isEmpty) ? '无套餐' : rawPlanName,
      transferUsedBytes: used,
      transferTotalBytes: total,
      transferRemainingBytes: remaining,
      expireAt: expireAt,
      daysRemaining: _toInt(json['days_remaining']),
      renewalUrl: json['renewal_url'] as String? ?? 'https://yuetong.app/#/plan',
      onlineCount: _toInt(json['online_count']),
      deviceLimit: _toInt(json['device_limit']),
      lastOnlineAt: lastOnlineAt,
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// 使用率 0.0~1.0，total=0 时返回 0。
  double get usageRatio =>
      transferTotalBytes > 0 ? (transferUsedBytes / transferTotalBytes).clamp(0.0, 1.0) : 0.0;

  /// 使用率百分比字符串，total=0 时返回 "--"。
  String get usagePercentText {
    if (transferTotalBytes <= 0) return '--';
    final pct = (transferUsedBytes / transferTotalBytes * 100).clamp(0.0, 100.0);
    return '${pct.toStringAsFixed(1)}%';
  }
}
