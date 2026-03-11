import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_notifier.dart';
import 'profile_service.dart';
import 'settings_service.dart';

/// Periodically checks and updates subscription profiles.
///
/// Uses precise scheduling: after each check, calculates the exact time the
/// next profile becomes due and sets a one-shot Timer for that moment.
/// A 1-hour safety-net timer runs in parallel to handle edge cases (clock
/// drift, profile list changes while app is open).
class AutoUpdateService {
  AutoUpdateService._();
  static final instance = AutoUpdateService._();

  Timer? _preciseTimer;  // fires exactly when the next profile is due
  Timer? _safetyTimer;   // 1-hour fallback
  bool _running = false;
  bool _updating = false;

  /// Start the auto-update background loop.
  void start() {
    if (_running) return;
    _running = true;
    _scheduleCheck(immediately: true);
    // 1-hour safety net in case the precise timer is miscalculated
    _safetyTimer = Timer.periodic(
        const Duration(hours: 1), (_) => _scheduleCheck());
  }

  /// Stop the auto-update loop.
  void stop() {
    _preciseTimer?.cancel();
    _safetyTimer?.cancel();
    _preciseTimer = null;
    _safetyTimer = null;
    _running = false;
  }

  /// Schedule the next check. If [immediately] is true, run right now;
  /// otherwise compute the earliest due time across all profiles and
  /// set a one-shot timer for exactly that moment.
  Future<void> _scheduleCheck({bool immediately = false}) async {
    if (!_running) return;

    if (immediately) {
      await _checkAndUpdate();
      return;
    }

    // Compute next due time
    final delay = await _nextDueDelay();
    if (delay == null) return; // no profiles with URLs, nothing to schedule

    _preciseTimer?.cancel();
    _preciseTimer = Timer(delay, () async {
      await _checkAndUpdate();
      if (_running) _scheduleCheck(); // reschedule after each run
    });

    debugPrint('[AutoUpdate] next check in '
        '${delay.inMinutes}m ${delay.inSeconds % 60}s');
  }

  /// Returns the Duration until the earliest overdue profile, clamped to
  /// a minimum of 30 seconds (avoid tight loops on misconfigured intervals).
  /// Returns null if there are no URL-backed profiles or auto-update is off.
  Future<Duration?> _nextDueDelay() async {
    try {
      final intervalHours = await SettingsService.getAutoUpdateInterval();
      if (intervalHours <= 0) return null;

      final profiles = await ProfileService.loadProfiles();
      final now = DateTime.now();
      DateTime? earliest;

      for (final p in profiles) {
        if (p.url.isEmpty) continue;
        final due = (p.lastUpdated ?? DateTime(2000)).add(p.updateInterval);
        if (earliest == null || due.isBefore(earliest)) earliest = due;
      }

      if (earliest == null) return null;

      final diff = earliest.difference(now);
      // Already overdue → run in 30s (give app time to fully start)
      return diff.isNegative
          ? const Duration(seconds: 30)
          : diff + const Duration(seconds: 5); // 5s buffer past due time
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkAndUpdate() async {
    if (_updating) return;
    _updating = true;
    int updated = 0;
    try {
      final intervalHours = await SettingsService.getAutoUpdateInterval();
      if (intervalHours <= 0) return;

      final profiles = await ProfileService.loadProfiles();
      final now = DateTime.now();

      for (final profile in profiles) {
        if (profile.url.isEmpty) continue;
        final due =
            (profile.lastUpdated ?? DateTime(2000)).add(profile.updateInterval);
        if (now.isAfter(due)) {
          try {
            await ProfileService.updateProfile(profile);
            updated++;
          } catch (_) {
            // Skip failed updates; will retry on next precise timer fire
          }
        }
      }
    } finally {
      _updating = false;
      if (updated > 0) {
        AppNotifier.success(
            updated == 1 ? '订阅已自动更新' : '已自动更新 $updated 个订阅');
      }
    }
  }

  /// Force-update all profiles immediately.
  /// Returns immediately with zeros if an update is already in progress.
  Future<({int updated, int failed})> updateAll() async {
    if (_updating) return (updated: 0, failed: 0);
    _updating = true;
    try {
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
    } finally {
      _updating = false;
      // Reschedule after a manual update so the precise timer reflects new lastUpdated times
      if (_running) _scheduleCheck();
    }
  }
}
