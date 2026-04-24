import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/platform/quit_watchdog.dart';

/// Unit tests for the kill-watchdog helper. The real [spawnQuitWatchdog]
/// entry point (which spawns an isolate and SIGKILLs the parent) can't
/// be tested without terminating the test runner. What matters for
/// correctness is the SLEEP→KILL invariant, and the swallow-errors
/// contract — both are in [runKillWatchdog], which is exercised
/// directly here with a fake kill fn.
void main() {
  group('runKillWatchdog', () {
    test('calls kill with the given pid after the specified delay',
        () async {
      var killed = -1;
      final sw = Stopwatch()..start();
      await runKillWatchdog(
        pid: 12345,
        delay: const Duration(milliseconds: 120),
        kill: (p) => killed = p,
      );
      sw.stop();

      expect(killed, 12345);
      // Allow some slack for test-env jitter; the floor matters.
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(100),
          reason: 'must actually wait the requested delay');
    });

    test('swallows exceptions thrown by kill — never surfaces', () async {
      // The watchdog is best-effort; a failing kill (bad pid, OS error)
      // must not propagate out of runKillWatchdog. The caller has
      // nothing productive to do with the exception — the process is
      // either already dead or about to die from something else.
      var attempted = false;
      await runKillWatchdog(
        pid: 0,
        delay: const Duration(milliseconds: 10),
        kill: (_) {
          attempted = true;
          throw Exception('no such pid');
        },
      );
      expect(attempted, isTrue);
      // Absence of throw is the assertion.
    });

    test('zero delay still fires kill', () async {
      var killed = -1;
      await runKillWatchdog(
        pid: 42,
        delay: Duration.zero,
        kill: (p) => killed = p,
      );
      expect(killed, 42);
    });

    test('QuitWatchdogArgs round-trips through const constructor', () {
      const a = QuitWatchdogArgs(pid: 9999, delayMs: 3000);
      expect(a.pid, 9999);
      expect(a.delayMs, 3000);
    });
  });
}
