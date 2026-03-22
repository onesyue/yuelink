import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/checkin/checkin_result_entity.dart';
import '../../../infrastructure/checkin/checkin_local_datasource.dart';
import '../../../infrastructure/checkin/checkin_repository.dart';
import '../../../infrastructure/datasources/xboard_api.dart';
import '../../../l10n/app_strings.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../shared/app_notifier.dart';
import '../state/checkin_state.dart';

// ── DI: Infrastructure instances ────────────────────────────────────────────

final checkinRepositoryProvider = Provider<CheckinRepository>((ref) {
  return CheckinRepository();
});

final checkinLocalDatasourceProvider = Provider<CheckinLocalDatasource>((ref) {
  return CheckinLocalDatasource();
});

// ── Notifier ────────────────────────────────────────────────────────────────

final checkinProvider =
    NotifierProvider<CheckinNotifier, CheckinState>(CheckinNotifier.new);

class CheckinNotifier extends Notifier<CheckinState> {
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

  // ── Injected dependencies ─────────────────────────────────────────────

  CheckinRepository get _repo => ref.read(checkinRepositoryProvider);
  CheckinLocalDatasource get _local => ref.read(checkinLocalDatasourceProvider);

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Whether a server error message indicates the user has already checked in
  /// (some backends return a business error instead of alreadyChecked:true).
  static bool _isAlreadyCheckedError(String message) {
    final m = message.toLowerCase();
    return m.contains('already') || m.contains('已签到');
  }

  // ── Status check ──────────────────────────────────────────────────────

  /// Poll the server for today's check-in status and reconcile with local
  /// record. Sets [CheckinState.checkedInOnOtherDevice] when the server
  /// reports already-checked but this device has no local record.
  Future<void> _checkStatus() async {
    final auth = ref.read(authProvider);
    if (auth.token == null) return;

    try {
      final result = await _repo.getCheckinStatus(auth.token!);
      if (result == null) return;

      if (result.alreadyChecked) {
        final self = await _local.selfCheckedToday();
        // Status API returns amount=0 — restore saved reward from local storage
        var displayResult = result;
        if (result.amount == 0 && self) {
          final saved = await _local.getSavedReward();
          if (saved != null) {
            displayResult = CheckinResult(
              type: saved.type,
              amount: 0,
              amountText: saved.text,
              alreadyChecked: true,
            );
          }
        }
        state = state.copyWith(
          checkedIn: true,
          lastResult: displayResult,
          checkedInOnOtherDevice: !self,
        );
      }
    } catch (e) {
      debugPrint('[Checkin] status check failed: $e');
    }
  }

  // ── Checkin action ────────────────────────────────────────────────────

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
      final result = await _repo.checkin(auth.token!);

      if (result.alreadyChecked) {
        // Server says today is already done — check if it was us or another device.
        final self = await _local.selfCheckedToday();
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

      // Successful new check-in — persist local date + reward.
      await _local.recordSelfCheckin(
        rewardType: result.type,
        rewardText: result.amountText,
      );
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
        final self = await _local.selfCheckedToday();
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
