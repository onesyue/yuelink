/// Outcome of [runGroupDelayWithRecovery].
///
/// `failureReason` tells the caller WHY the first attempt didn't return
/// usable results (so telemetry can distinguish "all nodes timed out"
/// from "HTTP call itself blew up"). `recovered` is true only when the
/// recovery loop produced a non-all-timeout map after the first attempt
/// failed — so the caller can emit a `delayTestAutoRecovered` event
/// without double-emitting on happy paths.
typedef GroupDelayOutcome = ({
  Map<String, dynamic>? results,
  String? failureReason,
  bool recovered,
});

typedef GroupDelayFn = Future<Map<String, dynamic>> Function();
typedef SideEffectFn = Future<void> Function();
typedef SleepFn = Future<void> Function(Duration d);

/// Closed-set reason strings for [GroupDelayOutcome.failureReason].
abstract class DelayTestFailureReason {
  /// HTTP call succeeded but every requested node reported timeout.
  /// Classic stale-core-state symptom after disconnect→reconnect.
  static const allTimeout = 'all_timeout';

  /// HTTP call itself threw (timeout, 5xx, socket error). Previously this
  /// path marked the whole group red without any recovery — the v1.0.21
  /// P0-3 fix adds the same flush+retry loop used by allTimeout so the
  /// user doesn't see a solid-red test right after reconnecting.
  static const exception = 'exception';
}

/// Default per-attempt backoff: starts short to catch the common
/// "mihomo just needed a beat" case, then stretches to give the core
/// real time to settle on persistently-bad reconnects.
///
/// v1.0.22 P0-2: was a single fixed `flushWait` of 1500 ms — all retries
/// at the same cadence wasted the cheap first attempt and didn't give
/// the deeper ones enough breathing room.
const List<Duration> kDelayRecoveryBackoff = [
  Duration(milliseconds: 500),
  Duration(milliseconds: 1500),
  Duration(milliseconds: 3000),
];

/// Run a group delay test with automatic flush+retry recovery.
///
/// Both failure modes fall through to the same recovery loop:
///   1. HTTP call threw
///   2. HTTP call returned a map where every requested node timed out
///
/// Recovery rounds: close all connections → flush fake-IP cache →
/// healthcheck providers → sleep [backoff[attempt-1]] → re-run. The
/// first successful result (non-throw AND non-all-timeout) wins. All
/// rounds failing returns `results: null` so the caller can mark the
/// group red as a last resort.
///
/// `maxRetries` defaults to `backoff.length` so callers don't have to
/// keep them in sync. If a caller overrides one without the other, the
/// loop runs `min(maxRetries, backoff.length)` rounds — passing more
/// retries than backoff entries would index out of bounds and dropping
/// retries silently is the safer default.
///
/// All IO goes through callbacks so tests can drive the state machine
/// without touching mihomo / sockets. Production callers wire:
///   - [flushConnections] → `manager.api.closeAllConnections`
///   - [flushFakeIp] → `manager.api.flushFakeIpCache`
///   - [healthCheckProviders] → iterate `/providers/proxies` and GET
///     `/providers/proxies/{name}/healthcheck` for each (clears the
///     stale URL-test cache that selector groups otherwise keep
///     reusing across a stop→start cycle, the actual root cause of
///     "测速全红 after reconnect")
///
/// `healthCheckProviders` defaults to a no-op so existing tests stay
/// passing without rewiring; production must pass it.
///
/// `totalBudget` caps the wall-clock duration of the entire recovery
/// loop (first attempt + all retries + side-effects). When the budget
/// is exhausted between phases, the loop short-circuits and returns
/// `results: null` with whatever `failureReason` was last classified.
/// Without this cap, a sluggish post-reconnect mihomo can keep each
/// retry round in the tens-of-seconds range (provider healthchecks
/// stack serially) and the user-facing spinner stays "testing…" for
/// minutes — the v1.0.22 P3-D regression report. `null` disables the
/// cap and preserves pre-fix behaviour for tests.
Future<GroupDelayOutcome> runGroupDelayWithRecovery({
  required GroupDelayFn runTest,
  required SideEffectFn flushConnections,
  required SideEffectFn flushFakeIp,
  required bool Function(Map<String, dynamic>) isAllTimeout,
  SideEffectFn? healthCheckProviders,
  SleepFn? sleep,
  int? maxRetries,
  List<Duration> backoff = kDelayRecoveryBackoff,
  Duration? totalBudget,
}) async {
  final stopwatch = Stopwatch()..start();
  bool budgetExhausted() =>
      totalBudget != null && stopwatch.elapsed >= totalBudget;

  final doSleep = sleep ?? Future.delayed;
  final doHealthCheck = healthCheckProviders ?? (() async {});
  final rounds = maxRetries ?? backoff.length;
  final effectiveRounds = rounds < backoff.length ? rounds : backoff.length;

  String? failureReason;
  try {
    final first = await runTest();
    if (!isAllTimeout(first)) {
      return (results: first, failureReason: null, recovered: false);
    }
    failureReason = DelayTestFailureReason.allTimeout;
  } catch (_) {
    // Both the "all timeout" and "HTTP threw" paths fall through here.
    // The exception is swallowed on purpose: whatever went wrong, the
    // recovery loop is the right next step. Caller logs the first-
    // attempt error separately if it wants to.
    failureReason = DelayTestFailureReason.exception;
  }

  // Recovery rounds. Each round: flush conn → flush fake-ip →
  // healthcheck providers → wait → retry. Order matters — connections
  // must close before the cache flush takes effect, and the cache must
  // be flushed before the healthcheck pulls fresh delay values into
  // the selector. Each phase checks the wall-clock budget before
  // running so a slow earlier phase can't leak into the next one.
  for (var attempt = 1; attempt <= effectiveRounds; attempt++) {
    if (budgetExhausted()) break;
    try {
      await flushConnections();
    } catch (_) {
      // mihomo may reject close-all during a bad state; retry still worth it.
    }
    if (budgetExhausted()) break;
    try {
      await flushFakeIp();
    } catch (_) {
      // same
    }
    if (budgetExhausted()) break;
    try {
      await doHealthCheck();
    } catch (_) {
      // healthcheck failures are not fatal — the next runTest() will
      // surface whatever state the core is in.
    }
    if (budgetExhausted()) break;
    await doSleep(backoff[attempt - 1]);
    if (budgetExhausted()) break;
    try {
      final retried = await runTest();
      if (!isAllTimeout(retried)) {
        return (
          results: retried,
          failureReason: failureReason,
          recovered: true,
        );
      }
    } catch (_) {
      // Retry threw too — continue to next round (or exit the loop).
    }
  }

  return (
    results: null,
    failureReason: failureReason,
    recovered: false,
  );
}
