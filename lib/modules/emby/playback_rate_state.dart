class EmbyPlaybackRateState {
  EmbyPlaybackRateState({double initialRate = 1.0})
    : selectedRate = initialRate,
      activeRate = initialRate;

  /// Rate the user picked in the settings sheet.
  double selectedRate;

  /// Rate currently applied to the player. This can differ from
  /// [selectedRate] while the temporary long-press boost is active.
  double activeRate;

  bool isTemporaryBoostActive = false;

  double select(double rate) {
    selectedRate = rate;
    if (!isTemporaryBoostActive) {
      activeRate = rate;
    }
    return activeRate;
  }

  double beginTemporaryBoost(double rate) {
    if (isTemporaryBoostActive) return activeRate;
    isTemporaryBoostActive = true;
    activeRate = rate;
    return activeRate;
  }

  double endTemporaryBoost() {
    if (!isTemporaryBoostActive) return activeRate;
    isTemporaryBoostActive = false;
    activeRate = selectedRate;
    return activeRate;
  }
}

bool embyPlaybackRateEquals(double a, double b) => (a - b).abs() < 0.001;

String formatEmbyPlaybackRate(double rate) {
  final rounded = rate.roundToDouble();
  if (embyPlaybackRateEquals(rate, rounded)) {
    return '${rounded.toInt()}x';
  }
  return '${rate}x';
}
