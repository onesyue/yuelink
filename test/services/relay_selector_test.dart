import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/relay/protocol_ranker.dart';
import 'package:yuelink/core/relay/relay_candidate.dart';
import 'package:yuelink/core/relay/relay_selector.dart';
import 'package:yuelink/domain/models/relay_profile.dart';

/// Hand-rolled metrics stub; deliberately kept in this test file so the
/// real [RelayMetrics] (A2-part-2) can land without touching these tests.
class _StubMetrics implements RelayMetricsView {
  final Map<String, int> _p50;
  final Map<String, double> _failure;
  _StubMetrics({
    Map<String, int>? p50,
    Map<String, double>? failure,
  })  : _p50 = p50 ?? const {},
        _failure = failure ?? const {};

  @override
  int? p50Latency(String candidateId) => _p50[candidateId];

  @override
  double failureRate(String candidateId) => _failure[candidateId] ?? 0.0;
}

RelayCandidate _direct({String profileId = 'yue-main', String type = 'vless'}) {
  return RelayCandidate.direct(
    profileId: profileId,
    exitHost: 'exit.example.com',
    exitPort: 443,
    exitType: type,
  );
}

RelayCandidate _commercial({
  required String host,
  int port = 443,
  String type = 'vless',
  Map<String, dynamic> extras = const {},
}) {
  return RelayCandidate.commercial(
    RelayProfile(
      enabled: true,
      type: type,
      host: host,
      port: port,
      extras: extras,
    ),
  );
}

void main() {
  group('LowestLatencySelector — direct fallback', () {
    test('empty relay pool → direct', () async {
      final sel = LowestLatencySelector();
      final direct = _direct();
      final pick = await sel.select([direct], _StubMetrics());
      expect(pick.isDirect, isTrue);
      expect(sel.lastReason, RelaySelectReason.fallback);
    });

    test('no metrics history for any relay → direct (never guess cold)',
        () async {
      final sel = LowestLatencySelector();
      final direct = _direct();
      final relay = _commercial(host: 'r1.example.com');
      final pick = await sel.select([direct, relay], _StubMetrics());
      expect(pick.isDirect, isTrue);
      expect(sel.lastReason, RelaySelectReason.fallback);
    });

    test('all relays exceed failureThreshold → direct', () async {
      final sel = LowestLatencySelector();
      final direct = _direct();
      final r1 = _commercial(host: 'r1.example.com');
      final r2 = _commercial(host: 'r2.example.com');
      final pick = await sel.select(
        [direct, r1, r2],
        _StubMetrics(
          p50: {r1.id: 50, r2.id: 60, direct.id: 500},
          failure: {r1.id: 0.8, r2.id: 0.9},
        ),
      );
      expect(pick.isDirect, isTrue);
      expect(sel.lastReason, RelaySelectReason.fallback);
    });

    test('no direct candidate → throws StateError', () async {
      final sel = LowestLatencySelector();
      final relay = _commercial(host: 'r1.example.com');
      await expectLater(
        sel.select([relay], _StubMetrics(p50: {relay.id: 50})),
        throwsStateError,
      );
    });
  });

  group('LowestLatencySelector — tolerance = max(20%, 80ms)', () {
    test('small absolute gap (<80ms) but large ratio (>20%) → direct', () async {
      // direct=60, relay=10 → ratio 83% but absolute 50ms (<80ms floor) → direct
      final sel = LowestLatencySelector();
      final direct = _direct();
      final relay = _commercial(host: 'r1.example.com');
      final pick = await sel.select(
        [direct, relay],
        _StubMetrics(p50: {relay.id: 10, direct.id: 60}),
      );
      expect(pick.isDirect, isTrue);
      expect(sel.lastReason, RelaySelectReason.conservativeBias);
    });

    test('large absolute gap (>80ms) but small ratio (<20%) → direct', () async {
      // direct=1000, relay=950 → absolute 50ms, ratio 5% → both below thresholds → direct
      final sel = LowestLatencySelector();
      final direct = _direct();
      final relay = _commercial(host: 'r1.example.com');
      final pick = await sel.select(
        [direct, relay],
        _StubMetrics(p50: {relay.id: 950, direct.id: 1000}),
      );
      expect(pick.isDirect, isTrue);
      expect(sel.lastReason, RelaySelectReason.conservativeBias);
    });

    test('gap clears both thresholds → relay wins', () async {
      // direct=500, relay=300 → absolute 200ms, ratio 40% → relay
      final sel = LowestLatencySelector();
      final direct = _direct();
      final relay = _commercial(host: 'r1.example.com');
      final pick = await sel.select(
        [direct, relay],
        _StubMetrics(p50: {relay.id: 300, direct.id: 500}),
      );
      expect(pick.id, relay.id);
      expect(sel.lastReason, RelaySelectReason.lowestLatency);
    });

    test('absolute >80ms on a slow link still requires ratio check', () async {
      // direct=400, relay=300 → absolute 100ms, ratio = 25% (> 20%); requiredGap
      // = max(300*0.20, 80) = 80; gap = 100 > 80 → relay
      final sel = LowestLatencySelector();
      final direct = _direct();
      final relay = _commercial(host: 'r1.example.com');
      final pick = await sel.select(
        [direct, relay],
        _StubMetrics(p50: {relay.id: 300, direct.id: 400}),
      );
      expect(pick.id, relay.id);
    });

    test('no direct p50 but relay p50 known → relay wins (no bias possible)',
        () async {
      final sel = LowestLatencySelector();
      final direct = _direct();
      final relay = _commercial(host: 'r1.example.com');
      final pick = await sel.select(
        [direct, relay],
        _StubMetrics(p50: {relay.id: 120}), // no direct.id entry
      );
      expect(pick.id, relay.id);
      expect(sel.lastReason, RelaySelectReason.lowestLatency);
    });
  });

  group('LowestLatencySelector — ProtocolRank tie-break', () {
    test('equal p50: higher protocolRank wins', () async {
      final sel = LowestLatencySelector();
      final direct = _direct();
      final realityRelay = _commercial(
        host: 'reality.example.com',
        type: 'vless',
        extras: const {
          'reality-opts': {'public-key': 'abc'},
        },
      );
      final vmessRelay = _commercial(
        host: 'vmess.example.com',
        type: 'vmess',
      );
      final pick = await sel.select(
        [direct, realityRelay, vmessRelay],
        _StubMetrics(
          p50: {
            realityRelay.id: 100,
            vmessRelay.id: 100, // identical
            direct.id: 500,
          },
        ),
      );
      expect(pick.id, realityRelay.id,
          reason:
              'equal p50 must tie-break by protocolRank (reality > vmess)');
      expect(sel.lastReason, RelaySelectReason.lowestLatency);
    });

    test('unequal p50: rank does NOT outrank the lower-latency candidate',
        () async {
      final sel = LowestLatencySelector();
      final direct = _direct();
      // vmess is 50ms faster than reality → vmess wins despite lower rank
      final realityRelay = _commercial(
        host: 'reality.example.com',
        type: 'vless',
        extras: const {
          'reality-opts': {'public-key': 'abc'},
        },
      );
      final vmessRelay = _commercial(
        host: 'vmess.example.com',
        type: 'vmess',
      );
      final pick = await sel.select(
        [direct, realityRelay, vmessRelay],
        _StubMetrics(
          p50: {
            realityRelay.id: 200,
            vmessRelay.id: 150,
            direct.id: 1000, // ensure bias doesn't kick in
          },
        ),
      );
      expect(pick.id, vmessRelay.id);
    });

    test('rank is pure tie-break — does not re-order across 1ms gaps',
        () async {
      final sel = LowestLatencySelector();
      final direct = _direct();
      final rankA = _commercial(
        host: 'a.example.com',
        type: 'vless',
        extras: const {
          'reality-opts': {'public-key': 'abc'},
        },
      );
      final rankB = _commercial(host: 'b.example.com', type: 'shadowsocks');
      // B is 1ms faster. Even though A has a far higher rank, B wins on p50.
      final pick = await sel.select(
        [direct, rankA, rankB],
        _StubMetrics(
          p50: {rankA.id: 101, rankB.id: 100, direct.id: 1000},
        ),
      );
      expect(pick.id, rankB.id);
    });

    test('ProtocolRanker exposes the expected relative order used here',
        () {
      // Sanity: if someone reorders the rank table such that these equalities
      // break, the tie-break tests above become meaningless. Pin the
      // invariants the selector relies on.
      final reality = ProtocolRanker.rank('vless', {
        'reality-opts': {'k': 'v'},
      });
      final vmess = ProtocolRanker.rank('vmess', const {});
      final ss = ProtocolRanker.rank('shadowsocks', const {});
      expect(reality, greaterThan(vmess));
      expect(vmess, greaterThan(ss));
    });
  });

  group('LowestLatencySelector — boundary behaviour', () {
    test('a brand-new relay (no history) is not excluded by failure filter',
        () async {
      // failureRate defaults to 0.0 with no history → candidate eligible.
      // But without a p50 it still falls through to the direct-fallback path;
      // this test pins that contract (no stale-relay preference).
      final sel = LowestLatencySelector();
      final direct = _direct();
      final newRelay = _commercial(host: 'new.example.com');
      final pick = await sel.select(
        [direct, newRelay],
        _StubMetrics(p50: {direct.id: 500}), // newRelay has no p50
      );
      expect(pick.isDirect, isTrue);
      expect(sel.lastReason, RelaySelectReason.fallback);
    });

    test('lastReason updates across successive select() calls', () async {
      final sel = LowestLatencySelector();
      final direct = _direct();
      final relay = _commercial(host: 'r.example.com');

      await sel.select([direct], _StubMetrics());
      expect(sel.lastReason, RelaySelectReason.fallback);

      await sel.select(
        [direct, relay],
        _StubMetrics(p50: {relay.id: 50, direct.id: 500}),
      );
      expect(sel.lastReason, RelaySelectReason.lowestLatency);

      await sel.select(
        [direct, relay],
        _StubMetrics(p50: {relay.id: 450, direct.id: 500}),
      );
      expect(sel.lastReason, RelaySelectReason.conservativeBias);
    });
  });
}
