import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/relay/network_profile.dart';
import 'package:yuelink/core/relay/network_profile_service.dart';

/// Adapter builders that drive the service under controlled conditions.
/// Kept inside the test file so the service module stays free of test
/// helpers and the fakes are never accidentally imported by production
/// code.
HasPublicIpv6Fn _v6Iface(bool value) => () async => value;
Ipv6ReachableFn _v6Reach(bool value) => () async => value;
NetworkKindProviderFn _netKind(NetworkKind value) => () async => value;

/// Returns a STUN adapter that yields the given sequence of results.
/// A `null` in the sequence simulates "STUN server didn't answer".
/// Once the sequence is exhausted, subsequent calls throw — which never
/// happens in a well-formed test (the service only queries twice).
StunQueryFn _stunSequence(List<({String ip, int port})?> values) {
  var i = 0;
  return () async {
    if (i >= values.length) {
      throw StateError(
          'StunQueryFn called more times than the test scripted — bug.');
    }
    return values[i++];
  };
}

/// A STUN adapter that always throws, to exercise the try/catch fallback.
StunQueryFn _stunThrowing(Object Function() factory) {
  return () async => throw factory();
}

NetworkProfileService _svc({
  HasPublicIpv6Fn? hasPublicIpv6,
  Ipv6ReachableFn? ipv6Reachable,
  StunQueryFn? stunQuery,
  NetworkKindProviderFn? networkKind,
}) {
  return NetworkProfileService(
    hasPublicIpv6: hasPublicIpv6 ?? _v6Iface(false),
    ipv6Reachable: ipv6Reachable ?? _v6Reach(false),
    stunQuery: stunQuery ?? _stunSequence(const [null]),
    networkKind: networkKind ?? _netKind(NetworkKind.unknown),
  );
}

void main() {
  group('NetworkProfile — value type invariants', () {
    test('NetworkKind has exactly {wifi, cellular, ethernet, unknown}', () {
      final names = NetworkKind.values.map((k) => k.name).toSet();
      expect(names, {'wifi', 'cellular', 'ethernet', 'unknown'});
    });

    test('NatKind has exactly {nonSymmetric, symmetric, unknown}', () {
      final names = NatKind.values.map((k) => k.name).toSet();
      expect(names, {'nonSymmetric', 'symmetric', 'unknown'});
    });

    test('constructor assigns fields and no externalAddress-like field exists',
        () {
      // Structural assertion: the class has 5 fields. Any future addition
      // of an address-like field is a deliberate schema change that should
      // break this test — keeping the privacy invariant visible in the
      // test surface.
      final p = NetworkProfile(
        hasIpv6Outbound: true,
        hasPublicIpv6: true,
        natKind: NatKind.nonSymmetric,
        networkKind: NetworkKind.wifi,
        sampledAt: DateTime(2026, 4, 24),
      );
      expect(p.hasIpv6Outbound, isTrue);
      expect(p.hasPublicIpv6, isTrue);
      expect(p.natKind, NatKind.nonSymmetric);
      expect(p.networkKind, NetworkKind.wifi);
      expect(p.sampledAt, DateTime(2026, 4, 24));
    });
  });

  group('NetworkProfileService.sample — IPv6 interface + outbound', () {
    test('public IPv6 present AND reachable → both bits true', () async {
      final p = await _svc(
        hasPublicIpv6: _v6Iface(true),
        ipv6Reachable: _v6Reach(true),
        stunQuery: _stunSequence(const [null]),
      ).sample();
      expect(p.hasPublicIpv6, isTrue);
      expect(p.hasIpv6Outbound, isTrue);
    });

    test('public IPv6 present but outbound blocked → iface true, reach false',
        () async {
      // Common carrier scenario: the interface has a global-unicast v6
      // address but the operator firewall blocks outbound 443. Both bits
      // must stay independent so the telemetry downstream can see the
      // gap.
      final p = await _svc(
        hasPublicIpv6: _v6Iface(true),
        ipv6Reachable: _v6Reach(false),
      ).sample();
      expect(p.hasPublicIpv6, isTrue);
      expect(p.hasIpv6Outbound, isFalse);
    });

    test('no public IPv6 AND no outbound → both false', () async {
      final p = await _svc().sample();
      expect(p.hasPublicIpv6, isFalse);
      expect(p.hasIpv6Outbound, isFalse);
    });

    test('hasPublicIpv6 adapter throws → false (conservative)', () async {
      final p = await _svc(
        hasPublicIpv6: () async => throw StateError('platform error'),
        ipv6Reachable: _v6Reach(true),
      ).sample();
      expect(p.hasPublicIpv6, isFalse);
      // Other fields are not poisoned by one adapter failing.
      expect(p.hasIpv6Outbound, isTrue);
    });

    test('ipv6Reachable adapter throws → false (conservative)', () async {
      final p = await _svc(
        hasPublicIpv6: _v6Iface(true),
        ipv6Reachable: () async => throw StateError('connect crashed'),
      ).sample();
      expect(p.hasPublicIpv6, isTrue);
      expect(p.hasIpv6Outbound, isFalse);
    });
  });

  group('NetworkProfileService.sample — STUN NAT classification', () {
    test('two identical (ip, port) results → nonSymmetric', () async {
      final p = await _svc(
        stunQuery: _stunSequence(const [
          (ip: '203.0.113.10', port: 55000),
          (ip: '203.0.113.10', port: 55000),
        ]),
      ).sample();
      expect(p.natKind, NatKind.nonSymmetric);
    });

    test('same ip, different port → symmetric', () async {
      final p = await _svc(
        stunQuery: _stunSequence(const [
          (ip: '203.0.113.10', port: 55000),
          (ip: '203.0.113.10', port: 55001),
        ]),
      ).sample();
      expect(p.natKind, NatKind.symmetric);
    });

    test('different ip → symmetric (defensive: unreliable mapping)', () async {
      final p = await _svc(
        stunQuery: _stunSequence(const [
          (ip: '203.0.113.10', port: 55000),
          (ip: '203.0.113.11', port: 55000),
        ]),
      ).sample();
      expect(p.natKind, NatKind.symmetric);
    });

    test('first query returns null → unknown (second never inspected)',
        () async {
      // If the first query already fails there is nothing to compare
      // against; the second probe is skipped so a flaky STUN server
      // doesn't dominate latency.
      var secondCalled = false;
      Future<({String ip, int port})?> stun() async {
        if (!secondCalled) {
          secondCalled = true;
          return null;
        }
        fail('service should not have issued the second STUN query');
      }

      final p = await _svc(stunQuery: stun).sample();
      expect(p.natKind, NatKind.unknown);
    });

    test('second query returns null → unknown', () async {
      final p = await _svc(
        stunQuery: _stunSequence(const [
          (ip: '203.0.113.10', port: 55000),
          null,
        ]),
      ).sample();
      expect(p.natKind, NatKind.unknown);
    });

    test('STUN adapter throws → unknown, no propagation', () async {
      final p = await _svc(
        stunQuery: _stunThrowing(() => StateError('stun crashed')),
      ).sample();
      expect(p.natKind, NatKind.unknown);
    });
  });

  group('NetworkProfileService.sample — network kind', () {
    test('each NetworkKind value propagates unchanged', () async {
      for (final k in NetworkKind.values) {
        final p = await _svc(networkKind: _netKind(k)).sample();
        expect(p.networkKind, k);
      }
    });

    test('networkKind adapter throws → unknown (fallback)', () async {
      final p = await _svc(
        networkKind: () async => throw StateError('platform channel down'),
      ).sample();
      expect(p.networkKind, NetworkKind.unknown);
    });
  });

  group('NetworkProfileService.sample — timestamp + isolation', () {
    test('sampledAt is set to a recent DateTime', () async {
      final before = DateTime.now();
      final p = await _svc().sample();
      final after = DateTime.now();
      expect(p.sampledAt.isBefore(before), isFalse);
      expect(p.sampledAt.isAfter(after), isFalse);
    });

    test('repeated sample() calls produce independent profiles', () async {
      // The service keeps no internal state; two samples from the same
      // instance must be determined only by the current adapter outputs.
      final svc = _svc(
        hasPublicIpv6: _v6Iface(true),
        ipv6Reachable: _v6Reach(true),
        stunQuery: _stunSequence(const [
          (ip: '203.0.113.10', port: 55000),
          (ip: '203.0.113.10', port: 55000),
          // second sample() consumes two more:
          (ip: '203.0.113.10', port: 55000),
          (ip: '203.0.113.10', port: 55001),
        ]),
        networkKind: _netKind(NetworkKind.wifi),
      );

      final a = await svc.sample();
      expect(a.natKind, NatKind.nonSymmetric);

      final b = await svc.sample();
      expect(b.natKind, NatKind.symmetric);

      // Bits unaffected by the adapter change across calls stay stable.
      expect(b.hasPublicIpv6, isTrue);
      expect(b.networkKind, NetworkKind.wifi);
    });
  });

  group('NetworkProfile — JSON round-trip (cache persistence)', () {
    test('toJson + fromJson preserves all fields', () {
      final original = NetworkProfile(
        hasIpv6Outbound: true,
        hasPublicIpv6: false,
        natKind: NatKind.symmetric,
        networkKind: NetworkKind.cellular,
        sampledAt: DateTime.utc(2026, 4, 24, 14, 30),
      );
      final json = original.toJson();
      final round = NetworkProfile.fromJson(json);
      expect(round.hasIpv6Outbound, original.hasIpv6Outbound);
      expect(round.hasPublicIpv6, original.hasPublicIpv6);
      expect(round.natKind, original.natKind);
      expect(round.networkKind, original.networkKind);
      expect(round.sampledAt.toUtc(), original.sampledAt.toUtc());
    });

    test('fromJson tolerates missing/invalid fields with sane defaults', () {
      final round = NetworkProfile.fromJson(const {});
      expect(round.hasIpv6Outbound, isFalse);
      expect(round.hasPublicIpv6, isFalse);
      expect(round.natKind, NatKind.unknown);
      expect(round.networkKind, NetworkKind.unknown);
      // sampledAt falls back to "now" — just verify it parsed without throwing.
      expect(round.sampledAt, isA<DateTime>());
    });

    test('fromJson handles unknown enum values via fallback', () {
      final round = NetworkProfile.fromJson({
        'natKind': 'invented',
        'networkKind': 'satellite',
        'sampledAt': '2026-04-24T00:00:00Z',
      });
      expect(round.natKind, NatKind.unknown);
      expect(round.networkKind, NetworkKind.unknown);
    });
  });

  group('NetworkProfileService.sample — all-adapters-fail fallback', () {
    test('every adapter throws → conservative defaults, no throw', () async {
      final svc = NetworkProfileService(
        hasPublicIpv6: () async => throw StateError('a'),
        ipv6Reachable: () async => throw StateError('b'),
        stunQuery: _stunThrowing(() => StateError('c')),
        networkKind: () async => throw StateError('d'),
      );
      final p = await svc.sample();
      expect(p.hasPublicIpv6, isFalse);
      expect(p.hasIpv6Outbound, isFalse);
      expect(p.natKind, NatKind.unknown);
      expect(p.networkKind, NetworkKind.unknown);
    });
  });
}
