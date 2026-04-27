import '../../domain/models/relay_profile.dart';
import 'relay_candidate.dart';
import 'relay_metrics.dart';
import 'relay_selector.dart';

/// Outcome of [selectRelayForColdStart].
class RelaySelectionOutcome {
  /// Profile to inject for THIS start, or null when direct was chosen.
  /// Direct is the safe fallback whenever the selector can't justify a
  /// relay — including the common "no metrics yet" case.
  final RelayProfile? profile;

  /// Which kind of candidate the selector picked. Always non-null.
  /// Recorded on `StartupReport.relay.selectedKind`.
  final RelayCandidateKind selectedKind;

  /// Why the selector picked it. Sourced from [LowestLatencySelector] when
  /// that's the implementation in use; null when a custom selector without
  /// a `lastReason` field was injected (this happens only in tests).
  final String? selectedReason;

  const RelaySelectionOutcome({
    required this.profile,
    required this.selectedKind,
    required this.selectedReason,
  });
}

/// Wires the cold-start selector. A5a edition: the metrics buffer is
/// always empty (the probe service hasn't run yet — A5b lands that), so
/// [LowestLatencySelector] takes its fallback path and returns direct
/// for every user today. The wiring exists so A5b can replace the empty
/// metrics with a populated one without touching CoreManager.
///
/// **This function does NOT mutate persisted state.** In particular it
/// does not call [RelayProfileService.clear] when direct is selected.
/// Cold-start with empty metrics ALWAYS picks direct, and clearing the
/// persisted profile every cold-start would silently delete the user's
/// saved relay configuration — an irreversible state mutation triggered
/// by a routine probe-table emptiness condition. Persisted-profile
/// cleanup is reserved for an explicit "disable relay" user action.
///
/// The function is a pure dependency on its parameters: the persisted
/// profile is passed in (the caller loaded it), the selector and metrics
/// are injectable. No global I/O, no SharedPreferences read. Easy to
/// test deterministically.
Future<RelaySelectionOutcome> selectRelayForColdStart({
  RelayProfile? persistedProfile,
  RelaySelector? selector,
  RelayMetricsView? metrics,
}) async {
  final candidates = <RelayCandidate>[
    // A5a placeholder. A5b will replace `_default` with the active
    // subscription's id and surface the real exit host/port/type so
    // probes can actually measure the direct path. Until then, the
    // direct candidate's host/port don't matter — empty metrics means
    // selector never reads them, and RelayInjector is never called for
    // direct (we return profile: null below).
    RelayCandidate.direct(
      profileId: '_default',
      exitHost: 'unknown',
      exitPort: 0,
      exitType: 'unknown',
    ),
  ];
  if (persistedProfile != null && persistedProfile.isValid) {
    candidates.add(RelayCandidate.commercial(persistedProfile));
  }

  final s = selector ?? LowestLatencySelector();
  final m = metrics ?? RelayMetrics();
  final picked = await s.select(candidates, m);

  return RelaySelectionOutcome(
    profile: picked.isDirect ? null : picked.toRelayProfile(),
    selectedKind: picked.kind,
    selectedReason: s is LowestLatencySelector ? s.lastReason : null,
  );
}
