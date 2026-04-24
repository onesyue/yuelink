import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/relay/relay_candidate.dart';
import 'package:yuelink/core/relay/relay_metrics.dart';
import 'package:yuelink/core/relay/relay_selection.dart';
import 'package:yuelink/core/relay/relay_selector.dart';
import 'package:yuelink/domain/models/relay_profile.dart';

const _validCommercial = RelayProfile(
  enabled: true,
  type: 'vless',
  host: 'r.example.com',
  port: 443,
  extras: {'uuid': 'abc'},
);

/// Records two probe results that drive LowestLatencySelector to pick
/// the commercial relay (relay much faster than direct, both healthy).
RelayMetrics _metricsRelayWins() {
  final m = RelayMetrics();
  final now = DateTime.now();
  for (final v in [95, 100, 105]) {
    m.record('commercial:r.example.com:443',
        ProbeResult(reachable: true, latencyMs: v, at: now));
  }
  for (final v in [490, 500, 510]) {
    m.record('direct:_default',
        ProbeResult(reachable: true, latencyMs: v, at: now));
  }
  return m;
}

/// Custom selector that always returns the first non-direct candidate.
/// Used to exercise the "selector lacks lastReason" code path —
/// selectedReason should be null in that case.
class _AlwaysCommercialSelector implements RelaySelector {
  @override
  Future<RelayCandidate> select(
    List<RelayCandidate> candidates,
    RelayMetricsView metrics,
  ) async {
    return candidates.firstWhere((c) => !c.isDirect);
  }
}

void main() {
  group('selectRelayForColdStart — direct fallback paths', () {
    test('no persisted profile → returns direct + fallback reason', () async {
      final r = await selectRelayForColdStart(persistedProfile: null);
      expect(r.profile, isNull);
      expect(r.selectedKind, RelayCandidateKind.direct);
      expect(r.selectedReason, RelaySelectReason.fallback);
    });

    test('disabled persisted profile → direct (invalid → not added to pool)',
        () async {
      final r = await selectRelayForColdStart(
        persistedProfile: const RelayProfile.disabled(),
      );
      expect(r.profile, isNull);
      expect(r.selectedKind, RelayCandidateKind.direct);
      expect(r.selectedReason, RelaySelectReason.fallback);
    });

    test('valid commercial profile + empty metrics → direct (cold relay)',
        () async {
      // A5a is the entire reason this matters: every user today has a
      // valid persisted profile (or none) and an empty metrics buffer.
      // Selector must NOT speculate that a never-probed relay is better
      // than direct.
      final r = await selectRelayForColdStart(
        persistedProfile: _validCommercial,
      );
      expect(r.profile, isNull,
          reason: 'cold-start with no probes must return direct');
      expect(r.selectedKind, RelayCandidateKind.direct);
      expect(r.selectedReason, RelaySelectReason.fallback);
    });
  });

  group('selectRelayForColdStart — relay selection', () {
    test('valid commercial + metrics where relay wins → commercial profile',
        () async {
      final r = await selectRelayForColdStart(
        persistedProfile: _validCommercial,
        metrics: _metricsRelayWins(),
      );
      expect(r.profile, isNotNull);
      expect(r.profile!.host, 'r.example.com');
      expect(r.profile!.port, 443);
      expect(r.profile!.type, 'vless');
      expect(r.profile!.extras['uuid'], 'abc');
      expect(r.selectedKind, RelayCandidateKind.officialCommercial);
      expect(r.selectedReason, RelaySelectReason.lowestLatency);
    });

    test('round-trip preserves targetMode + allowlistNames', () async {
      // Mirrors the A2 round-trip guarantee. If this regresses the relay
      // would silently widen its blast radius from "these specific nodes"
      // to "all VLESS" the next time it gets selected.
      const allowlistProfile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'r.example.com',
        port: 443,
        targetMode: RelayTargetMode.allowlistNames,
        allowlistNames: ['HK-VLESS', 'JP-VLESS'],
      );
      final r = await selectRelayForColdStart(
        persistedProfile: allowlistProfile,
        metrics: _metricsRelayWins(),
      );
      expect(r.profile!.targetMode, RelayTargetMode.allowlistNames);
      expect(r.profile!.allowlistNames, ['HK-VLESS', 'JP-VLESS']);
    });
  });

  group('selectRelayForColdStart — selector reason propagation', () {
    test('default LowestLatencySelector exposes lastReason', () async {
      // direct case → fallback
      final r1 = await selectRelayForColdStart(persistedProfile: null);
      expect(r1.selectedReason, RelaySelectReason.fallback);

      // commercial case → lowest_latency
      final r2 = await selectRelayForColdStart(
        persistedProfile: _validCommercial,
        metrics: _metricsRelayWins(),
      );
      expect(r2.selectedReason, RelaySelectReason.lowestLatency);
    });

    test('custom selector without lastReason → selectedReason is null',
        () async {
      final r = await selectRelayForColdStart(
        persistedProfile: _validCommercial,
        selector: _AlwaysCommercialSelector(),
      );
      expect(r.selectedKind, RelayCandidateKind.officialCommercial);
      expect(r.selectedReason, isNull);
    });
  });

  group('selectRelayForColdStart — pure-function contract (no side effects)',
      () {
    test(
        'persistedProfile is treated as input; function does not mutate it',
        () async {
      // The function takes RelayProfile by parameter; structurally it
      // can't call RelayProfileService.clear (the service isn't
      // imported). This test pins that property by re-checking the
      // input profile is unchanged after a direct-selection run, which
      // would have been the trigger for an erroneous clear() in the
      // earlier draft of the spec.
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'r.example.com',
        port: 443,
        extras: {'uuid': 'abc'},
      );
      final r = await selectRelayForColdStart(persistedProfile: profile);
      // direct selected → r.profile is null but the input is intact
      expect(r.profile, isNull);
      expect(profile.host, 'r.example.com');
      expect(profile.isValid, isTrue);
      expect(profile.extras['uuid'], 'abc');
    });

    test('repeated calls are idempotent for the same inputs', () async {
      // No internal state is accumulated between calls; selecting twice
      // with the same persisted profile + same metrics yields the same
      // outcome. This protects against future refactors that might add
      // hidden caches.
      final m = _metricsRelayWins();
      final a = await selectRelayForColdStart(
        persistedProfile: _validCommercial,
        metrics: m,
      );
      final b = await selectRelayForColdStart(
        persistedProfile: _validCommercial,
        metrics: m,
      );
      expect(a.selectedKind, b.selectedKind);
      expect(a.selectedReason, b.selectedReason);
      expect(a.profile?.host, b.profile?.host);
    });
  });
}
