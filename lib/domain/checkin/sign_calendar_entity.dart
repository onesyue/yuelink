/// 单日签到记录（来自 app_sign_history 表）。
class SignDay {
  /// '2026-04-29' 形式
  final DateTime date;

  /// 当日累计连签天数
  final int streak;

  /// 'traffic' | 'balance' | 'both' | 'points' | 'lucky' | 'card'
  final String? rewardType;

  /// 单位：traffic/lucky → GB；balance/milestone → 分；card → 0
  final int rewardValue;

  /// 'normal'（正常签到）| 'card'（补签卡补的）
  final String source;

  const SignDay({
    required this.date,
    required this.streak,
    this.rewardType,
    this.rewardValue = 0,
    this.source = 'normal',
  });

  bool get isCardResign => source == 'card';

  factory SignDay.fromJson(Map<String, dynamic> j) {
    return SignDay(
      date: DateTime.parse(j['date'] as String),
      streak: j['streak'] as int? ?? 0,
      rewardType: j['reward_type'] as String?,
      rewardValue: j['reward_value'] as int? ?? 0,
      source: j['source'] as String? ?? 'normal',
    );
  }
}

/// 月度日历完整数据。
class SignCalendarMonth {
  /// 'YYYY-MM'
  final String month;
  final int daysInMonth;
  final DateTime today;
  final bool todaySigned;
  final int streak;
  final double multiplier;
  final List<SignDay> days;

  const SignCalendarMonth({
    required this.month,
    required this.daysInMonth,
    required this.today,
    required this.todaySigned,
    required this.streak,
    required this.multiplier,
    required this.days,
  });

  /// 用 ISO date string 索引每天，O(1) 查询。
  Map<String, SignDay> get byDate => {
        for (final d in days) _isoDate(d.date): d,
      };

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  factory SignCalendarMonth.fromJson(Map<String, dynamic> j) {
    final daysJson = (j['days'] as List?) ?? const [];
    return SignCalendarMonth(
      month: j['month'] as String? ?? '',
      daysInMonth: j['days_in_month'] as int? ?? 30,
      today: DateTime.parse(j['today'] as String),
      todaySigned: j['today_signed'] == true,
      streak: j['streak'] as int? ?? 0,
      multiplier: (j['multiplier'] as num?)?.toDouble() ?? 1.0,
      days: daysJson
          .map((e) => SignDay.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// 补签卡兑换结果（POST /api/client/checkin/resign）。
class ResignResult {
  final bool success;
  final String? errorCode;
  final int cost;
  final int remainingPoints;
  final int newStreak;
  final String message;

  const ResignResult({
    required this.success,
    this.errorCode,
    this.cost = 0,
    this.remainingPoints = 0,
    this.newStreak = 0,
    this.message = '',
  });

  factory ResignResult.success(Map<String, dynamic> data) {
    return ResignResult(
      success: true,
      cost: data['cost'] as int? ?? 0,
      remainingPoints: data['remaining_points'] as int? ?? 0,
      newStreak: data['new_streak'] as int? ?? 0,
      message: data['message'] as String? ?? '补签成功',
    );
  }

  factory ResignResult.error(String code, [Map<String, dynamic>? extra]) {
    return ResignResult(
      success: false,
      errorCode: code,
      cost: extra?['required'] as int? ?? 0,
      remainingPoints: extra?['current'] as int? ?? 0,
      message: _humanizeError(code),
    );
  }

  static String _humanizeError(String code) {
    switch (code) {
      case 'today_already_checked':
        return '今天已签到，不需要补签卡';
      case 'yesterday_already_signed':
        return '昨天已签到，连签未断';
      case 'points_insufficient':
        return '积分不足';
      case 'invalid_token':
        return '请重新登录';
      default:
        return code;
    }
  }
}
