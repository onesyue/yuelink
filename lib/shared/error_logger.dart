import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'event_log.dart';
import 'rotating_log_file.dart';
import 'telemetry.dart';

/// Unified error reporting — logs locally AND to remote monitoring.
///
/// In debug mode: only local crash.log + EventLog (no remote upload).
/// In release mode: local + remote (Sentry / Crashlytics / custom).
///
/// ## Integration
///
/// 1. Call [ErrorLogger.init] in `main()` before `runApp()`
/// 2. Pass a [RemoteReporter] implementation for your chosen platform:
///    ```dart
///    ErrorLogger.init(reporter: SentryReporter(dsn: '...'));
///    ```
/// 3. To add Sentry, add `sentry_flutter: ^8.0.0` to pubspec.yaml and
///    implement [RemoteReporter] (see example below).
class ErrorLogger {
  ErrorLogger._();

  static RemoteReporter? _reporter;

  /// Initialize global error handlers.
  ///
  /// Call once in `main()`. If [reporter] is provided and the app is running
  /// in release mode, errors are forwarded to the remote platform.
  static void init({RemoteReporter? reporter}) {
    _reporter = reporter;

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _capture(
        details.exceptionAsString(),
        details.stack ?? StackTrace.current,
        source: 'FlutterError',
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _capture(error.toString(), stack, source: 'PlatformDispatcher');
      // Return true on all platforms to prevent the framework from propagating
      // the error further (which can crash/exit the app on desktop).
      return true;
    };
  }

  /// Manually report a caught exception (e.g., in try-catch blocks).
  static void captureException(
    Object error,
    StackTrace stack, {
    String? source,
  }) {
    _capture(error.toString(), stack, source: source);
  }

  /// Scan crash.log for entries tagged `[Android/<thread>]` written by
  /// MainApplication's UncaughtExceptionHandler since the last check.
  /// For each new one, fire a `crash` telemetry event so server-side can
  /// aggregate the root cause distribution. Idempotent — uses the entry's
  /// timestamp as the cursor, persisted via [SettingsService].
  ///
  /// Called once at app start (after ErrorLogger.init and Telemetry.init).
  static Future<void> scanAndroidNativeCrashes() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logFile = File('${dir.path}/crash.log');
      if (!logFile.existsSync()) return;
      final content = await logFile.readAsString();
      // Fast path — no Android entries at all.
      if (!content.contains('[Android/')) return;
      // Timestamps on Android entries are ISO 8601 like [2026-04-17T12:34:56.789].
      // Track the most recent timestamp already reported.
      const cursorKey = 'lastAndroidCrashTimestamp';
      final lastSeen = await _readCrashCursor(cursorKey);
      final entries = _parseAndroidCrashEntries(content);
      String? newestSeen;
      for (final e in entries) {
        if (lastSeen != null && e.timestamp.compareTo(lastSeen) <= 0) continue;
        Telemetry.event(
          TelemetryEvents.crash,
          priority: true,
          props: {
            'src': 'android_native',
            'type': e.exceptionType,
            'thread': e.thread,
          },
        );
        if (newestSeen == null || e.timestamp.compareTo(newestSeen) > 0) {
          newestSeen = e.timestamp;
        }
      }
      if (newestSeen != null) await _writeCrashCursor(cursorKey, newestSeen);
    } catch (_) {
      // Silent — diagnostic code must never itself crash the app.
    }
  }

  static Future<String?> _readCrashCursor(String key) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final cursorFile = File('${dir.path}/$key.txt');
      if (!cursorFile.existsSync()) return null;
      final v = (await cursorFile.readAsString()).trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCrashCursor(String key, String value) async {
    try {
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/$key.txt').writeAsString(value);
    } catch (_) {}
  }

  static List<_AndroidCrashEntry> _parseAndroidCrashEntries(String content) {
    final out = <_AndroidCrashEntry>[];
    // Format written by MainApplication.installCrashHandler:
    //   [2026-04-17T12:34:56.789]
    //   [Android/<thread>] <exceptionClass>: <message>
    //   <stack>
    //   (blank)
    final re = RegExp(
      r'\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3})\]\s*\n'
      r'\[Android/([^\]]+)\]\s*([A-Za-z0-9_.$]+)',
      multiLine: true,
    );
    for (final m in re.allMatches(content)) {
      out.add(
        _AndroidCrashEntry(
          timestamp: m.group(1)!,
          thread: m.group(2)!,
          exceptionType: m.group(3)!,
        ),
      );
    }
    return out;
  }

  // ── Internal ────────────────────────────────────────────────────────

  // ── Telemetry dedup ──────────────────────────────────────────────────
  //
  // A single original exception can reach [_capture] through more than one
  // entry point: FlutterError.onError + PlatformDispatcher.onError for a
  // framework-level error that also escapes async; Zone handler in main()
  // + a manual captureException in the same frame; or a tight async loop
  // that retries a fire-and-forget op until it fails N times. The local
  // crash.log / EventLog / remote reporter keep every write (timestamps
  // have forensic value), but telemetry dashboards just see a noisy spike
  // that masks the per-session crash rate. Gate ONLY Telemetry.event so
  // a fingerprint fires at most once per [_dedupTtl] window.
  //
  // Fingerprint intentionally excludes `source` so two handlers observing
  // the same exception collapse to one entry. The top 3 stack lines are
  // enough to distinguish call sites while tolerating rethrow-wrapping
  // variations above that frame.
  static const _dedupTtl = Duration(seconds: 2);
  static final Map<String, DateTime> _recentFingerprints = {};

  static String _fingerprint(String firstLine, StackTrace stack) {
    final stackLines = stack.toString().split('\n');
    final top3 = stackLines.take(3).join('\n');
    return '$firstLine|$top3';
  }

  static bool _shouldEmitTelemetry(String fingerprint) {
    final now = DateTime.now();
    final last = _recentFingerprints[fingerprint];
    if (last != null && now.difference(last) < _dedupTtl) {
      return false;
    }
    _recentFingerprints[fingerprint] = now;
    // Opportunistic cleanup — no timer, map stays small between starts.
    _recentFingerprints.removeWhere((_, ts) => now.difference(ts) > _dedupTtl);
    return true;
  }

  /// Reset the telemetry dedup window. Test-only hook so cases can assert
  /// fingerprint behaviour from a known-clean state.
  @visibleForTesting
  static void debugResetDedup() {
    _recentFingerprints.clear();
  }

  static void _capture(String error, StackTrace stack, {String? source}) {
    // 1. Always write to local crash.log
    _writeCrashLog(error, stack.toString());

    // 2. Write to EventLog for quick diagnosis
    final tag = source != null ? '[$source]' : '[Error]';
    EventLog.write('$tag ${error.split('\n').first}');

    // 2b. Forward exception type to opt-in telemetry. We split into two
    // buckets so dashboards aren't drowned in transient network blips:
    //   - `crash`         : genuinely unexpected exceptions (priority, always
    //                        kept through buffer overflow)
    //   - `network_error` : WebSocket / HTTP / socket failures that the app
    //                        already handles (retry / reconnect logic). These
    //                        used to mask real crashes at ~98:1 ratio; we
    //                        keep them as non-priority telemetry for signal.
    //
    // Both buckets go through [_shouldEmitTelemetry] so one exception hitting
    // multiple handlers only shows up once — local crash.log above stays
    // unconditional.
    final firstLine = error.split('\n').first;
    // v1.0.22 P3-B: compute the dedup decision ONCE so both telemetry
    // and the remote reporter share the same fingerprint window.
    // _shouldEmitTelemetry has the side-effect of stamping the
    // fingerprint into the recent-map; calling it twice would always
    // return false on the second call and silently drop the remote
    // report on every legitimate first emission.
    final shouldEmit = _shouldEmitTelemetry(_fingerprint(firstLine, stack));
    if (shouldEmit) {
      final typeHint = firstLine.length > 80
          ? firstLine.substring(0, 80)
          : firstLine;
      final typeName = _typeFromError(typeHint);
      final isNetwork = _isNetworkError(typeName);
      Telemetry.event(
        isNetwork ? TelemetryEvents.networkError : TelemetryEvents.crash,
        priority: !isNetwork,
        props: {'src': source ?? 'unknown', 'type': typeName},
      );
    }

    // 3. Forward to remote reporter (release only). v1.0.22 P3-B:
    //    gated on the same dedup window as telemetry so a tight crash
    //    loop doesn't hammer Sentry / Crashlytics with the same
    //    fingerprint hundreds of times per minute. Local crash.log
    //    (step 1) and EventLog (step 2) intentionally stay
    //    unconditional — timestamps in those have forensic value.
    if (!kReleaseMode || _reporter == null) return;
    if (!shouldEmit) return;
    try {
      _reporter!.report(error, stack);
    } catch (e) {
      debugPrint('[ErrorLogger] remote report failed: $e');
    }
  }

  /// Pull the exception class name out of a stringified error, e.g.
  /// `FormatException: bad char` → `FormatException`. Falls back to the
  /// first 40 chars if no colon delimiter is found.
  static String _typeFromError(String s) {
    final idx = s.indexOf(':');
    if (idx > 0 && idx < 40) return s.substring(0, idx);
    return s.length > 40 ? s.substring(0, 40) : s;
  }

  /// Classify an exception type as a transient network failure. The app
  /// already retries these at higher levels (MihomoStream reconnect,
  /// MihomoApi circuit breaker, HttpClient with fallback URL), so they
  /// shouldn't trip the dashboard's `crash` counter.
  static bool _isNetworkError(String typeName) {
    const networkTypes = {
      'WebSocketChannelException',
      'WebSocketException',
      'SocketException',
      'HandshakeException',
      'HttpException',
      'ClientException',
      'TimeoutException',
      'TlsException',
      'OSError',
    };
    if (networkTypes.contains(typeName)) return true;
    // http package wraps some of these, e.g. "ClientException with SocketException".
    return typeName.startsWith('ClientException') ||
        typeName.startsWith('SocketException');
  }

  static Future<void> _writeCrashLog(String error, String stack) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logFile = File('${dir.path}/crash.log');
      final timestamp = DateTime.now().toIso8601String();
      final entry = '[$timestamp]\n$error\n$stack\n\n';
      // v1.0.22 P3-B: cap crash.log at 1 MB with one rotated sidecar
      // (~2 MB total). Prevents a tight crash loop from ballooning the
      // file. Rotation is handled inside [appendWithRotation] —
      // pre-write size check + .1 sidecar shift, fail-soft on any IO
      // error so the existing swallow-all contract is preserved.
      await appendWithRotation(logFile, entry);
    } catch (_) {}
  }
}

class _AndroidCrashEntry {
  final String timestamp;
  final String thread;
  final String exceptionType;
  const _AndroidCrashEntry({
    required this.timestamp,
    required this.thread,
    required this.exceptionType,
  });
}

// ── Remote reporter interface ──────────────────────────────────────────────

/// Implement this to forward errors to Sentry, Crashlytics, or any backend.
abstract class RemoteReporter {
  /// Report an error to the remote service.
  void report(String error, StackTrace stack);
}

// ── Example Sentry implementation (uncomment after adding sentry_flutter) ──
//
// import 'package:sentry_flutter/sentry_flutter.dart';
//
// class SentryReporter implements RemoteReporter {
//   @override
//   void report(String error, StackTrace stack) {
//     Sentry.captureException(error, stackTrace: stack);
//   }
// }
//
// In main():
//   await SentryFlutter.init(
//     (options) => options.dsn = 'https://xxx@sentry.io/xxx',
//     appRunner: () {
//       ErrorLogger.init(reporter: SentryReporter());
//       runApp(...);
//     },
//   );
