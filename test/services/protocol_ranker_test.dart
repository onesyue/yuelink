import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/relay/protocol_ranker.dart';

void main() {
  group('ProtocolRanker.rank — extras drive score, not type alone', () {
    test('VLESS with reality-opts ranks highest', () {
      final r = ProtocolRanker.rank('vless', {
        'reality-opts': {'public-key': 'abc', 'short-id': '01'},
      });
      expect(r, 100);
    });

    test('VLESS with `reality:` alt key also counts as reality', () {
      final r = ProtocolRanker.rank('vless', {
        'reality': {'public-key': 'abc'},
      });
      expect(r, 100);
    });

    test('VLESS with tls but no reality ranks lower than reality', () {
      final withTls = ProtocolRanker.rank('vless', {'tls': true});
      final withReality = ProtocolRanker.rank('vless', {
        'reality-opts': {'public-key': 'abc'},
      });
      expect(withTls, 70);
      expect(withReality, greaterThan(withTls));
    });

    test('naked VLESS (no reality, no tls) ranks neutral-ish', () {
      expect(ProtocolRanker.rank('vless', const {}), 50);
    });

    test('empty reality-opts map does not count as reality', () {
      // Guard against a subscription shipping `reality-opts: {}` by accident.
      expect(ProtocolRanker.rank('vless', {'reality-opts': {}}), 50);
    });
  });

  group('ProtocolRanker.rank — other protocols', () {
    test('trojan+reality = 95, trojan+tls = 65, naked trojan = 50', () {
      expect(
        ProtocolRanker.rank('trojan', {
          'reality-opts': {'x': 1}
        }),
        95,
      );
      expect(ProtocolRanker.rank('trojan', {'tls': true}), 65);
      expect(ProtocolRanker.rank('trojan', const {}), 50);
    });

    test('anytls = 60', () {
      expect(ProtocolRanker.rank('anytls', const {}), 60);
    });

    test('hysteria2 / hy2 alias = 55', () {
      expect(ProtocolRanker.rank('hysteria2', const {}), 55);
      expect(ProtocolRanker.rank('hy2', const {}), 55);
    });

    test('vmess+tls = 45, naked vmess = 40', () {
      expect(ProtocolRanker.rank('vmess', {'tls': true}), 45);
      expect(ProtocolRanker.rank('vmess', const {}), 40);
    });

    test('shadowsocks / ss alias = 30 (FET detection risk in 2026)', () {
      expect(ProtocolRanker.rank('shadowsocks', const {}), 30);
      expect(ProtocolRanker.rank('ss', const {}), 30);
    });

    test('socks5 / http = 20 (no encryption)', () {
      expect(ProtocolRanker.rank('socks5', const {}), 20);
      expect(ProtocolRanker.rank('http', const {}), 20);
    });
  });

  group('ProtocolRanker.rank — malformed inputs', () {
    test('null type → neutral 50', () {
      expect(ProtocolRanker.rank(null, const {}), 50);
    });

    test('empty type → neutral 50', () {
      expect(ProtocolRanker.rank('', const {}), 50);
    });

    test('unknown type → neutral 50', () {
      expect(ProtocolRanker.rank('wireguard', const {}), 50);
      expect(ProtocolRanker.rank('quic-magic', const {}), 50);
    });

    test('type is case-insensitive', () {
      expect(ProtocolRanker.rank('VLESS', {'tls': true}), 70);
      expect(ProtocolRanker.rank('Trojan', const {}), 50);
    });

    test('tls=true is strict — not any truthy value', () {
      // Defensive: only bool-true should flip the tls bit, otherwise a
      // subscription shipping `tls: "true"` (string) would score wrong.
      expect(ProtocolRanker.rank('vless', {'tls': 'true'}), 50);
      expect(ProtocolRanker.rank('vless', {'tls': 1}), 50);
    });
  });

  group('ProtocolRanker.tier — telemetry buckets', () {
    test('≥80 → high, 45-79 → medium, <45 → low', () {
      expect(ProtocolRanker.tier(100), 'high');
      expect(ProtocolRanker.tier(80), 'high');
      expect(ProtocolRanker.tier(79), 'medium');
      expect(ProtocolRanker.tier(45), 'medium');
      expect(ProtocolRanker.tier(44), 'low');
      expect(ProtocolRanker.tier(20), 'low');
    });
  });
}
