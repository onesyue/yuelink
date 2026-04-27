/// Coarse categorisation of the current network carrier.
///
/// Phase 1B only needs this to bucket telemetry samples — decisions never
/// branch on it. `unknown` is the defensive default when the platform
/// adapter can't answer.
enum NetworkKind { wifi, cellular, ethernet, unknown }

/// NAT classification, intentionally collapsed to a two-way split plus
/// `unknown`. Full STUN RFC taxonomy (full-cone / restricted / port-
/// restricted / symmetric) isn't observable with a single pair of binding
/// requests, and the Phase 1B consumer (telemetry only) doesn't need the
/// extra resolution. Anything beyond "is it symmetric?" lands in Phase 2+.
enum NatKind { nonSymmetric, symmetric, unknown }

/// Snapshot of the client-side network as it looked at [sampledAt].
///
/// **No external-address field by design.** The STUN probe learns the
/// public IP/port the NAT mapped the request to — that address never
/// enters this model, is never persisted, and never leaves telemetry
/// in raw form. The two NAT-adjacent fields exposed here are strictly
/// classifications:
///   - [hasPublicIpv6]:   "the box has a globally-unicast v6 address" bit
///   - [hasIpv6Outbound]: "we can open a TCP socket to a v6 target" bit
///   - [natKind]:         classification derived locally from the pair of
///                        STUN results, not the raw addresses themselves
///
/// These two IPv6 bits are kept separate on purpose — in the wild an
/// interface can carry a global-unicast v6 address while the operator
/// firewall blocks outbound 443, or the reverse. Treating them as one
/// signal would lose information the Super-Peer feasibility study depends
/// on.
class NetworkProfile {
  final bool hasIpv6Outbound;
  final bool hasPublicIpv6;
  final NatKind natKind;
  final NetworkKind networkKind;
  final DateTime sampledAt;

  const NetworkProfile({
    required this.hasIpv6Outbound,
    required this.hasPublicIpv6,
    required this.natKind,
    required this.networkKind,
    required this.sampledAt,
  });

  /// Serialise to a JSON-safe map for SettingsService cache. Field
  /// names match the Dart property names — they're internal cache keys,
  /// not telemetry. Telemetry uses the snake_case schema in
  /// `RelayTelemetry.networkProfileSample`.
  Map<String, dynamic> toJson() => {
        'hasIpv6Outbound': hasIpv6Outbound,
        'hasPublicIpv6': hasPublicIpv6,
        'natKind': natKind.name,
        'networkKind': networkKind.name,
        'sampledAt': sampledAt.toIso8601String(),
      };

  /// Round-trip from a SettingsService cache entry. Defensive against
  /// missing / malformed fields — returns sensible fallbacks rather than
  /// throwing, so a cache written by a future schema doesn't crash an
  /// older client trying to read it.
  factory NetworkProfile.fromJson(Map<String, dynamic> json) {
    return NetworkProfile(
      hasIpv6Outbound: json['hasIpv6Outbound'] as bool? ?? false,
      hasPublicIpv6: json['hasPublicIpv6'] as bool? ?? false,
      natKind: NatKind.values.firstWhere(
        (k) => k.name == json['natKind'],
        orElse: () => NatKind.unknown,
      ),
      networkKind: NetworkKind.values.firstWhere(
        (k) => k.name == json['networkKind'],
        orElse: () => NetworkKind.unknown,
      ),
      sampledAt:
          DateTime.tryParse(json['sampledAt'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}
