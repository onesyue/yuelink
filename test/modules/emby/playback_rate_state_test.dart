import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/emby/playback_rate_state.dart';

void main() {
  group('EmbyPlaybackRateState', () {
    test('selected rate is the active rate in normal playback', () {
      final state = EmbyPlaybackRateState();

      expect(state.select(1.5), 1.5);
      expect(state.selectedRate, 1.5);
      expect(state.activeRate, 1.5);
      expect(state.isTemporaryBoostActive, isFalse);
    });

    test('ending an inactive boost is a no-op', () {
      final state = EmbyPlaybackRateState()..select(1.5);

      expect(state.endTemporaryBoost(), 1.5);
      expect(state.selectedRate, 1.5);
      expect(state.activeRate, 1.5);
      expect(state.isTemporaryBoostActive, isFalse);
    });

    test('temporary boost restores the user-selected rate', () {
      final state = EmbyPlaybackRateState()..select(1.25);

      expect(state.beginTemporaryBoost(2.0), 2.0);
      expect(state.selectedRate, 1.25);
      expect(state.activeRate, 2.0);
      expect(state.endTemporaryBoost(), 1.25);
      expect(state.activeRate, 1.25);
    });

    test('selecting during a boost takes effect after the boost ends', () {
      final state = EmbyPlaybackRateState()..select(1.25);

      state.beginTemporaryBoost(2.0);
      expect(state.select(1.5), 2.0);
      expect(state.selectedRate, 1.5);
      expect(state.activeRate, 2.0);
      expect(state.endTemporaryBoost(), 1.5);
    });
  });

  group('formatEmbyPlaybackRate', () {
    test('does not show a trailing .0 for integer rates', () {
      expect(formatEmbyPlaybackRate(1.0), '1x');
      expect(formatEmbyPlaybackRate(2.0), '2x');
    });

    test('keeps fractional rates readable', () {
      expect(formatEmbyPlaybackRate(0.75), '0.75x');
      expect(formatEmbyPlaybackRate(1.25), '1.25x');
    });
  });
}
