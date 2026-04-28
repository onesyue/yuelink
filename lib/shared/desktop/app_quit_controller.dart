import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/quit_watchdog.dart';
import '../../core/providers/core_provider.dart';
import '../event_log.dart';

/// Owns the desktop quit sequence: watchdog spawn → core stop →
/// system-proxy clear → tray + window destroy → `exit(0)`.
///
/// Previously inlined in `_YueLinkAppState._handleQuit` (lib/main.dart,
/// ~110 lines) plus the `_isQuitting` flag plus the watchdog fallback
/// timer. Pulling them out:
///   * makes the multi-step cleanup readable as a sequence of guarded
///     phases rather than 6 nested try/catches;
///   * lets `_isQuitting` live next to the only thing that flips it
///     (the run path) and still be observable from `onWindowClose`'s
///     short-circuit;
///   * keeps the platform-channel + isolate-spawn imports out of
///     main.dart.
///
/// The controller is desktop-only — mobile quits via the OS task
/// manager and never invokes [runQuit]. Constructor takes a single
/// callback for closing the cold-start single-instance ServerSocket
/// because that lives at module scope in main.dart and the controller
/// shouldn't reach into widget-file private state.
class AppQuitController {
  AppQuitController({
    required this.ref,
    required this.closeSingleInstanceServer,
  });

  final WidgetRef ref;

  /// Called during [runQuit] to release the single-instance TCP listener.
  /// Synchronous; failures are swallowed (logged only) — the listener
  /// dies with the process anyway.
  final void Function() closeSingleInstanceServer;

  /// True from the moment [runQuit] starts until [exit(0)] runs. Used
  /// by the window-close handler to ignore the OS callback that fires
  /// as a side-effect of `windowManager.destroy()`. Without this guard
  /// the close callback re-enters the quit path and races with the
  /// shutdown already in progress.
  bool get isQuitting => _isQuitting;
  bool _isQuitting = false;

  /// Run the full quit sequence. Idempotent — repeated calls return
  /// immediately because [_isQuitting] short-circuits at the top.
  ///
  /// Order is load-bearing:
  ///   1. Mark `isQuitting = true` so `onWindowClose` re-entries no-op.
  ///   2. Spawn the watchdog isolate so a hung native call below still
  ///      gets SIGKILL'd at +3 s.
  ///   3. Stop the core (best-effort, 2 s cap).
  ///   4. Close the single-instance listener.
  ///   5. Clear the system proxy so the OS doesn't keep routing through
  ///      a dead mixed-port (most user-visible correctness invariant —
  ///      bumping this earlier in the chain risks getting cut off by a
  ///      later stage failure).
  ///   6. Destroy tray + window.
  ///   7. `exit(0)`.
  Future<void> runQuit() async {
    if (_isQuitting) return;
    _isQuitting = true;

    // Phase 1: watchdog. Hard-cap the entire quit sequence with a SEPARATE
    // isolate's event loop. Previously this was a `Future.delayed(3 s)`
    // scheduled on the main isolate — exactly the loop being starved by
    // the platform-channel awaits below (windowManager.destroy /
    // trayManager.destroy / ServiceClient.stop) on Win11. Isolate has
    // its own event loop; on fire it SIGKILLs our pid which OS-level
    // terminates the whole process. Desktop only.
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await spawnQuitWatchdog(delay: const Duration(seconds: 3));
      } catch (e) {
        // Isolate spawn itself failed — fall back to a Dart Timer.
        // Worse safety net than the isolate (same jam risk) but better
        // than nothing; on a healthy event loop it still fires.
        debugPrint(
          '[Quit] watchdog isolate spawn failed: $e — '
          'falling back to Dart Timer',
        );
        Future.delayed(const Duration(seconds: 3), () {
          try {
            Process.killPid(pid, ProcessSignal.sigkill);
          } catch (e) {
            EventLog.writeTagged(
              'Quit',
              'quit_kill_fallback_failed',
              context: {'error': e},
            );
          }
          exit(0);
        });
      }
    }

    // Phase 2: cleanup. Each step is independently try/caught — one
    // hung step must not block the next. EventLog entries record what
    // failed for the diagnostics export.
    try {
      final status = ref.read(coreStatusProvider);
      if (status == CoreStatus.running) {
        await ref
            .read(coreActionsProvider)
            .stop()
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      }
      try {
        closeSingleInstanceServer();
      } catch (e) {
        EventLog.writeTagged(
          'Quit',
          'quit_server_close_failed',
          context: {'error': e},
        );
      }
      // System-proxy clear is the user-visible correctness requirement —
      // must complete before exit, or the OS keeps routing traffic
      // through a dead mixed-port. 2 s cap covers the slow macOS path
      // (N network services × 3 networksetup calls); the 3 s watchdog
      // above is the hard safety net if this itself hangs.
      try {
        await CoreActions.clearSystemProxyStatic().timeout(
          const Duration(seconds: 2),
        );
      } catch (e) {
        EventLog.writeTagged(
          'Quit',
          'quit_proxy_clear_failed',
          context: {'error': e},
        );
      }
      try {
        trayManager.destroy();
      } catch (e) {
        EventLog.writeTagged(
          'Quit',
          'quit_tray_destroy_failed',
          context: {'error': e},
        );
      }
      try {
        windowManager.setPreventClose(false);
      } catch (e) {
        EventLog.writeTagged(
          'Quit',
          'quit_prevent_close_failed',
          context: {'error': e},
        );
      }
      try {
        windowManager.destroy();
      } catch (e) {
        EventLog.writeTagged(
          'Quit',
          'quit_window_destroy_failed',
          context: {'error': e},
        );
      }
    } catch (e) {
      EventLog.writeTagged(
        'Quit',
        'quit_cleanup_failed',
        context: {'error': e},
      );
    }
    exit(0);
  }
}
