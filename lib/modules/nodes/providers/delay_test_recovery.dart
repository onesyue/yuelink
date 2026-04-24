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

/// Run a group delay test with automatic flush+retry recovery.
///
/// Both failure modes fall through to the same 2-round recovery loop:
///   1. HTTP call threw
///   2. HTTP call returned a map where every requested node timed out
///
/// Recovery rounds: close all connections → flush fake-IP cache → wait
/// [flushWait] → re-run. The first successful result (non-throw AND
/// non-all-timeout) wins. All [maxRetries] rounds failing returns
/// `results: null` so the caller can mark the group red as a last resort.
///
/// All IO goes through callbacks so tests can drive the state machine
/// without touching mihomo / sockets. Production callers wire
/// [flushConnections] / [flushFakeIp] to `manager.api.closeAllConnections` /
/// `manager.api.flushFakeIpCache`; unit tests pass counters.
Future<GroupDelayOutcome> runGroupDelayWithRecovery({
  required GroupDelayFn runTest,
  required SideEffectFn flushConnections,
  required SideEffectFn flushFakeIp,
  required bool Function(Map<String, dynamic>) isAllTimeout,
  SleepFn? sleep,
  int maxRetries = 2,
  Duration flushWait = const Duration(milliseconds: 1500),
}) async {
  final doSleep = sleep ?? Future.delayed;

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

  // Recovery rounds. Each round: flush → wait → retry.
  for (var attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      await flushConnections();
    } catch (_) {
      // mihomo may reject close-all during a bad state; retry still worth it.
    }
    try {
      await flushFakeIp();
    } catch (_) {
      // same
    }
    await doSleep(flushWait);
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
