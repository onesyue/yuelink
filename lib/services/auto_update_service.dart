import 'dart:async';

import 'profile_service.dart';
import 'settings_service.dart';

/// Periodically checks and updates subscription profiles.
///
/// Each profile has its own `updateInterval`. This service checks every hour
/// whether any profile is due for an update based on its `lastUpdated` time.
class AutoUpdateService {
  AutoUpdateService._();
  static final instance = AutoUpdateService._();

  Timer? _timer;
  bool _running = false;

  /// Start the auto-update background loop.
  void start() {
    if (_running) return;
    _running = true;
    // Check immediately, then every hour
    _checkAndUpdate();
    _timer = Timer.periodic(const Duration(hours: 1), (_) => _checkAndUpdate());
  }

  /// Stop the auto-update loop.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> _checkAndUpdate() async {
    final intervalHours = await SettingsService.getAutoUpdateInterval();
    if (intervalHours <= 0) return; // Disabled

    final profiles = await ProfileService.loadProfiles();
    final now = DateTime.now();

    for (final profile in profiles) {
      if (profile.url.isEmpty) continue;

      final effectiveInterval = profile.updateInterval;
      final lastUpdated = profile.lastUpdated ?? DateTime(2000);
      final due = lastUpdated.add(effectiveInterval);

      if (now.isAfter(due)) {
        try {
          await ProfileService.updateProfile(profile);
        } catch (_) {
          // Silently skip failed updates; will retry next cycle
        }
      }
    }
  }

  /// Force-update all profiles immediately.
  Future<({int updated, int failed})> updateAll() async {
    final profiles = await ProfileService.loadProfiles();
    int updated = 0;
    int failed = 0;
    for (final profile in profiles) {
      if (profile.url.isEmpty) continue;
      try {
        await ProfileService.updateProfile(profile);
        updated++;
      } catch (_) {
        failed++;
      }
    }
    return (updated: updated, failed: failed);
  }
}
