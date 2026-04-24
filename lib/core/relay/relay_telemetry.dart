import 'protocol_ranker.dart';
import 'relay_candidate.dart';
import 'relay_metrics.dart';
import 'relay_probe_service.dart';

/// Closed-set props builders for Phase 1B relay telemetry.
///
/// All Phase 1B emitters MUST go through these helpers — direct calls
/// to `Telemetry.event(TelemetryEvents.relayProbe, props: {...})` with
/// hand-rolled maps would defeat the privacy contract. The helpers
/// produce only the keys listed below; the corresponding privacy test
/// sweep in `test/services/relay_telemetry_test.dart` walks both
/// builders against representative inputs and asserts no host / IP /
/// port / server / uuid / password / address ever appears in keys or
/// values.
///
/// Allowed keys:
///   relay_probe      → candidate_kind, reachable, latency_bucket,
///                      error_class, protocol_rank_tier
///   relay_selected   → kind, reason
///
/// Anything else is an addition that needs a deliberate review.
class RelayTelemetry {
  RelayTelemetry._();

  /// Build props for [TelemetryEvents.relayProbe].
  static Map<String, dynamic> probe(
    RelayCandidate candidate,
    ProbeResult result,
  ) {
    return {
      'candidate_kind': candidate.kind.name,
      'reachable': result.reachable,
      'latency_bucket': _latencyBucket(result),
      'error_class': result.errorClass ?? 'none',
      'protocol_rank_tier': ProtocolRanker.tier(
        ProtocolRanker.rank(candidate.type, candidate.extras),
      ),
    };
  }

  /// Build props for [TelemetryEvents.relaySelected].
  /// `reason` is omitted (not present as a key) when null — the dashboard
  /// reads "no reason" from key absence rather than a magic string.
  static Map<String, dynamic> selected(
    RelayCandidateKind kind,
    String? reason,
  ) {
    return {
      'kind': kind.name,
      'reason': ?reason,
    };
  }

  /// Latency bucket schema:
  ///   reachable + latency known → numeric tier
  ///   unreachable + errorClass=='timeout' → "timeout"
  ///   unreachable + other failure → "fail"
  ///
  /// Splitting "timeout" from "fail" preserves the slow-network vs
  /// broken-endpoint distinction at dashboard granularity without needing
  /// to cross-reference error_class.
  static String _latencyBucket(ProbeResult r) {
    if (r.reachable && r.latencyMs != null) {
      final ms = r.latencyMs!;
      if (ms < 50) return '<50ms';
      if (ms < 150) return '50-150';
      if (ms < 500) return '150-500';
      return '>500';
    }
    if (r.errorClass == ProbeError.timeout) return 'timeout';
    return 'fail';
  }
}
