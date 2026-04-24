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
}
