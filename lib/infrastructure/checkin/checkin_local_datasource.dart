import '../../core/storage/settings_service.dart';

/// Encapsulates local check-in date persistence via [SettingsService].
///
/// The checkin server resets at midnight Asia/Shanghai. This datasource
/// records whether *this device* performed today's check-in, so the
/// Provider can distinguish "checked on this device" from "checked on
/// another device".
class CheckinLocalDatasource {
  static const _dateKey = 'checkin_date';
  static const _rewardTypeKey = 'checkin_reward_type';
  static const _rewardTextKey = 'checkin_reward_text';

  /// Today's date in UTC+8, e.g. "2026-03-22".
  /// Forced to UTC+8 so the result is consistent across all timezones.
  static String _todayStr() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Whether this device recorded a check-in for today.
  Future<bool> selfCheckedToday() async {
    final stored = await SettingsService.get<String>(_dateKey);
    return stored == _todayStr();
  }

  /// Persist today's date and reward as the local check-in record.
  Future<void> recordSelfCheckin({
    required String rewardType,
    required String rewardText,
  }) async {
    await SettingsService.set(_dateKey, _todayStr());
    await SettingsService.set(_rewardTypeKey, rewardType);
    await SettingsService.set(_rewardTextKey, rewardText);
  }

  /// Read saved reward from today's check-in (null if no record for today).
  Future<({String type, String text})?> getSavedReward() async {
    final stored = await SettingsService.get<String>(_dateKey);
    if (stored != _todayStr()) return null;
    final type = await SettingsService.get<String>(_rewardTypeKey);
    final text = await SettingsService.get<String>(_rewardTextKey);
    if (type == null || text == null) return null;
    return (type: type, text: text);
  }
}
