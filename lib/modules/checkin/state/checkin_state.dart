import '../../../domain/checkin/checkin_result_entity.dart';

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
