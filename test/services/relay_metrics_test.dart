import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/relay/relay_candidate.dart';
import 'package:yuelink/core/relay/relay_metrics.dart';
import 'package:yuelink/core/relay/relay_selector.dart';
import 'package:yuelink/domain/models/relay_profile.dart';

ProbeResult _ok(int latencyMs) => ProbeResult(
      reachable: true,
      latencyMs: latencyMs,
      at: DateTime.now(),
    );

ProbeResult _fail([String? error]) => ProbeResult(
      reachable: false,
      errorClass: error,
      at: DateTime.now(),
    );

void main() {
  group('RelayMetrics.record + recent', () {
    test('stores probes per candidateId and returns them oldest-first', () {
      final m = RelayMetrics();
      m.record('c1', _ok(10));
      m.record('c1', _ok(20));
      m.record('c1', _ok(30));
      final r = m.recent('c1');
      expect(r.map((p) => p.latencyMs), [10, 20, 30]);
    });

    test('unknown candidateId returns empty list', () {
      final m = RelayMetrics();
      expect(m.recent('never-probed'), isEmpty);
    });

    test('ring buffer caps at maxHistorySize (20); oldest is dropped', () {
      final m = RelayMetrics();
      for (var i = 0; i < 25; i++) {
        m.record('c1', _ok(i));
      }
      final r = m.recent('c1', n: 100);
      expect(r.length, RelayMetrics.maxHistorySize);
      // Oldest kept should be latency 5 (0..4 dropped); newest should be 24.
      expect(r.first.latencyMs, 5);
      expect(r.last.latencyMs, 24);
    });

    test('different candidateIds are isolated', () {
      final m = RelayMetrics();
      m.record('a', _ok(100));
      m.record('b', _ok(200));
      expect(m.recent('a').single.latencyMs, 100);
      expect(m.recent('b').single.latencyMs, 200);
    });

    test('recent() default n=10 returns the last 10', () {
      final m = RelayMetrics();
      for (var i = 0; i < 15; i++) {
        m.record('c1', _ok(i));
      }
      final r = m.recent('c1');
      expect(r.length, 10);
      expect(r.first.latencyMs, 5);
      expect(r.last.latencyMs, 14);
    });

    test('recent() returns unmodifiable list', () {
      final m = RelayMetrics();
      m.record('c1', _ok(10));
      final r = m.recent('c1');
      expect(() => r.add(_ok(99)), throwsUnsupportedError);
    });
  });

  group('RelayMetrics.p50Latency', () {
    test('no history → null', () {
      expect(RelayMetrics().p50Latency('c1'), isNull);
    });

    test('all failures → null (nothing to compute median from)', () {
      final m = RelayMetrics();
      m.record('c1', _fail('timeout'));
      m.record('c1', _fail('tcp_refused'));
      expect(m.p50Latency('c1'), isNull);
    });

    test('single sample → that value', () {
      final m = RelayMetrics();
      m.record('c1', _ok(42));
      expect(m.p50Latency('c1'), 42);
    });

    test('odd count → middle value', () {
      final m = RelayMetrics();
      for (final v in [30, 10, 20]) {
        m.record('c1', _ok(v));
      }
      // sorted: 10, 20, 30 → p50 = 20
      expect(m.p50Latency('c1'), 20);
    });

    test('even count → lower of two middle (deterministic)', () {
      final m = RelayMetrics();
      for (final v in [40, 10, 30, 20]) {
        m.record('c1', _ok(v));
      }
      // sorted: 10, 20, 30, 40 → (len-1)~/2 = 1 → 20
      expect(m.p50Latency('c1'), 20);
    });

    test('excludes failed probes from median calculation', () {
      final m = RelayMetrics();
      m.record('c1', _ok(10));
      m.record('c1', _fail('timeout'));
      m.record('c1', _ok(30));
      m.record('c1', _fail('tls_fail'));
      m.record('c1', _ok(20));
      // Only successes: 10, 20, 30 → p50 = 20
      expect(m.p50Latency('c1'), 20);
    });
  });

  group('RelayMetrics.failureRate', () {
    test('no history → 0.0 (new candidates not punished)', () {
      expect(RelayMetrics().failureRate('c1'), 0.0);
    });

    test('all failures → 1.0', () {
      final m = RelayMetrics();
      m.record('c1', _fail('timeout'));
      m.record('c1', _fail('tcp_refused'));
      expect(m.failureRate('c1'), 1.0);
    });

    test('all successes → 0.0', () {
      final m = RelayMetrics();
      m.record('c1', _ok(10));
      m.record('c1', _ok(20));
      expect(m.failureRate('c1'), 0.0);
    });

    test('mixed → ratio', () {
      final m = RelayMetrics();
      for (var i = 0; i < 4; i++) {
        m.record('c1', _ok(10));
      }
      m.record('c1', _fail('timeout'));
      // 1 fail / 5 total = 0.2
      expect(m.failureRate('c1'), closeTo(0.2, 1e-9));
    });
  });

  group('RelayMetrics.cumulativeUsage', () {
    test('unknown candidateId → Duration.zero', () {
      expect(RelayMetrics().cumulativeUsage('c1'), Duration.zero);
    });

    test('addUsage accumulates', () {
      final m = RelayMetrics();
      m.addUsage('c1', const Duration(minutes: 30));
      m.addUsage('c1', const Duration(minutes: 20));
      expect(m.cumulativeUsage('c1'), const Duration(minutes: 50));
    });

    test('addUsage isolates between candidateIds', () {
      final m = RelayMetrics();
      m.addUsage('a', const Duration(hours: 2));
      m.addUsage('b', const Duration(hours: 5));
      expect(m.cumulativeUsage('a'), const Duration(hours: 2));
      expect(m.cumulativeUsage('b'), const Duration(hours: 5));
    });
  });

  group('RelayMetrics.cumulativeUsageBucket', () {
    test('unknown candidateId → "<1h" (zero falls in first bucket)', () {
      expect(RelayMetrics().cumulativeUsageBucket('c1'), '<1h');
    });

    test('each bucket boundary falls into the higher bucket', () {
      final m = RelayMetrics();

      // 30m → <1h
      m.addUsage('a', const Duration(minutes: 30));
      expect(m.cumulativeUsageBucket('a'), '<1h');

      // exactly 1h → 1-6h
      m.addUsage('b', const Duration(hours: 1));
      expect(m.cumulativeUsageBucket('b'), '1-6h');

      // 5h → 1-6h
      m.addUsage('c', const Duration(hours: 5));
      expect(m.cumulativeUsageBucket('c'), '1-6h');

      // exactly 6h → 6-24h
      m.addUsage('d', const Duration(hours: 6));
      expect(m.cumulativeUsageBucket('d'), '6-24h');

      // 12h → 6-24h
      m.addUsage('e', const Duration(hours: 12));
      expect(m.cumulativeUsageBucket('e'), '6-24h');

      // exactly 24h → 1-7d
      m.addUsage('f', const Duration(hours: 24));
      expect(m.cumulativeUsageBucket('f'), '1-7d');

      // 3d → 1-7d
      m.addUsage('g', const Duration(days: 3));
      expect(m.cumulativeUsageBucket('g'), '1-7d');

      // exactly 7d → >7d
      m.addUsage('h', const Duration(days: 7));
      expect(m.cumulativeUsageBucket('h'), '>7d');

      // 30d → >7d
      m.addUsage('i', const Duration(days: 30));
      expect(m.cumulativeUsageBucket('i'), '>7d');
    });
  });

  group('RelayMetrics implements RelayMetricsView', () {
    test('is usable anywhere a RelayMetricsView is expected', () {
      final RelayMetricsView view = RelayMetrics();
      expect(view.p50Latency('x'), isNull);
      expect(view.failureRate('x'), 0.0);
    });
  });

  group('integration: LowestLatencySelector × real RelayMetrics', () {
    test('records probes and selects the lowest-latency healthy relay',
        () async {
      final metrics = RelayMetrics();

      final direct = RelayCandidate.direct(
        profileId: 'yue-main',
        exitHost: 'exit.example.com',
        exitPort: 443,
        exitType: 'vless',
      );
      final relayA = RelayCandidate.commercial(const RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'a.example.com',
        port: 443,
      ));
      final relayB = RelayCandidate.commercial(const RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'b.example.com',
        port: 443,
      ));

      // Direct: stable around 400ms
      for (final v in [390, 410, 400]) {
        metrics.record(direct.id, _ok(v));
      }
      // Relay A: fast and healthy, ~100ms
      for (final v in [95, 105, 100, 110]) {
        metrics.record(relayA.id, _ok(v));
      }
      // Relay B: failing enough to trip the 50% failure filter
      for (var i = 0; i < 5; i++) {
        metrics.record(relayB.id, _fail('timeout'));
      }
      metrics.record(relayB.id, _ok(30)); // one lucky probe — still 5/6 failed

      final selector = LowestLatencySelector();
      final pick = await selector.select([direct, relayA, relayB], metrics);

      expect(pick.id, relayA.id,
          reason:
              'A is the only healthy low-latency relay; B is filtered out by '
              'failureRate > 50% and the direct p50 (400ms) is well outside '
              'the tolerance band around A.p50 (100ms).');
      expect(selector.lastReason, RelaySelectReason.lowestLatency);

      // Also pin the aggregate numbers the selector saw — if these drift,
      // the outcome explanation above stops holding.
      expect(metrics.p50Latency(direct.id), 400);
      expect(metrics.p50Latency(relayA.id), anyOf(100, 105));
      expect(metrics.failureRate(relayB.id), closeTo(5 / 6, 1e-9));
    });
  });
}
