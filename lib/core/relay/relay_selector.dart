import 'relay_candidate.dart';
import 'protocol_ranker.dart';

/// Read-only view on relay metrics.
///
/// Phase 1B introduces this abstraction so the selector can be built and
/// tested without a concrete metrics store (the full [RelayMetrics]
/// implementation lands in A2-part-2). The full class will `implements`
/// this interface, so selector tests written against it stay valid.
abstract class RelayMetricsView {
  /// p50 latency across the recent probe window for [candidateId],
  /// or null when there's no usable history.
  int? p50Latency(String candidateId);

  /// Share of failed probes in the recent window, 0.0 … 1.0.
  /// Returns 0.0 when there's no history — the selector's unhealthy-filter
  /// therefore never excludes a brand-new candidate, only one that has been
  /// actively failing.
  double failureRate(String candidateId);
}

/// Selects the candidate the next cold-start should dial through.
///
/// Contract: under any normal configuration the selector returns a
/// candidate and never throws — on ambiguity or probe failure the direct
/// candidate wins, so direct is always a safe choice. The one exception
/// is a caller bug: if the candidate list contains no direct entry at
/// all, [StateError] is thrown to surface the misconfiguration loudly
/// rather than silently pick a relay as a fallback.
abstract class RelaySelector {
  Future<RelayCandidate> select(
    List<RelayCandidate> candidates,
    RelayMetricsView metrics,
  );
}

/// Why the selector picked what it picked. Closed set; telemetry-safe.
abstract class RelaySelectReason {
  static const lowestLatency = 'lowest_latency';
  static const conservativeBias = 'conservative_bias';
  static const fallback = 'fallback';
  static const cached = 'cached'; // reserved for A2-part-2 cache reuse path
}

/// Default selector.
///
/// Flow:
///   1. Require at least one direct candidate; synthesise none if missing —
///      caller owes us one (one per active profile). No direct → throw, so
///      a configuration bug is loud, not silent.
///   2. Exclude relay candidates whose recent failure rate > [failureThreshold].
///   3. Sort remaining relays by p50 latency ascending.
///   4. Tie-break same p50 by [ProtocolRanker.rank] descending.
///   5. Conservative bias: if the best relay's p50 isn't meaningfully lower
///      than direct's, choose direct. The gap required is the *larger* of
///      [toleranceRatio] × topRelay.p50 and [toleranceMinMs] — so small
///      absolute gaps (wifi jitter) never trigger a switch.
///   6. No relay history / all filtered out → direct. Fallback is deliberate.
///
/// `lastReason` records why the most recent select() returned what it did.
/// The selector is stateless aside from this breadcrumb; callers can read
/// it to populate StartupReport / telemetry without threading a result
/// object through every layer.
class LowestLatencySelector implements RelaySelector {
  /// Relay candidates with a higher observed failure rate are excluded
  /// from sorting. A brand-new candidate (no history) has failureRate 0
  /// and is always eligible.
  final double failureThreshold;

  /// Conservative-bias thresholds, combined as `max(ratio, minMs)`.
  /// 20% / 80 ms mirrors mihomo's `tolerance` parameter style —
  /// a pure ratio would chase noise on fast links; a pure absolute
  /// number would over-switch on slow ones.
  final double toleranceRatio;
  final int toleranceMinMs;

  String? _lastReason;
  String? get lastReason => _lastReason;

  LowestLatencySelector({
    this.failureThreshold = 0.5,
    this.toleranceRatio = 0.20,
    this.toleranceMinMs = 80,
  });

  @override
  Future<RelayCandidate> select(
    List<RelayCandidate> candidates,
    RelayMetricsView metrics,
  ) async {
    final direct = _findDirect(candidates);
    if (direct == null) {
      throw StateError(
          'LowestLatencySelector requires at least one direct candidate; '
          'callers must always include one (one per active profile).');
    }

    final relays = candidates.where((c) => !c.isDirect).toList();

    // Filter relays by observed failure rate. Note: a candidate with no
    // history has failureRate 0.0 (see RelayMetricsView contract) so it
    // stays eligible — we don't punish "new" candidates, only failing ones.
    final healthy = relays
        .where((c) => metrics.failureRate(c.id) <= failureThreshold)
        .toList();

    // No relay ever probed / all relays filtered out → direct.
    if (healthy.isEmpty) {
      _lastReason = RelaySelectReason.fallback;
      return direct;
    }

    // Rank known-latency candidates. If none of the healthy relays has a
    // measured p50 yet, behave like "no history" and fall back to direct —
    // we refuse to guess a cold relay is faster than direct.
    final withLatency = healthy
        .where((c) => metrics.p50Latency(c.id) != null)
        .toList();
    if (withLatency.isEmpty) {
      _lastReason = RelaySelectReason.fallback;
      return direct;
    }

    withLatency.sort((a, b) {
      final la = metrics.p50Latency(a.id)!;
      final lb = metrics.p50Latency(b.id)!;
      if (la != lb) return la.compareTo(lb);
      // Tie-break only — rank never outranks a lower p50.
      final ra = ProtocolRanker.rank(a.type, a.extras);
      final rb = ProtocolRanker.rank(b.type, b.extras);
      return rb.compareTo(ra);
    });

    final topRelay = withLatency.first;
    final topP50 = metrics.p50Latency(topRelay.id)!;

    // Conservative bias only applies when we actually have a direct p50 to
    // compare against. If direct was never measured, the relay's concrete
    // number wins — there's nothing to bias toward.
    final directP50 = metrics.p50Latency(direct.id);
    if (directP50 != null) {
      final ratioGap = (topP50 * toleranceRatio).round();
      final requiredGap =
          ratioGap > toleranceMinMs ? ratioGap : toleranceMinMs;
      if (directP50 - topP50 < requiredGap) {
        _lastReason = RelaySelectReason.conservativeBias;
        return direct;
      }
    }

    _lastReason = RelaySelectReason.lowestLatency;
    return topRelay;
  }

  RelayCandidate? _findDirect(List<RelayCandidate> candidates) {
    for (final c in candidates) {
      if (c.isDirect) return c;
    }
    return null;
  }
}
