/// Expand a base log-source list to include rotated sidecars.
///
/// v1.0.22 P3-A (Dart side): the Go core implements size-based
/// rotation of `core.log` — a long session shifts the live file to
/// `core.log.1` / `core.log.2` once it crosses ~5 MB. Without this
/// helper the diagnostic export only reads the live file, so a user
/// reproducing a crash that happened minutes-to-hours ago might find
/// the relevant lines were already shifted into a sidecar by the
/// time the export runs — defeating the purpose of "export
/// diagnostics" as a triage tool.
///
/// Returns names in chronological order — oldest sidecar first, live
/// file last — so the concatenated output reads top-down through
/// time. Non-rotating sources (`crash.log`, `event.log`,
/// `startup_report.json`, …) pass through unchanged.
///
/// Pure function — caller is still responsible for file-existence
/// checks (sidecars are absent on a freshly-installed instance).
List<String> expandRotatedLogSources(
  List<String> bases, {
  int coreLogBackups = 2,
}) {
  final out = <String>[];
  for (final name in bases) {
    if (name == 'core.log') {
      // Oldest first: core.log.2 → core.log.1 → core.log
      for (var i = coreLogBackups; i >= 1; i--) {
        out.add('$name.$i');
      }
    }
    out.add(name);
  }
  return out;
}
