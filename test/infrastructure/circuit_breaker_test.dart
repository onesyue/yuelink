import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/infrastructure/datasources/circuit_breaker.dart';

void main() {
  group('CircuitBreaker', () {
    test('starts closed', () {
      final cb = CircuitBreaker();
      expect(cb.isOpen, isFalse);
    });

    test('stays closed under threshold-1 failures', () {
      final cb = CircuitBreaker(threshold: 5);
      for (var i = 0; i < 4; i++) {
        expect(cb.recordFailure(), isFalse);
      }
      expect(cb.isOpen, isFalse);
    });

    test('trips open exactly at threshold', () {
      final cb = CircuitBreaker(threshold: 3);
      expect(cb.recordFailure(), isFalse);
      expect(cb.recordFailure(), isFalse);
      expect(cb.recordFailure(), isTrue,
          reason: 'third failure crosses threshold and opens the breaker');
      expect(cb.isOpen, isTrue);
    });

    test('recordSuccess resets failure counter', () {
      final cb = CircuitBreaker(threshold: 3);
      cb.recordFailure();
      cb.recordFailure();
      cb.recordSuccess();
      // After reset, two more failures are not enough to trip
      cb.recordFailure();
      cb.recordFailure();
      expect(cb.isOpen, isFalse);
      expect(cb.recordFailure(), isTrue,
          reason:
              'fresh threshold means three more failures are needed to trip');
    });

    test('isOpen flips back to false after cooldown elapses', () async {
      // Use a tight 50 ms cooldown so the test stays fast.
      final cb = CircuitBreaker(
        threshold: 1,
        cooldown: const Duration(milliseconds: 50),
      );
      cb.recordFailure();
      expect(cb.isOpen, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(cb.isOpen, isFalse,
          reason: 'cooldown elapsed → breaker enters half-open (returns false)');
    });

    test('reset clears both counter and open timestamp', () {
      final cb = CircuitBreaker(threshold: 1);
      cb.recordFailure();
      expect(cb.isOpen, isTrue);
      cb.reset();
      expect(cb.isOpen, isFalse);
      // After reset a single failure should NOT immediately trip again
      // unless threshold == 1 (it does here, but we're checking the
      // counter semantic not the threshold).
      expect(cb.recordFailure(), isTrue,
          reason: 'threshold=1 trips on every failure regardless of reset');
    });

    test('default threshold and cooldown are sensible', () {
      final cb = CircuitBreaker();
      // Defaults match the comment in the class — 5 failures, 30 s cooldown.
      // Verify by recording 4 failures (should NOT trip).
      for (var i = 0; i < 4; i++) {
        expect(cb.recordFailure(), isFalse);
      }
      expect(cb.recordFailure(), isTrue,
          reason: 'fifth failure trips with default threshold=5');
    });
  });
}
