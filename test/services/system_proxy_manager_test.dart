import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/managers/system_proxy_manager.dart';

/// Unit tests for [SystemProxyManager]'s cache layer.
///
/// The platform-specific verifiers (`scutil` / `reg query` / `gsettings`)
/// are not exercised here — they touch the live OS and flake under CI.
/// What matters for the P0-2 hotfix is the CACHE DISCIPLINE around them:
///
///   * `verify(force: false)` must hit the cache when fresh.
///   * `verify(force: true)` must bypass the cache.
///   * `set()` / `clear()` must invalidate the cache so a subsequent
///     `verify()` re-queries the OS. Without this, a 60 s stale "no"
///     survived past the mutation, which was the original observable
///     bug in the v1.0.20 v2rayN-tamper scenario.
void main() {
  setUp(() {
    SystemProxyManager.invalidateVerifyCache();
  });

  tearDown(() {
    SystemProxyManager.invalidateVerifyCache();
  });

  group('SystemProxyManager.canServeFromCache — pure decision matrix', () {
    test('cold cache → miss (no cached entry can serve)', () {
      // Cache was invalidated in setUp; no prime.
      expect(
        SystemProxyManager.canServeFromCache(
          requestedPort: 7890,
          force: false,
          now: DateTime.now(),
        ),
        isFalse,
      );
    });

    test('fresh cache for same port → hit', () {
      final t = DateTime(2026, 4, 24, 12, 0, 0);
      SystemProxyManager.primeVerifyCacheForTest(
        port: 7890,
        value: true,
        at: t,
      );
      expect(
        SystemProxyManager.canServeFromCache(
          requestedPort: 7890,
          force: false,
          now: t.add(const Duration(seconds: 30)),
        ),
        isTrue,
      );
    });

    test('fresh cache but different port → miss', () {
      final t = DateTime(2026, 4, 24, 12, 0, 0);
      SystemProxyManager.primeVerifyCacheForTest(
        port: 7890,
        value: true,
        at: t,
      );
      // Caller is asking about port 1080 — cached value for 7890 is
      // irrelevant and would be a correctness hazard if served.
      expect(
        SystemProxyManager.canServeFromCache(
          requestedPort: 1080,
          force: false,
          now: t.add(const Duration(seconds: 10)),
        ),
        isFalse,
      );
    });

    test('cache past 60s TTL → miss', () {
      final t = DateTime(2026, 4, 24, 12, 0, 0);
      SystemProxyManager.primeVerifyCacheForTest(
        port: 7890,
        value: true,
        at: t,
      );
      expect(
        SystemProxyManager.canServeFromCache(
          requestedPort: 7890,
          force: false,
          now: t.add(const Duration(seconds: 61)),
        ),
        isFalse,
      );
    });

    test('force=true always misses, even on a 1-second-old entry', () {
      // This is the P0-2 invariant: v2rayN can flip the system proxy at
      // any moment, and resume/focus hooks must not read a stale "yes"
      // during the 60 s window.
      final t = DateTime(2026, 4, 24, 12, 0, 0);
      SystemProxyManager.primeVerifyCacheForTest(
        port: 7890,
        value: true,
        at: t,
      );
      expect(
        SystemProxyManager.canServeFromCache(
          requestedPort: 7890,
          force: true,
          now: t.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });

    test('null cached verdict is still servable when fresh (unknown tier)',
        () {
      // Linux/gsettings-unavailable path: null means "unknown, don't try
      // to interpret". Cache serves it same as any other verdict — the
      // caller's responsibility to treat null as "skip tamper check".
      final t = DateTime(2026, 4, 24, 12, 0, 0);
      SystemProxyManager.primeVerifyCacheForTest(
        port: 7890,
        value: null,
        at: t,
      );
      expect(
        SystemProxyManager.canServeFromCache(
          requestedPort: 7890,
          force: false,
          now: t.add(const Duration(seconds: 5)),
        ),
        isTrue,
      );
    });
  });

  group('SystemProxyManager.invalidateVerifyCache', () {
    test('wipes value + timestamp + port', () {
      SystemProxyManager.primeVerifyCacheForTest(
        port: 7890,
        value: true,
        at: DateTime(2026, 4, 24),
      );
      expect(SystemProxyManager.verifyCacheValueForTest, isTrue);
      expect(SystemProxyManager.verifyCacheAtForTest, isNotNull);
      expect(SystemProxyManager.verifyCachePortForTest, 7890);

      SystemProxyManager.invalidateVerifyCache();

      expect(SystemProxyManager.verifyCacheValueForTest, isNull);
      expect(SystemProxyManager.verifyCacheAtForTest, isNull);
      expect(SystemProxyManager.verifyCachePortForTest, isNull);
    });

    test('idempotent — safe to call twice', () {
      SystemProxyManager.invalidateVerifyCache();
      SystemProxyManager.invalidateVerifyCache();
      expect(SystemProxyManager.verifyCacheValueForTest, isNull);
    });

    test('after invalidate, canServeFromCache returns false', () {
      SystemProxyManager.primeVerifyCacheForTest(
        port: 7890,
        value: true,
      );
      SystemProxyManager.invalidateVerifyCache();
      expect(
        SystemProxyManager.canServeFromCache(
          requestedPort: 7890,
          force: false,
          now: DateTime.now(),
        ),
        isFalse,
      );
    });
  });

  group('SystemProxyManager.setWithRetry — P1-4 resume retry contract', () {
    test('first attempt succeeds → no retries, no sleep', () async {
      var attempts = 0;
      var sleepCount = 0;

      final ok = await SystemProxyManager.setWithRetry(
        7890,
        attemptOverride: (port) async {
          attempts++;
          return true;
        },
        sleepOverride: (_) async => sleepCount++,
      );

      expect(ok, isTrue);
      expect(attempts, 1);
      expect(sleepCount, 0,
          reason: 'happy path must not pay the 1.5 s settle delay');
    });

    test(
      'first attempt fails, second succeeds → recovers within one settle round',
      () async {
        var attempts = 0;
        final sleeps = <Duration>[];

        final ok = await SystemProxyManager.setWithRetry(
          7890,
          attemptOverride: (port) async {
            attempts++;
            return attempts >= 2;
          },
          sleepOverride: (d) async => sleeps.add(d),
        );

        expect(ok, isTrue);
        expect(attempts, 2);
        expect(sleeps, [const Duration(milliseconds: 1500)],
            reason: 'one settle round = one 1.5 s sleep');
      },
    );

    test(
      'all 3 attempts fail → returns false, exactly 2 sleeps between rounds',
      () async {
        var attempts = 0;
        final sleeps = <Duration>[];

        final ok = await SystemProxyManager.setWithRetry(
          7890,
          attemptOverride: (port) async {
            attempts++;
            return false;
          },
          sleepOverride: (d) async => sleeps.add(d),
        );

        expect(ok, isFalse);
        expect(attempts, 3);
        expect(sleeps.length, 2,
            reason: 'no trailing sleep after the final attempt');
        expect(sleeps.every((d) => d == const Duration(milliseconds: 1500)),
            isTrue);
      },
    );

    test(
      'attempt that throws is treated as a failure and retry continues',
      () async {
        var attempts = 0;
        final ok = await SystemProxyManager.setWithRetry(
          7890,
          attemptOverride: (port) async {
            attempts++;
            if (attempts == 1) throw StateError('mock platform error');
            return attempts >= 2;
          },
          sleepOverride: (_) async {},
        );

        expect(ok, isTrue);
        expect(attempts, 2);
      },
    );

    test('custom maxAttempts honoured', () async {
      var attempts = 0;
      final ok = await SystemProxyManager.setWithRetry(
        7890,
        maxAttempts: 1,
        attemptOverride: (port) async {
          attempts++;
          return false;
        },
        sleepOverride: (_) async {},
      );
      expect(ok, isFalse);
      expect(attempts, 1, reason: 'maxAttempts=1 disables retry');
    });
  });
}
