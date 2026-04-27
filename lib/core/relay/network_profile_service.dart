import 'network_profile.dart';
import 'network_profile_adapters.dart';

/// Returns whether the device currently has at least one global-unicast
/// IPv6 address on any non-loopback interface.
///
/// Production implementation (to be wired in A5): enumerates
/// `NetworkInterface.list()`, filters out loopback / link-local (fe80::)
/// / ULA (fc00::/7), and returns true iff any address remains in the
/// `2000::/3` range. Phase 1B keeps this as an injectable boolean so
/// tests never touch the real network stack.
typedef HasPublicIpv6Fn = Future<bool> Function();

/// Probes IPv6 outbound reachability. Semantically distinct from
/// [HasPublicIpv6Fn]: an interface can advertise a global v6 address
/// while the carrier firewall blocks outbound 443, or vice versa.
///
/// Production implementation: `Socket.connect('[2001:4860:4860::8888]', 443,
/// timeout: 3s)` — success → true, any failure → false. Returns, does not
/// throw.
typedef Ipv6ReachableFn = Future<bool> Function();

/// A single STUN binding result. Returned by [StunQueryFn].
///
/// **This record must never be persisted, logged at info level, or cross
/// a telemetry boundary.** The `ip` and `port` values are meaningful only
/// within [NetworkProfileService._probeNat], for comparing two
/// consecutive queries. Once compared, the tuples go out of scope and
/// only the resulting [NatKind] classification travels further.
typedef StunQueryFn = Future<({String ip, int port})?> Function();

/// Reports the current network medium. Production backs to
/// `connectivity_plus` on mobile and interface-name heuristics on desktop;
/// both are best-effort — callers should treat [NetworkKind.unknown] as
/// a normal outcome, not a failure.
typedef NetworkKindProviderFn = Future<NetworkKind> Function();

/// Samples the current client-side network profile.
///
/// Constructor requires all four adapters to be provided — there are no
/// production defaults baked in. The real-adapter wiring lands with the
/// A5 CoreManager integration so this file stays free of `dart:io`,
/// `connectivity_plus`, and STUN protocol code; tests here only see
/// controlled fakes.
class NetworkProfileService {
  final HasPublicIpv6Fn _hasPublicIpv6;
  final Ipv6ReachableFn _ipv6Reachable;
  final StunQueryFn _stunQuery;
  final NetworkKindProviderFn _networkKind;

  NetworkProfileService({
    required HasPublicIpv6Fn hasPublicIpv6,
    required Ipv6ReachableFn ipv6Reachable,
    required StunQueryFn stunQuery,
    required NetworkKindProviderFn networkKind,
  })  : _hasPublicIpv6 = hasPublicIpv6,
        _ipv6Reachable = ipv6Reachable,
        _stunQuery = stunQuery,
        _networkKind = networkKind;

  /// Production wiring: forwards to [NetworkProfileAdapters]. Use this
  /// from CoreManager. Tests construct with explicit fakes via the main
  /// constructor.
  factory NetworkProfileService.production() {
    return NetworkProfileService(
      hasPublicIpv6: NetworkProfileAdapters.hasPublicIpv6,
      ipv6Reachable: NetworkProfileAdapters.ipv6Reachable,
      stunQuery: NetworkProfileAdapters.stunQuery,
      networkKind: NetworkProfileAdapters.networkKind,
    );
  }

  /// Runs all four probes and returns the composite profile. Never
  /// throws: an adapter that fails contributes a conservative default
  /// (`false` / [NetworkKind.unknown] / [NatKind.unknown]) rather than
  /// poisoning the whole sample.
  Future<NetworkProfile> sample() async {
    final hasPubIpv6 = await _safeBool(_hasPublicIpv6);
    final hasIpv6Out = await _safeBool(_ipv6Reachable);
    final natKind = await _probeNat();
    final netKind = await _safeNetworkKind();
    return NetworkProfile(
      hasIpv6Outbound: hasIpv6Out,
      hasPublicIpv6: hasPubIpv6,
      natKind: natKind,
      networkKind: netKind,
      sampledAt: DateTime.now(),
    );
  }

  Future<bool> _safeBool(Future<bool> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return false;
    }
  }

  Future<NetworkKind> _safeNetworkKind() async {
    try {
      return await _networkKind();
    } catch (_) {
      return NetworkKind.unknown;
    }
  }

  /// Classifies NAT by sending two STUN binding requests and comparing
  /// their external mappings.
  ///
  /// Logic: identical (ip, port) on both → [NatKind.nonSymmetric];
  /// anything else → [NatKind.symmetric]; any failure → [NatKind.unknown].
  ///
  /// Two queries differ in source port (the production adapter binds a
  /// fresh ephemeral socket each call). A symmetric NAT assigns a new
  /// external port per source port, so identical results identify the NAT
  /// as non-symmetric. The full RFC NAT taxonomy needs 3+ queries; we
  /// don't need that resolution in Phase 1B.
  ///
  /// The two intermediate tuples are strictly function-local. Nothing
  /// about the external address flows to the returned [NatKind] — the
  /// enum only carries classification.
  Future<NatKind> _probeNat() async {
    try {
      final a = await _stunQuery();
      if (a == null) return NatKind.unknown;
      final b = await _stunQuery();
      if (b == null) return NatKind.unknown;
      if (a.ip == b.ip && a.port == b.port) {
        return NatKind.nonSymmetric;
      }
      return NatKind.symmetric;
    } catch (_) {
      return NatKind.unknown;
    }
  }
}
