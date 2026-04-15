import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'event_log.dart';
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
  static void captureException(Object error, StackTrace stack,
      {String? source}) {
    _capture(error.toString(), stack, source: source);
  }

  // ── Internal ────────────────────────────────────────────────────────

  static void _capture(String error, StackTrace stack, {String? source}) {
    // 1. Always write to local crash.log
    _writeCrashLog(error, stack.toString());

    // 2. Write to EventLog for quick diagnosis
    final tag = source != null ? '[$source]' : '[Error]';
    EventLog.write('$tag ${error.split('\n').first}');

    // 2b. Forward exception type (not the message) to opt-in telemetry so we
    // can see error shape distribution without leaking payload content.
    final firstLine = error.split('\n').first;
    final typeHint = firstLine.length > 80 ? firstLine.substring(0, 80) : firstLine;
    Telemetry.event(
      TelemetryEvents.crash,
      priority: true,
      props: {
        'src': source ?? 'unknown',
        'type': _typeFromError(typeHint),
      },
    );

    // 3. Forward to remote reporter (release only)
    if (!kReleaseMode || _reporter == null) return;
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

  static Future<void> _writeCrashLog(String error, String stack) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logFile = File('${dir.path}/crash.log');
      final timestamp = DateTime.now().toIso8601String();
      final entry = '[$timestamp]\n$error\n$stack\n\n';
      await logFile.writeAsString(entry, mode: FileMode.append);
    } catch (_) {}
  }
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
