import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/relay/relay_candidate.dart';
import 'package:yuelink/domain/models/relay_profile.dart';

void main() {
  group('RelayCandidate.direct', () {
    test('builds a direct candidate scoped per profile', () {
      final c = RelayCandidate.direct(
        profileId: 'yue-main',
        exitHost: 'hk.example.com',
        exitPort: 443,
        exitType: 'vless',
        exitExtras: {'tls': true, 'uuid': 'xxx'},
        region: 'HK',
      );
      expect(c.id, 'direct:yue-main');
      expect(c.kind, RelayCandidateKind.direct);
      expect(c.isDirect, isTrue);
      expect(c.type, 'vless');
      expect(c.host, 'hk.example.com');
      expect(c.port, 443);
      expect(c.extras['tls'], true);
      expect(c.extras['uuid'], 'xxx');
      expect(c.profileId, 'yue-main');
      expect(c.region, 'HK');
    });

    test('different profiles produce different direct candidate ids', () {
      final a = RelayCandidate.direct(
        profileId: 'yue-main',
        exitHost: 'hk.example.com',
        exitPort: 443,
        exitType: 'vless',
      );
      final b = RelayCandidate.direct(
        profileId: 'yue-secondary',
        exitHost: 'jp.example.com',
        exitPort: 443,
        exitType: 'vless',
      );
      expect(a.id, isNot(equals(b.id)));
    });

    test('direct.toRelayProfile() throws StateError', () {
      final c = RelayCandidate.direct(
        profileId: 'yue-main',
        exitHost: 'hk.example.com',
        exitPort: 443,
        exitType: 'vless',
      );
      expect(c.toRelayProfile, throwsStateError);
    });

    test('extras are unmodifiable', () {
      final c = RelayCandidate.direct(
        profileId: 'yue-main',
        exitHost: 'hk.example.com',
        exitPort: 443,
        exitType: 'vless',
        exitExtras: {'tls': true},
      );
      expect(() => c.extras['hacked'] = true, throwsUnsupportedError);
    });
  });

  group('RelayCandidate.commercial', () {
    test('materialises from a valid RelayProfile', () {
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
        extras: {'uuid': 'relay-uuid', 'tls': true},
      );
      final c = RelayCandidate.commercial(profile);
      expect(c.id, 'commercial:relay.example.com:443');
      expect(c.kind, RelayCandidateKind.officialCommercial);
      expect(c.isDirect, isFalse);
      expect(c.type, 'vless');
      expect(c.host, 'relay.example.com');
      expect(c.port, 443);
      expect(c.extras['uuid'], 'relay-uuid');
      expect(c.extras['tls'], true);
    });

    test('rejects invalid profiles — disabled', () {
      expect(
        () => RelayCandidate.commercial(const RelayProfile.disabled()),
        throwsArgumentError,
      );
    });

    test('rejects invalid profiles — officialAccess source', () {
      const profile = RelayProfile(
        enabled: true,
        source: RelaySource.officialAccess,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
      );
      expect(() => RelayCandidate.commercial(profile), throwsArgumentError);
    });

    test('commercial.toRelayProfile() round-trips identity fields', () {
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
        extras: {'uuid': 'relay-uuid'},
      );
      final c = RelayCandidate.commercial(profile);
      final round = c.toRelayProfile();
      expect(round.type, 'vless');
      expect(round.host, 'relay.example.com');
      expect(round.port, 443);
      expect(round.extras['uuid'], 'relay-uuid');
      expect(round.enabled, isTrue);
      expect(round.isValid, isTrue);
    });

    test('commercial.toRelayProfile() round-trips allowlistNames targeting',
        () {
      // A profile scoped to explicit nodes must NOT silently widen to
      // allVless after a round-trip through RelayCandidate — that would
      // expand the relay's blast radius from "these 2 nodes" to "every
      // VLESS". This guards the blocking issue spotted in review.
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
        extras: {'uuid': 'relay-uuid'},
        targetMode: RelayTargetMode.allowlistNames,
        allowlistNames: ['HK-VLESS', 'JP-VLESS'],
      );
      final c = RelayCandidate.commercial(profile);
      final round = c.toRelayProfile();
      expect(round.targetMode, RelayTargetMode.allowlistNames);
      expect(round.allowlistNames, ['HK-VLESS', 'JP-VLESS']);
      expect(round.isValid, isTrue);
    });

    test('commercial with allVless profile keeps allVless on round-trip', () {
      const profile = RelayProfile(
        enabled: true,
        type: 'vless',
        host: 'relay.example.com',
        port: 443,
      );
      final round = RelayCandidate.commercial(profile).toRelayProfile();
      expect(round.targetMode, RelayTargetMode.allVless);
      expect(round.allowlistNames, isEmpty);
    });
  });

  group('RelayCandidateKind enum', () {
    test('does not expose superPeer', () {
      // Defensive: if someone ever adds superPeer to this enum, this test
      // fails immediately — that's a deliberate legal-review gate, not a
      // drive-by change.
      final names = RelayCandidateKind.values.map((k) => k.name).toSet();
      expect(names, {'direct', 'officialCommercial', 'officialAccess'});
      expect(names, isNot(contains('superPeer')));
    });
  });
}
