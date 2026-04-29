import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/models/startup_report.dart';
import '../../shared/telemetry.dart';
import '../relay/relay_candidate.dart';
import 'relay_injector.dart';

/// Diagnostics surface for the [CoreManager] startup pipeline.
///
/// Was inlined in `core_manager.dart` (~150 lines across `_step`,
/// `_finishReport`, `_errorCodeFor`, `_relayReportFields`). Pulling them
/// out frees CoreManager from the report-construction + telemetry +
/// disk-persistence side concerns and lets the rules be unit-tested
/// without spinning up a real CoreManager.
///
/// Kept as top-level functions (not a class) because the surface is
/// stateless — CoreManager owns `lastReport`/`lastRelayResult`/
/// `lastSelectedKind`/`lastSelectedReason` and threads them in at call
/// time. The contract: callers pass step records + relay state, get
/// back a hydrated `StartupReport` with telemetry already emitted.

/// Run a single startup step with timing, structured success/failure
/// recording into [steps], and a `[BOOT]`-tagged debug print.
///
/// On success the action's returned `detail` string is captured (used
/// by the StartupReport viewer to surface per-step context). On failure
/// the exception is recorded with [errorCode] and rethrown — the
/// caller's outer try/catch decides what to do with it.
Future<void> runStartupStep(
  List<StartupStep> steps,
  String name,
  String errorCode,
  Future<String> Function() action,
) async {
  final sw = Stopwatch()..start();
  try {
    final detail = await action();
    sw.stop();
    steps.add(
      StartupStep(
        name: name,
        success: true,
        detail: detail,
        durationMs: sw.elapsedMilliseconds,
      ),
    );
    debugPrint('[CoreManager] ✓ $name (${sw.elapsedMilliseconds}ms) $detail');
  } catch (e) {
    sw.stop();
    steps.add(
      StartupStep(
        name: name,
        success: false,
        errorCode: errorCode,
        error: e.toString(),
        durationMs: sw.elapsedMilliseconds,
      ),
    );
    debugPrint(
      '[CoreManager] ✗ $name [$errorCode] (${sw.elapsedMilliseconds}ms) $e',
    );
    rethrow;
  }
}

/// Read up to 100 lines from the Go-side `core.log` (logrus output).
/// Returns empty list on read failure — diagnostics must never abort
/// the startup-report path.
Future<List<String>> _readCoreLogTail() async {
  try {
    final appDir = await getApplicationSupportDirectory();
    final logFile = File('${appDir.path}/core.log');
    if (!logFile.existsSync()) return const [];
    final lines = await logFile.readAsLines();
    if (lines.length <= 100) return lines;
    return lines.sublist(lines.length - 100);
  } catch (e) {
    debugPrint('[StartupDiagnostics] failed to read core.log: $e');
    return const [];
  }
}

/// Build a [StartupReport] from the recorded steps + relay state, emit
/// the appropriate telemetry event, and persist the report to disk
/// (fire-and-forget). Caller stores the returned report on
/// `CoreManager.lastReport`.
///
/// Telemetry rules (matching the previous inline version):
///   * success → `startupOk` with `total_ms`, `steps`,
///     `slow` boolean (>5 s), `slowest_step`, `slowest_ms`.
///   * failure → `startupFail` with `step` + `code`, marked priority
///     so it survives the buffer overflow.
Future<StartupReport> buildAndPersistStartupReport({
  required List<StartupStep> steps,
  required bool success,
  required String? failedStep,
  required Map<String, dynamic>? relayReportFields,
}) async {
  final coreLogs = await _readCoreLogTail();

  final report = StartupReport(
    timestamp: DateTime.now(),
    platform: Platform.operatingSystem,
    overallSuccess: success,
    steps: steps,
    failedStep: failedStep,
    coreLogs: coreLogs,
    relay: relayReportFields,
  );

  debugPrint(report.toDebugString());

  if (success) {
    final totalMs = steps.fold<int>(0, (a, s) => a + s.durationMs);
    // Identify the bottleneck step. Lets the telemetry dashboard
    // attribute slow launches to a specific phase (ensureGeo on slow
    // CDN, waitApi on a sluggish mihomo cold start, buildConfig on a
    // huge subscription, etc.) without us having to ship a wider
    // event-shape change.
    StartupStep? slowest;
    for (final s in steps) {
      if (slowest == null || s.durationMs > slowest.durationMs) slowest = s;
    }
    // 5 s is the empirical "users start asking if the app is broken"
    // threshold across desktop + mobile. Boolean rather than numeric
    // so the dashboard can chart slow-launch share without a bucket.
    const slowThresholdMs = 5000;
    Telemetry.event(
      TelemetryEvents.startupOk,
      props: {
        'total_ms': totalMs,
        'steps': steps.length,
        if (totalMs > slowThresholdMs) 'slow': true,
        if (slowest != null) 'slowest_step': slowest.name,
        if (slowest != null) 'slowest_ms': slowest.durationMs,
      },
    );
  } else {
    Telemetry.event(
      TelemetryEvents.startupFail,
      priority: true,
      props: {
        'step': failedStep ?? 'unknown',
        'code': errorCodeForStep(failedStep),
      },
    );
  }

  // Save to disk (fire-and-forget) — caller doesn't await.
  StartupReport.save(report);
  return report;
}

/// Build the `relay` block for [StartupReport]. Returns null when the
/// selector has never run (e.g. before the first start). Once the
/// selector is wired into every start path, every successful or
/// failed start records its `selectedKind` / `selectedReason` here —
/// telemetry sees the consistent shape.
Map<String, dynamic>? buildRelayReportFields({
  required RelayApplyResult? lastRelayResult,
  required RelayCandidateKind? lastSelectedKind,
  required String? lastSelectedReason,
}) {
  if (lastRelayResult == null && lastSelectedKind == null) return null;
  return {
    if (lastRelayResult != null) 'injected': lastRelayResult.injected,
    if (lastRelayResult != null && lastRelayResult.targetCount > 0)
      'targetCount': lastRelayResult.targetCount,
    if (lastRelayResult != null && lastRelayResult.skipReason != null)
      'skipReason': lastRelayResult.skipReason,
    if (lastSelectedKind != null) 'selectedKind': lastSelectedKind.name,
    'selectedReason': ?lastSelectedReason,
  };
}

/// Stable error codes for dashboard grouping. Mirrors the E002–E009
/// constants rendered in StartupErrorBanner.
String errorCodeForStep(String? step) {
  switch (step) {
    case 'initCore':
      return 'E002';
    case 'vpnPermission':
      return 'E003';
    case 'startVpn':
      return 'E004';
    case 'buildConfig':
      return 'E005';
    case 'startCore':
      return 'E006';
    case 'waitApi':
      return 'E007';
    case 'waitProxies':
      // Same family as waitApi — REST is up but the proxy graph is
      // not yet usable. Re-uses E007 so dashboard grouping and
      // telemetry counters stay consistent with the commit body
      // contract; the distinct step name preserves diagnostic
      // detail in the StartupReport.
      return 'E007';
    case 'verify':
      return 'E008';
    case 'ensureGeo':
      return 'E009';
    default:
      return 'Exx';
  }
}
