import '../../domain/models/relay_profile.dart';

/// A candidate the selector may pick as the next dialer-proxy entry.
///
/// Phase 1B scope: three kinds only.
///   - [direct]             — no relay, go straight to the exit node
///   - [officialCommercial] — relay materialised from a persisted [RelayProfile]
///   - [officialAccess]     — reserved; no Phase 1B source populates it
///
/// `superPeer` is deliberately NOT in this enum. It stays as a value in
/// [RelaySource] (for forward-compatible JSON) but never becomes a candidate.
/// Any code path that needs to reason about superPeer has to go through
/// [RelayProfile.source] and a deliberate legal-review gate, not the
/// candidate pool.
enum RelayCandidateKind { direct, officialCommercial, officialAccess }

/// A proposal for "what to dial through" — one row in the candidate pool.
///
/// IDs:
///   - direct: `direct:<profileId>`
///   - commercial: `commercial:<host>:<port>`
///   - officialAccess: `official:<id>` (reserved; no constructor today)
///
/// The ID is the metrics key, so direct candidates are scoped per profile —
/// never a single global "direct" row. Different subscriptions, different
/// exit networks, different numbers; merging them into one bucket would
/// pull the selector toward whichever profile was probed most recently.
class RelayCandidate {
  final String id;
  final RelayCandidateKind kind;

  /// mihomo outbound type. Populated for `direct` too (it's the exit node's
  /// type), so [ProtocolRanker] can rank direct paths by their exit protocol.
  final String type;

  /// For relay candidates: the relay's host.
  /// For direct candidates: the exit node's host.
  final String host;
  final int port;

  /// Protocol-specific fields (uuid, tls, reality-opts, network, …).
  /// Drives [ProtocolRanker]; opaque to the selector itself.
  final Map<String, dynamic> extras;

  /// Coarse region code ("CN-East", "JP", …). Never a precise city.
  final String? region;

  /// Set for [RelayCandidateKind.direct]; may be null for relay kinds.
  final String? profileId;

  /// Carried through from the source [RelayProfile] so that
  /// [toRelayProfile] reconstructs the same targeting semantics.
  /// Silently losing these in the round-trip would promote an
  /// `allowlistNames` profile into `allVless` and widen the relay's
  /// blast radius — guarded by a round-trip test.
  final RelayTargetMode targetMode;
  final List<String> allowlistNames;

  const RelayCandidate._({
    required this.id,
    required this.kind,
    required this.type,
    required this.host,
    required this.port,
    this.extras = const {},
    this.region,
    this.profileId,
    this.targetMode = RelayTargetMode.allVless,
    this.allowlistNames = const [],
  });

  bool get isDirect => kind == RelayCandidateKind.direct;

  /// A direct candidate tied to a specific subscription profile.
  ///
  /// `exitHost` / `exitPort` / `exitType` describe the *exit* node — the one
  /// mihomo would dial without any relay fronting. Phase 1B uses a single
  /// representative exit per profile (caller decides which one: typically the
  /// currently selected node in the profile's url-test group, or the first
  /// node if none is selected).
  factory RelayCandidate.direct({
    required String profileId,
    required String exitHost,
    required int exitPort,
    required String exitType,
    Map<String, dynamic> exitExtras = const {},
    String? region,
  }) {
    return RelayCandidate._(
      id: 'direct:$profileId',
      kind: RelayCandidateKind.direct,
      type: exitType,
      host: exitHost,
      port: exitPort,
      extras: Map<String, dynamic>.unmodifiable(exitExtras),
      region: region,
      profileId: profileId,
    );
  }

  /// A commercial relay candidate materialised from a Phase 1A [RelayProfile].
  ///
  /// Throws [ArgumentError] if the profile is not [RelayProfile.isValid] —
  /// the selector must not reason about invalid profiles.
  factory RelayCandidate.commercial(RelayProfile profile, {String? region}) {
    if (!profile.isValid) {
      throw ArgumentError(
          'RelayCandidate.commercial requires a valid RelayProfile '
          '(source must be commercial; host/port/type non-empty).');
    }
    return RelayCandidate._(
      id: 'commercial:${profile.host}:${profile.port}',
      kind: RelayCandidateKind.officialCommercial,
      type: profile.type,
      host: profile.host,
      port: profile.port,
      extras: Map<String, dynamic>.unmodifiable(profile.extras),
      region: region,
      targetMode: profile.targetMode,
      allowlistNames: List<String>.unmodifiable(profile.allowlistNames),
    );
  }

  /// Convert a relay candidate back into the [RelayProfile] shape
  /// [RelayInjector] consumes. Direct candidates have no relay to inject
  /// and throw [StateError] — callers should branch on [isDirect] first.
  RelayProfile toRelayProfile() {
    if (isDirect) {
      throw StateError(
          'RelayCandidate.direct has no relay to inject; branch on isDirect.');
    }
    return RelayProfile(
      enabled: true,
      type: type,
      host: host,
      port: port,
      extras: extras,
      targetMode: targetMode,
      allowlistNames: allowlistNames,
    );
  }
}
