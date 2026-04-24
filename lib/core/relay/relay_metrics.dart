import 'relay_selector.dart';

/// The record of a single probe attempt against a [RelayCandidate].
///
/// Produced by `RelayProbeService` (A2-part-3); consumed by [RelayMetrics].
/// Lives in this file because metrics owns the storage shape and the
/// selector already has a read-only view of the aggregates — the probe
/// service depends on this file, not the other way around.
class ProbeResult {
  /// True when the target answered (TCP handshake completed; TLS handshake
  /// completed when required). `reachable == false` can still carry a
  /// meaningful [errorClass].
  final bool reachable;

  /// Round-trip latency in ms for successful probes. Null for failures.
  final int? latencyMs;

  /// Coarse, closed-set classification of what went wrong. Probe service
  /// owns the exact set of values; metrics does not interpret it, it only
  /// propagates to telemetry consumers. Null when `reachable == true`.
  final String? errorClass;

  /// Wall-clock timestamp the probe completed. Only retained in memory —
  /// never serialised to telemetry with more precision than a bucket.
  final DateTime at;

  const ProbeResult({
    required this.reachable,
    required this.at,
    this.latencyMs,
    this.errorClass,
  });
}

/// In-memory aggregate of probe outcomes and usage accounting per
/// candidate. A2-part-2 scope: everything lives in RAM; persistence of
/// cumulative usage is deferred to a later step so this PR can land
/// without touching async init / SettingsService.
///
/// Thread safety: this class is **not** thread-safe. In the YueLink
/// architecture RelayMetrics is touched from the main isolate only — the
/// probe service, the selector, and any telemetry walker all run there.
/// If that ever changes, add synchronisation; don't add `async` to the
/// methods below.
class RelayMetrics implements RelayMetricsView {
  /// Per-candidate ring buffer depth. 20 matches the Phase 1B spec and is
  /// wide enough that a single flaky probe doesn't dominate p50 while
  /// staying small enough to keep per-id allocation trivial.
  static const maxHistorySize = 20;

  final Map<String, List<ProbeResult>> _history = {};
  final Map<String, Duration> _cumulativeUsage = {};

  /// Append a probe outcome. Older entries beyond [maxHistorySize] are
  /// discarded from the head of the buffer (FIFO); the most recent
  /// [maxHistorySize] survive.
  void record(String candidateId, ProbeResult result) {
    final list = _history.putIfAbsent(candidateId, () => <ProbeResult>[]);
    list.add(result);
    if (list.length > maxHistorySize) {
      list.removeRange(0, list.length - maxHistorySize);
    }
  }

  /// Accumulate usage time against [candidateId]. Used by telemetry
  /// (bucketed via [cumulativeUsageBucket]); never consulted by the
  /// selector — Phase 1B contract keeps usage off the decision path.
  void addUsage(String candidateId, Duration d) {
    final current = _cumulativeUsage[candidateId] ?? Duration.zero;
    _cumulativeUsage[candidateId] = current + d;
  }

  /// Return the most recent [n] probe results, oldest-first. Empty list
  /// when the candidate has no history. The returned list is unmodifiable
  /// so callers can't silently mutate the ring buffer.
  List<ProbeResult> recent(String candidateId, {int n = 10}) {
    final list = _history[candidateId];
    if (list == null || list.isEmpty) return const [];
    final start = list.length > n ? list.length - n : 0;
    return List<ProbeResult>.unmodifiable(list.sublist(start));
  }

  /// p50 latency across the current ring buffer, considering only
  /// successful probes. Null when there are no successes on record.
  /// Even-count median uses the lower of the two middle values (integer,
  /// deterministic — callers can rely on identical buffers producing
  /// identical selector behaviour across runs).
  @override
  int? p50Latency(String candidateId) {
    final list = _history[candidateId];
    if (list == null || list.isEmpty) return null;
    final latencies = <int>[];
    for (final r in list) {
      if (r.reachable && r.latencyMs != null) {
        latencies.add(r.latencyMs!);
      }
    }
    if (latencies.isEmpty) return null;
    latencies.sort();
    return latencies[(latencies.length - 1) ~/ 2];
  }

  /// Share of probes in the ring buffer that were unreachable, 0.0..1.0.
  /// Empty history → 0.0. This is deliberate: a brand-new candidate must
  /// not be excluded by the selector's failure filter just for lacking
  /// history (see [RelayMetricsView] contract).
  @override
  double failureRate(String candidateId) {
    final list = _history[candidateId];
    if (list == null || list.isEmpty) return 0.0;
    var failures = 0;
    for (final r in list) {
      if (!r.reachable) failures++;
    }
    return failures / list.length;
  }

  /// Accumulated usage time. Zero when unknown. Precise value is for
  /// internal comparisons only; telemetry must go through
  /// [cumulativeUsageBucket].
  Duration cumulativeUsage(String candidateId) {
    return _cumulativeUsage[candidateId] ?? Duration.zero;
  }

  /// Closed-set bucket for telemetry. Edges chosen to match the Phase 1B
  /// terminal spec; equality to a boundary falls into the higher bucket
  /// (e.g. exactly 1h → "1-6h") so boundaries are unambiguous.
  String cumulativeUsageBucket(String candidateId) {
    final d = cumulativeUsage(candidateId);
    if (d < const Duration(hours: 1)) return '<1h';
    if (d < const Duration(hours: 6)) return '1-6h';
    if (d < const Duration(hours: 24)) return '6-24h';
    if (d < const Duration(days: 7)) return '1-7d';
    return '>7d';
  }
}
