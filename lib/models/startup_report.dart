import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Standard error codes for startup diagnostics.
abstract class StartupError {
  static const soLoadFailed = 'E001_SO_LOAD_FAILED';
  static const initCoreFailed = 'E002_INIT_CORE_FAILED';
  static const vpnPermissionDenied = 'E003_VPN_PERMISSION_DENIED';
  static const vpnFdInvalid = 'E004_VPN_FD_INVALID';
  static const configBuildFailed = 'E005_CONFIG_BUILD_FAILED';
  static const coreStartFailed = 'E006_CORE_START_FAILED';
  static const apiTimeout = 'E007_API_TIMEOUT';
  static const coreDiedAfterStart = 'E008_CORE_DIED_AFTER_START';
  static const geoFilesFailed = 'E009_GEO_FILES_FAILED';
}

/// A single step in the core startup sequence.
class StartupStep {
  final String name;
  final bool success;
  final String? errorCode;
  final String? error;
  final String? detail;
  final int durationMs;

  const StartupStep({
    required this.name,
    required this.success,
    this.errorCode,
    this.error,
    this.detail,
    required this.durationMs,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'success': success,
        if (errorCode != null) 'errorCode': errorCode,
        if (error != null) 'error': error,
        if (detail != null) 'detail': detail,
        'durationMs': durationMs,
      };

  factory StartupStep.fromJson(Map<String, dynamic> json) => StartupStep(
        name: json['name'] as String,
        success: json['success'] as bool,
        errorCode: json['errorCode'] as String?,
        error: json['error'] as String?,
        detail: json['detail'] as String?,
        durationMs: json['durationMs'] as int? ?? 0,
      );

  @override
  String toString() {
    final status = success ? 'OK' : 'FAIL';
    final code = errorCode != null ? ' [$errorCode]' : '';
    final err = error != null ? ' — $error' : '';
    return '[$status] $name (${durationMs}ms)$code$err';
  }
}

/// Full report of a startup attempt.
class StartupReport {
  final DateTime timestamp;
  final String platform;
  final bool overallSuccess;
  final List<StartupStep> steps;
  final String? failedStep;
  final List<String> coreLogs;

  const StartupReport({
    required this.timestamp,
    required this.platform,
    required this.overallSuccess,
    required this.steps,
    this.failedStep,
    this.coreLogs = const [],
  });

  /// Human-readable summary: "[errorCode] step: message"
  String? get failureSummary {
    if (overallSuccess) return null;
    final failed = steps.where((s) => !s.success).firstOrNull;
    if (failed == null) return failedStep;
    final code = failed.errorCode != null ? '[${failed.errorCode}] ' : '';
    final err = failed.error ?? 'unknown error';
    return '$code${failed.name}: $err';
  }

  /// Detailed multi-line report for debugging / clipboard copy.
  String toDebugString() {
    final buf = StringBuffer();
    buf.writeln('=== Startup Report (${timestamp.toIso8601String()}) ===');
    buf.writeln('Platform: $platform');
    buf.writeln('Result: ${overallSuccess ? "SUCCESS" : "FAILED"}');
    if (failedStep != null) buf.writeln('Failed at: $failedStep');
    buf.writeln('');
    buf.writeln('Steps:');
    for (final step in steps) {
      buf.writeln('  $step');
      if (step.detail != null) {
        for (final line in step.detail!.split('\n')) {
          buf.writeln('    $line');
        }
      }
    }
    final totalMs = steps.fold<int>(0, (sum, s) => sum + s.durationMs);
    buf.writeln('Total: ${totalMs}ms');

    if (coreLogs.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Go Core Logs (last ${coreLogs.length} lines):');
      for (final line in coreLogs) {
        buf.writeln('  $line');
      }
    }

    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'platform': platform,
        'overallSuccess': overallSuccess,
        'failedStep': failedStep,
        'steps': steps.map((s) => s.toJson()).toList(),
        'coreLogs': coreLogs,
      };

  factory StartupReport.fromJson(Map<String, dynamic> json) => StartupReport(
        timestamp: DateTime.parse(json['timestamp'] as String),
        platform: json['platform'] as String,
        overallSuccess: json['overallSuccess'] as bool,
        failedStep: json['failedStep'] as String?,
        steps: (json['steps'] as List)
            .map((s) => StartupStep.fromJson(s as Map<String, dynamic>))
            .toList(),
        coreLogs: (json['coreLogs'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
      );

  /// Save report to disk.
  static Future<void> save(StartupReport report) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final file = File('${appDir.path}/startup_report.json');
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report.toJson()));
    } catch (_) {}
  }

  /// Load the most recent saved report.
  static Future<StartupReport?> load() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final file = File('${appDir.path}/startup_report.json');
      if (!file.existsSync()) return null;
      final json = jsonDecode(await file.readAsString());
      return StartupReport.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
