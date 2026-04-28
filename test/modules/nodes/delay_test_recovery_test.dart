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
      expect(runCount, 4,
          reason:
              'P0-2 default backoff has 3 entries → first + 3 recovery attempts');
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
        'exception on every attempt (first + 3 recoveries with default '
        'backoff) → results null, reason stays "exception"', () async {
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
      expect(runCount, 4,
          reason: 'P0-2: backoff[0..2] = 3 recovery rounds + 1 first attempt');
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

    test('first sleep duration defaults to 500ms (P0-2 backoff[0])',
        () async {
      Duration? observed;
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
      expect(observed, const Duration(milliseconds: 500));
    });
  });

  group('runGroupDelayWithRecovery — P0-2 healthcheck + backoff', () {
    test('healthCheckProviders runs once per recovery round, AFTER flushes',
        () async {
      final order = <String>[];
      var runCount = 0;

      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          order.add('runTest');
          if (runCount == 1) throw Exception('first blew');
          return {'A': 100};
        },
        flushConnections: () async => order.add('flushConn'),
        flushFakeIp: () async => order.add('flushIp'),
        healthCheckProviders: () async => order.add('healthcheck'),
        isAllTimeout: _allTimeout,
        sleep: (_) async => order.add('sleep'),
      );

      expect(out.recovered, isTrue);
      // First runTest fails, then exactly one recovery round before success.
      expect(order, [
        'runTest',
        'flushConn',
        'flushIp',
        'healthcheck',
        'sleep',
        'runTest',
      ]);
    });

    test('healthCheckProviders default no-op preserves back-compat', () async {
      // No `healthCheckProviders` argument — the existing all-timeout path
      // must still recover the same way it did pre-P0-2. Belt-and-
      // suspenders for callers that haven't been rewired yet.
      var runCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          if (runCount == 1) return {'A': 0};
          return {'A': 60};
        },
        flushConnections: () async {},
        flushFakeIp: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );
      expect(out.recovered, isTrue);
      expect(out.results, {'A': 60});
    });

    test('healthcheck failure is swallowed — recovery still retries',
        () async {
      var runCount = 0;
      var hcCalls = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          if (runCount == 1) throw Exception('first');
          return {'A': 42};
        },
        flushConnections: () async {},
        flushFakeIp: () async {},
        healthCheckProviders: () async {
          hcCalls++;
          throw Exception('mihomo healthcheck 502');
        },
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );
      expect(out.results, {'A': 42});
      expect(out.recovered, isTrue);
      expect(hcCalls, 1, reason: 'one round = one healthcheck attempt');
    });

    test(
        'per-attempt backoff escalates 500ms → 1500ms → 3000ms across rounds',
        () async {
      final observed = <Duration>[];
      await runGroupDelayWithRecovery(
        runTest: () async => throw Exception('always'),
        flushConnections: () async {},
        flushFakeIp: () async {},
        healthCheckProviders: () async {},
        isAllTimeout: _allTimeout,
        sleep: (d) async => observed.add(d),
      );
      expect(observed, const [
        Duration(milliseconds: 500),
        Duration(milliseconds: 1500),
        Duration(milliseconds: 3000),
      ]);
    });

    test(
        'custom backoff list overrides default and bounds maxRetries silently',
        () async {
      final observed = <Duration>[];
      await runGroupDelayWithRecovery(
        runTest: () async => throw Exception('always'),
        flushConnections: () async {},
        flushFakeIp: () async {},
        isAllTimeout: _allTimeout,
        backoff: const [Duration(milliseconds: 10)],
        maxRetries: 5, // larger than backoff.length — should clamp to 1
        sleep: (d) async => observed.add(d),
      );
      expect(observed.length, 1,
          reason: 'maxRetries clamps to backoff.length to avoid OOB');
    });

    test(
        'persistent failure across all backoff entries — results null, '
        'failureReason preserved as exception (P0-2 throughput-failure path)',
        () async {
      var runCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          throw Exception('persistent helper down');
        },
        flushConnections: () async {},
        flushFakeIp: () async {},
        healthCheckProviders: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
      );
      expect(out.results, isNull);
      expect(out.failureReason, DelayTestFailureReason.exception);
      expect(out.recovered, isFalse);
      expect(runCount, 4,
          reason: 'first attempt + 3 backoff rounds = 4 runTest calls');
    });
  });

  group('runGroupDelayWithRecovery — P3-D wall-clock budget', () {
    test('totalBudget=null preserves pre-fix unbounded behaviour', () async {
      var runCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          throw Exception('always');
        },
        flushConnections: () async {},
        flushFakeIp: () async {},
        healthCheckProviders: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
        // totalBudget intentionally omitted
      );
      expect(out.results, isNull);
      expect(runCount, 4, reason: 'all 3 recovery rounds run when uncapped');
    });

    test(
        'budget exhausted after first attempt → no recovery rounds run',
        () async {
      // Slow first attempt that consumes the entire budget. The loop
      // must short-circuit BEFORE running flushConnections in round 1.
      var runCount = 0;
      var flushCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          // Burn 100ms of real wall-clock so the budget elapses.
          await Future.delayed(const Duration(milliseconds: 100));
          throw Exception('slow first');
        },
        flushConnections: () async => flushCount++,
        flushFakeIp: () async {},
        healthCheckProviders: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
        totalBudget: const Duration(milliseconds: 50),
      );
      expect(out.results, isNull);
      expect(out.failureReason, DelayTestFailureReason.exception);
      expect(out.recovered, isFalse);
      expect(runCount, 1,
          reason: 'budget exhausted after first attempt; no retries');
      expect(flushCount, 0, reason: 'no recovery side-effects past budget');
    });

    test(
        'budget large enough for first attempt + one round → at most one '
        'retry runs', () async {
      var runCount = 0;
      var flushCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          await Future.delayed(const Duration(milliseconds: 80));
          throw Exception('slow always');
        },
        flushConnections: () async => flushCount++,
        flushFakeIp: () async {},
        healthCheckProviders: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
        totalBudget: const Duration(milliseconds: 200),
      );
      expect(out.results, isNull);
      // 80ms first attempt + recovery round (≈80ms) ≈ 160ms < 200ms,
      // round 2 would push past 200ms. Allow either 2 or 3 to keep
      // the test stable across CI timing jitter.
      expect(runCount, inInclusiveRange(2, 3));
      expect(flushCount, inInclusiveRange(1, 2),
          reason: 'flush ran in at least the surviving round(s)');
    });

    test(
        'budget does not block a fast-path success on first attempt',
        () async {
      var runCount = 0;
      final out = await runGroupDelayWithRecovery(
        runTest: () async {
          runCount++;
          return {'A': 100, 'B': 150};
        },
        flushConnections: () async {},
        flushFakeIp: () async {},
        healthCheckProviders: () async {},
        isAllTimeout: _allTimeout,
        sleep: (_) async {},
        totalBudget: const Duration(milliseconds: 1),
      );
      expect(out.results, {'A': 100, 'B': 150});
      expect(out.recovered, isFalse);
      expect(runCount, 1, reason: 'success short-circuits before budget check');
    });
  });
}
