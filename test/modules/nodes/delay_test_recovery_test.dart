import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/nodes/providers/delay_test_recovery.dart';

bool _allTimeout(Map<String, dynamic> r) =>
    r.values.every((v) => (v is int && v <= 0) ||
        (v is Map && ((v['delay'] as num?)?.toInt() ?? 0) <= 0));

void main() {
  group('runGroupDelayWithRecovery — happy path', () {
    test('first attempt returns non-all-timeout → no recovery, no flush',
        () async {
      var runCount = 0;
      var flushConn = 0;
      var flushIp = 0;

      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          return {'A': 100, 'B': 150};
        },
        flushConnections: () async => flushConn++,
        flushFakeIp: () async => flushIp++,
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );

      expect(out.results, {'A': 100, 'B': 150});
      expect(out.failureReason, isNull);
      expect(out.recovered, isFalse);
      expect(runCount, 1);
      expect(flushConn, 0);
      expect(flushIp, 0);
    });
  });

  group('runGroupDelayWithRecovery — all-timeout path', () {
    test(
        'first attempt all-timeout → recovery succeeds → reason=all_timeout, '
        'recovered=true', () async {
      var runCount = 0;
      var flushConn = 0;
      var flushIp = 0;

      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          if (runCount == 1) {
            return {'A': 0, 'B': 0, 'C': 0};
          }
          return {'A': 90, 'B': 110, 'C': 75};
        },
        flushConnections: () async => flushConn++,
        flushFakeIp: () async => flushIp++,
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );

      expect(out.results, isNotNull);
      expect(out.results!['A'], 90);
      expect(out.failureReason, DelayTestFailureReason.allTimeout);
      expect(out.recovered, isTrue);
      expect(runCount, 2);
      expect(flushConn, 1, reason: 'one recovery round = one flush');
      expect(flushIp, 1);
    });

    test('all recovery rounds also return all-timeout → results null',
        () async {
      var runCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          return {'A': 0, 'B': 0};
        },
        flushConnections: () async {},
        flushFakeIp: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );

      expect(out.results, isNull);
      expect(out.failureReason, DelayTestFailureReason.allTimeout);
      expect(out.recovered, isFalse);
      expect(runCount, 3, reason: 'first + 2 recovery attempts');
    });
  });

  group('runGroupDelayWithRecovery — exception path (P0-3 core fix)', () {
    test(
        'TimeoutException on first attempt → recovery runs, NOT direct red',
        () async {
      var runCount = 0;
      var flushConn = 0;
      var flushIp = 0;

      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          if (runCount == 1) {
            throw TimeoutException('mock HTTP timeout');
          }
          return {'A': 120};
        },
        flushConnections: () async => flushConn++,
        flushFakeIp: () async => flushIp++,
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );

      expect(out.results, {'A': 120});
      expect(out.failureReason, DelayTestFailureReason.exception,
          reason: 'first-attempt throw must be classified as exception');
      expect(out.recovered, isTrue,
          reason:
              'exception path must now produce recovered=true when retry works');
      expect(runCount, 2);
      expect(flushConn, 1);
      expect(flushIp, 1);
    });

    test('generic Exception on first attempt → same recovery path',
        () async {
      var runCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          if (runCount == 1) throw Exception('some http error');
          return {'A': 100};
        },
        flushConnections: () async {},
        flushFakeIp: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );

      expect(out.results, isNotNull);
      expect(out.failureReason, DelayTestFailureReason.exception);
      expect(out.recovered, isTrue);
    });

    test(
        'exception on every attempt (first + 2 recoveries) → results null, '
        'reason stays "exception"', () async {
      var runCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          throw TimeoutException('persistent');
        },
        flushConnections: () async {},
        flushFakeIp: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );

      expect(out.results, isNull);
      expect(out.failureReason, DelayTestFailureReason.exception);
      expect(out.recovered, isFalse);
      expect(runCount, 3);
    });

    test(
        'first attempt throws, first recovery returns all-timeout, second '
        'recovery succeeds → recovered=true, reason preserved as exception',
        () async {
      var runCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          if (runCount == 1) throw Exception('blew up');
          if (runCount == 2) return {'A': 0, 'B': 0}; // still all-timeout
          return {'A': 50, 'B': 60};
        },
        flushConnections: () async {},
        flushFakeIp: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );

      expect(out.results, {'A': 50, 'B': 60});
      expect(out.failureReason, DelayTestFailureReason.exception,
          reason: 'failureReason reflects the FIRST failure, not the last');
      expect(out.recovered, isTrue);
      expect(runCount, 3);
    });
  });

  group('runGroupDelayWithRecovery — flush adapter failures are swallowed',
      () {
    test(
        'flushConnections throws → recovery still attempts retry',
        () async {
      var runCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          if (runCount == 1) throw Exception('first');
          return {'A': 42};
        },
        flushConnections: () async => throw Exception('api down'),
        flushFakeIp: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );

      expect(out.results, {'A': 42});
      expect(out.recovered, isTrue);
    });

    test('flushFakeIp throws → recovery still attempts retry', () async {
      var runCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          if (runCount == 1) return {'A': 0};
          return {'A': 50};
        },
        flushConnections: () async {},
        flushFakeIp: () async => throw StateError('fake-ip wedged'),
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );

      expect(out.results, {'A': 50});
      expect(out.recovered, isTrue);
    });
  });

  group('runGroupDelayWithRecovery — bounds + invariants', () {
    test('maxRetries=0 disables recovery; first-attempt throw → null',
        () async {
      final out = await runGroupDelayWithRecovery(
        runTest: () async => throw TimeoutException('x'),
        flushConnections: () async {},
        flushFakeIp: () async {},
        isAllTimeout: _allTimeout,
        maxRetries: 0,
        sleep: (_) async {},
      );
      expect(out.results, isNull);
      expect(out.failureReason, DelayTestFailureReason.exception);
      expect(out.recovered, isFalse);
    });

    test('sleep is called maxRetries times (once per recovery round)',
        () async {
      var sleepCount = 0;
      await runGroupDelayWithRecovery(
        runTest: () async => throw Exception('always'),
        flushConnections: () async {},
        flushFakeIp: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async => sleepCount++,
        maxRetries: 3,
      );
      expect(sleepCount, 3);
    });

    test('sleep duration defaults to 1.5s (production spec)', () async {
      Duration? observed;
      // Helper short-circuits on success; make first attempt succeed but
      // assert sleep is never called — and separately test the default
      // value by using a one-shot failure + one-shot recovery.
      await runGroupDelayWithRecovery(
        runTest: () async {
          // Never recover, so we exhaust retries and observe sleep.
          throw TimeoutException('x');
        },
        flushConnections: () async {},
        flushFakeIp: () async {},
        isAllTimeout: _allTimeout,
        maxRetries: 1,
        sleep: (d) async {
          observed = d;
        },
      );
      expect(observed, const Duration(milliseconds: 1500));
    });
  });
}
