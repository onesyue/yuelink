import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/settings_service.dart';
import '../../infrastructure/datasources/xboard_api.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../shared/app_notifier.dart';
import '../../l10n/app_strings.dart';
import 'models/checkin_result.dart';
import 'checkin_repository.dart';

// ------------------------------------------------------------------
// Checkin state
// ------------------------------------------------------------------

class CheckinState {
  final bool checkedIn;
  final bool loading;
  final CheckinResult? lastResult;
  final String? error;

  /// True when the server reports already-checked but this device has no
  /// local record for today — meaning another device performed the check-in.
  final bool checkedInOnOtherDevice;

  const CheckinState({
    this.checkedIn = false,
    this.loading = false,
    this.lastResult,
    this.error,
    this.checkedInOnOtherDevice = false,
  });

  CheckinState copyWith({
    bool? checkedIn,
    bool? loading,
    CheckinResult? lastResult,
    String? error,
    bool? checkedInOnOtherDevice,
  }) =>
      CheckinState(
        checkedIn: checkedIn ?? this.checkedIn,
        loading: loading ?? this.loading,
        lastResult: lastResult ?? this.lastResult,
        error: error,
        checkedInOnOtherDevice:
            checkedInOnOtherDevice ?? this.checkedInOnOtherDevice,
      );
}

// ------------------------------------------------------------------
// Provider
// ------------------------------------------------------------------

final checkinProvider =
    NotifierProvider<CheckinNotifier, CheckinState>(CheckinNotifier.new);

class CheckinNotifier extends Notifier<CheckinState> {
  static const _dateKey = 'checkin_date';

  @override
  CheckinState build() {
    // Reset + refresh whenever auth changes (login / logout).
    ref.listen(authProvider, (prev, next) {
      if (prev?.isLoggedIn == true && !next.isLoggedIn) {
        state = const CheckinState();
      } else if (prev?.isLoggedIn == false && next.isLoggedIn) {
        refresh();
      }
    });

    _checkStatus();
    return const CheckinState();
  }

  // ── Helpers ────────────────────────────────────────────────────────

  /// Today's date in UTC+8, e.g. "2026-03-21".
  /// Forced to UTC+8 so the result is consistent across all timezones —
  /// a user in UTC-5 won't get a different date than one in UTC+8.
  static String _todayStr() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Whether this device recorded a check-in for today.
  Future<bool> _selfCheckedToday() async {
    final stored = await SettingsService.get<String>(_dateKey);
    return stored == _todayStr();
  }

  /// Persist today's date as the local check-in record.
  Future<void> _recordSelfCheckin() =>
      SettingsService.set(_dateKey, _todayStr());

  /// Whether a server error message indicates the user has already checked in
  /// (some backends return a business error instead of alreadyChecked:true).
  static bool _isAlreadyCheckedError(String message) {
    final m = message.toLowerCase();
    return m.contains('already') || m.contains('已签到');
  }

  // ── Status check ───────────────────────────────────────────────────

  /// Poll the server for today's check-in status and reconcile with local
  /// record. Sets [CheckinState.checkedInOnOtherDevice] when the server
  /// reports already-checked but this device has no local record.
  Future<void> _checkStatus() async {
    final auth = ref.read(authProvider);
    if (auth.token == null) return;

    try {
      final result = await CheckinRepository().getCheckinStatus(auth.token!);
      if (result == null) return;

      if (result.alreadyChecked) {
        final self = await _selfCheckedToday();
        state = state.copyWith(
          checkedIn: true,
          lastResult: result,
          checkedInOnOtherDevice: !self,
        );
      }
    } catch (e) {
      debugPrint('[Checkin] status check failed: $e');
    }
  }

  // ── Checkin action ─────────────────────────────────────────────────

  /// Perform check-in. Distinguishes "other device already checked" from
  /// "this device already checked" for a clear user message.
  Future<void> checkin() async {
    if (state.loading || state.checkedIn) return;

    final auth = ref.read(authProvider);
    if (auth.token == null) {
      AppNotifier.error(S.current.checkinNeedLogin);
      return;
    }

    state = state.copyWith(loading: true, error: null);

    try {
      final result = await CheckinRepository().checkin(auth.token!);

      if (result.alreadyChecked) {
        // Server says today is already done — check if it was us or another device.
        final self = await _selfCheckedToday();
        state = state.copyWith(
          checkedIn: true,
          loading: false,
          lastResult: result,
          checkedInOnOtherDevice: !self,
        );
        AppNotifier.warning(
            self ? S.current.checkinAlready : S.current.checkinOtherDevice);
        return;
      }

      // Successful new check-in — persist local date.
      await _recordSelfCheckin();
      state = state.copyWith(
        checkedIn: true,
        loading: false,
        lastResult: result,
        checkedInOnOtherDevice: false,
      );

      final rewardText = result.type == 'traffic'
          ? S.current.checkinTrafficReward(result.amountText)
          : S.current.checkinBalanceReward(result.amountText);
      AppNotifier.success(rewardText);

      // Refresh user profile to reflect new traffic/balance.
      ref.read(authProvider.notifier).refreshUserInfo();
    } on XBoardApiException catch (e) {
      // Some checkin servers return a business error (e.g. "cannot determine
      // user ID") instead of alreadyChecked:true when the user has already
      // checked in. Intercept known patterns and show the correct message.
      if (_isAlreadyCheckedError(e.message)) {
        final self = await _selfCheckedToday();
        state = state.copyWith(
          checkedIn: true,
          loading: false,
          checkedInOnOtherDevice: !self,
        );
        AppNotifier.warning(
            self ? S.current.checkinAlready : S.current.checkinOtherDevice);
        return;
      }
      state = state.copyWith(loading: false, error: e.message);
      AppNotifier.error(S.current.checkinFailed);
    } catch (e) {
      debugPrint('[Checkin] error: $e');
      state = state.copyWith(loading: false, error: e.toString());
      AppNotifier.error(S.current.checkinFailed);
    }
  }

  /// Reset state and re-check from server (e.g. called on app resume or
  /// when pulling to refresh on the Dashboard).
  Future<void> refresh() async {
    state = const CheckinState();
    await _checkStatus();
  }
}
