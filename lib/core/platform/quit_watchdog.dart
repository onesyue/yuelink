import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// Arguments passed to [_watchdogIsolateEntry] via [Isolate.spawn]. Must be
/// a transferable type — so it's a small class with only int fields, no
/// Function / Ref / Stream closures.
class QuitWatchdogArgs {
  final int pid;
  final int delayMs;
  const QuitWatchdogArgs({required this.pid, required this.delayMs});
}

/// Watchdog-isolate entry. Declared at top-level so [Isolate.spawn] can
/// send it (nested / anonymous functions don't serialise).
///
/// In the child isolate: sleeps [QuitWatchdogArgs.delayMs], then sends
/// SIGKILL to the PARENT process pid. The SIGKILL terminates the whole
/// OS process — both isolates — which is the whole point: when the main
/// isolate is jammed in a blocking native call, the OS kill is the only
/// remaining lever.
Future<void> _watchdogIsolateEntry(QuitWatchdogArgs args) async {
  await runKillWatchdog(
    pid: args.pid,
    delay: Duration(milliseconds: args.delayMs),
  );
}

/// Pure-ish kill helper used by [_watchdogIsolateEntry] and unit tests.
///
/// The [kill] parameter defaults to `Process.killPid(pid, SIGKILL)` in
/// production. Tests pass a fake kill fn so they can assert the timing
/// without actually terminating the test runner.
///
/// Swallows any exception from [kill] — the watchdog is best-effort
/// by construction. The worst case is the main process eventually does
/// exit normally; the second-worst is the user kills it via Task
/// Manager. Neither is made worse by a failing kill call here.
Future<void> runKillWatchdog({
  required int pid,
  required Duration delay,
  void Function(int pid)? kill,
}) async {
  try {
    await Future.delayed(delay);
    final k = kill ?? _defaultKill;
    k(pid);
  } catch (_) {
    // Best-effort.
  }
}

void _defaultKill(int pid) {
  // `Process.killPid(pid, SIGKILL)` translates to TerminateProcess on
  // Windows (ends the process immediately regardless of Dart scheduler
  // state) and to `kill -9` on POSIX.
  Process.killPid(pid, ProcessSignal.sigkill);
}

/// Spawn a watchdog isolate that will SIGKILL the current process after
/// [delay] if something jams the main event loop. Call from the top of
/// the quit handler, BEFORE any cleanup work that could block.
///
/// Why an isolate, not a Dart [Timer] in the main isolate:
/// - `Future.delayed` / `Timer` in the main isolate depend on its event
///   loop ticking. If `windowManager.destroy` / `trayManager.destroy` /
///   a service-helper IPC call sits in a blocking native wait, the
///   event loop can't run the timer callback — and the 3 s safety
///   net never fires. User-reported Windows symptom: tray → Quit,
///   window closes but process stays resident.
/// - A child isolate has its own event loop. The main isolate being
///   jammed doesn't stop `Future.delayed` inside the watchdog.
/// - No external subprocess (no PowerShell Start-Sleep ghost), no
///   FFI dependency, no new pubspec package.
Future<void> spawnQuitWatchdog({
  Duration delay = const Duration(seconds: 3),
}) async {
  await Isolate.spawn(
    _watchdogIsolateEntry,
    QuitWatchdogArgs(pid: pid, delayMs: delay.inMilliseconds),
    errorsAreFatal: false,
  );
}
