import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/relay/relay_candidate.dart';
import 'package:yuelink/core/relay/relay_metrics.dart';
import 'package:yuelink/core/relay/relay_probe_service.dart';
import 'package:yuelink/core/relay/relay_selector.dart';
import 'package:yuelink/core/relay/relay_telemetry.dart';
import 'package:yuelink/domain/models/relay_profile.dart';

/// Words that must never appear as a KEY in any relay telemetry payload —
/// their presence as a key would itself signal a structural leak even if
/// the value were sanitised. Value-side leaks are checked separately
/// against the candidate's actual host / port (see [assertNoForbidden])
/// rather than via substring sweep, because closed-set values like
/// `l3_unsupported` legitimately contain the substring "port" without
/// being a leak.
const _forbiddenKeys = <String>[
  'host',
  'ip',
  'port',
  'server',
  'uuid',
  'password',
  'address',
];

ProbeResult _ok(int ms) =>
    ProbeResult(reachable: true, latencyMs: ms, at: DateTime.now());

ProbeResult _failTimeout() => ProbeResult(
      reachable: false,
      errorClass: ProbeError.timeout,
      at: DateTime.now(),
    );

ProbeResult _failOther(String klass) => ProbeResult(
      reachable: false,
      errorClass: klass,
      at: DateTime.now(),
    );

RelayCandidate _commercial({
  String type = 'vless',
  String host = 'r.example.com',
  int port = 443,
  Map<String, dynamic> extras = const {},
}) {
  return RelayCandidate.commercial(RelayProfile(
    enabled: true,
    type: type,
    host: host,
    port: port,
    extras: extras,
  ));
}

RelayCandidate _direct() => RelayCandidate.direct(
      profileId: '_default',
      exitHost: 'unknown',
      exitPort: 0,
      exitType: 'unknown',
    );

void assertNoForbidden(
  Map<String, dynamic> props, {
  List<String> forbiddenValueSubstrings = const [],
  String label = 'props',
}) {
  // 1. No forbidden word as a KEY (substring match — "host_count" is just as
  // bad as "host" because it telegraphs we're shipping host data).
  for (final key in props.keys) {
    final lower = key.toLowerCase();
    for (final w in _forbiddenKeys) {
      expect(lower.contains(w), isFalse,
          reason: '$label: key "$key" contains forbidden substring "$w"');
    }
  }
  // 2. No call-site-supplied value substrings (e.g. the candidate's host or
  // port number) anywhere in stringified values. Substring sweep against
  // generic words like "port" is intentionally NOT performed — closed-set
  // labels such as ProbeError.l3Unsupported contain "port" inside
  // "unsupported" without being a leak.
  if (forbiddenValueSubstrings.isEmpty) return;
  for (final entry in props.entries) {
    final asStr = entry.value.toString().toLowerCase();
    for (final needle in forbiddenValueSubstrings) {
      if (needle.isEmpty) continue;
      expect(asStr.contains(needle.toLowerCase()), isFalse,
          reason: '$label: value of "${entry.key}" '
              '("${entry.value}") leaks call-site substring "$needle"');
    }
  }
}

void main() {
  group('RelayTelemetry.probe — closed key set', () {
    test('produces exactly the 5 allowed keys for a successful probe', () {
      final props = RelayTelemetry.probe(_commercial(), _ok(80));
      expect(props.keys.toSet(), {
        'candidate_kind',
        'reachable',
        'latency_bucket',
        'error_class',
        'protocol_rank_tier',
      });
    });

    test('same key set for unreachable probes (no fields conditional)', () {
      final props = RelayTelemetry.probe(_commercial(), _failTimeout());
      expect(props.keys.toSet(), {
        'candidate_kind',
        'reachable',
        'latency_bucket',
        'error_class',
        'protocol_rank_tier',
      });
    });

    test('values use the documented closed-set strings', () {
      final p = RelayTelemetry.probe(_commercial(), _ok(80));
      expect(['direct', 'officialCommercial', 'officialAccess'],
          contains(p['candidate_kind']));
      expect(p['reachable'], isA<bool>());
      expect(['<50ms', '50-150', '150-500', '>500', 'timeout', 'fail'],
          contains(p['latency_bucket']));
      expect(p['error_class'], isA<String>());
      expect(['low', 'medium', 'high'], contains(p['protocol_rank_tier']));
    });
  });

  group('RelayTelemetry.probe — latency_bucket', () {
    test('reachable buckets', () {
      expect(
          RelayTelemetry.probe(_commercial(), _ok(10))['latency_bucket'],
          '<50ms');
      expect(
          RelayTelemetry.probe(_commercial(), _ok(49))['latency_bucket'],
          '<50ms');
      expect(
          RelayTelemetry.probe(_commercial(), _ok(50))['latency_bucket'],
          '50-150');
      expect(
          RelayTelemetry.probe(_commercial(), _ok(149))['latency_bucket'],
          '50-150');
      expect(
          RelayTelemetry.probe(_commercial(), _ok(150))['latency_bucket'],
          '150-500');
      expect(
          RelayTelemetry.probe(_commercial(), _ok(499))['latency_bucket'],
          '150-500');
      expect(
          RelayTelemetry.probe(_commercial(), _ok(500))['latency_bucket'],
          '>500');
      expect(
          RelayTelemetry.probe(_commercial(), _ok(5000))['latency_bucket'],
          '>500');
    });

    test('unreachable + errorClass=timeout → "timeout"', () {
      expect(
          RelayTelemetry.probe(_commercial(), _failTimeout())['latency_bucket'],
          'timeout');
    });

    test('unreachable + non-timeout error → "fail"', () {
      for (final e in [
        ProbeError.tcpRefused,
        ProbeError.dnsFail,
        ProbeError.tlsFail,
        ProbeError.l3Unsupported,
      ]) {
        expect(
            RelayTelemetry.probe(_commercial(), _failOther(e))['latency_bucket'],
            'fail',
            reason: 'errorClass=$e should map to "fail" not "timeout"');
      }
    });
  });

  group('RelayTelemetry.probe — protocol_rank_tier reflects extras', () {
    test('VLESS+Reality is "high"', () {
      final p = RelayTelemetry.probe(
        _commercial(extras: {
          'reality-opts': {'public-key': 'abc'},
        }),
        _ok(50),
      );
      expect(p['protocol_rank_tier'], 'high');
    });

    test('VLESS+TLS is "medium"', () {
      final p = RelayTelemetry.probe(
        _commercial(extras: {'tls': true}),
        _ok(50),
      );
      expect(p['protocol_rank_tier'], 'medium');
    });

    test('Shadowsocks is "low"', () {
      final p =
          RelayTelemetry.probe(_commercial(type: 'shadowsocks'), _ok(50));
      expect(p['protocol_rank_tier'], 'low');
    });
  });

  group('RelayTelemetry.selected — closed key set', () {
    test('with reason → 2 keys', () {
      final p = RelayTelemetry.selected(
          RelayCandidateKind.officialCommercial, RelaySelectReason.lowestLatency);
      expect(p, {
        'kind': 'officialCommercial',
        'reason': 'lowest_latency',
      });
    });

    test('without reason → reason key absent (not null-valued)', () {
      final p =
          RelayTelemetry.selected(RelayCandidateKind.direct, null);
      expect(p.keys.toSet(), {'kind'});
      expect(p.containsKey('reason'), isFalse,
          reason: 'absent ≠ null — dashboard reads "no reason" from key absence');
    });
  });

  group('RelayTelemetry — privacy sweep', () {
    test('relay_probe never leaks host/ip/port/server/uuid/password/address',
        () {
      // Build candidates whose host / port include each forbidden token
      // verbatim so a leak would show up as a substring match.
      final candidates = <RelayCandidate>[
        _commercial(host: 'host-leak.example.com', port: 443),
        _commercial(host: 'server-leak.example.com', port: 8443),
        _commercial(
          host: 'a.example.com',
          port: 80,
          extras: {'uuid': 'leak-this-uuid', 'password': 'leak-pwd'},
        ),
        _commercial(
          host: 'b.example.com',
          port: 443,
          extras: {
            'reality-opts': {'public-key': 'leak-key'},
          },
        ),
        _direct(),
      ];
      final results = <ProbeResult>[
        _ok(40),
        _ok(120),
        _ok(450),
        _ok(900),
        _failTimeout(),
        _failOther(ProbeError.tcpRefused),
        _failOther(ProbeError.dnsFail),
        _failOther(ProbeError.tlsFail),
        _failOther(ProbeError.l3Unsupported),
      ];

      for (final c in candidates) {
        for (final r in results) {
          final props = RelayTelemetry.probe(c, r);
          // Direct candidates carry placeholder host="unknown" / port=0;
          // those aren't realistic leak risks (they're sentinels we
          // chose). Only sweep value-leaks for commercial candidates
          // where host/port/extras are actual user data.
          final valueLeaks = c.isDirect
              ? <String>[]
              : <String>[
                  c.host,
                  c.port.toString(),
                  if (c.extras['uuid'] is String) c.extras['uuid'] as String,
                  if (c.extras['password'] is String)
                    c.extras['password'] as String,
                  if (c.extras['reality-opts'] is Map &&
                      (c.extras['reality-opts'] as Map)['public-key']
                          is String)
                    (c.extras['reality-opts'] as Map)['public-key'] as String,
                ];
          assertNoForbidden(
            props,
            forbiddenValueSubstrings: valueLeaks,
            label: 'probe(${c.kind.name}/${c.type})',
          );
        }
      }
    });

    test('relay_selected never leaks anything — only kind + reason', () {
      for (final kind in RelayCandidateKind.values) {
        for (final reason in <String?>[
          null,
          RelaySelectReason.lowestLatency,
          RelaySelectReason.conservativeBias,
          RelaySelectReason.fallback,
          RelaySelectReason.cached,
        ]) {
          final props = RelayTelemetry.selected(kind, reason);
          assertNoForbidden(props, label: 'selected($kind/$reason)');
          // Hardcoded shape check: only "kind" and optionally "reason".
          expect(
              props.keys.toSet().difference({'kind', 'reason'}), isEmpty,
              reason: 'unexpected key: ${props.keys}');
        }
      }
    });
  });
}
