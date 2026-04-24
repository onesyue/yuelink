import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/relay/relay_candidate.dart';
import 'package:yuelink/core/relay/relay_probe_service.dart';
import 'package:yuelink/domain/models/relay_profile.dart';

/// Builds a commercial candidate with the given type/extras.
RelayCandidate _c({
  required String type,
  Map<String, dynamic> extras = const {},
  String host = 'relay.example.com',
  int port = 443,
}) {
  return RelayCandidate.commercial(RelayProfile(
    enabled: true,
    type: type,
    host: host,
    port: port,
    extras: extras,
  ));
}

/// A direct candidate — TLS detection on direct should follow the same
/// rules because [RelayCandidate.direct] carries exitType + exitExtras.
RelayCandidate _direct({
  required String exitType,
  Map<String, dynamic> extras = const {},
}) {
  return RelayCandidate.direct(
    profileId: 'yue-main',
    exitHost: 'exit.example.com',
    exitPort: 443,
    exitType: exitType,
    exitExtras: extras,
  );
}

/// Records which adapter got called, useful for TLS-detection and L3
/// short-circuit tests.
class _CallTracker {
  int tcp = 0;
  int tls = 0;
  void reset() => tcp = tls = 0;
}

Future<void> Function(String, int, Duration) _okAdapter(_CallTracker t,
    {required bool tls}) {
  return (_, _, _) async {
    if (tls) {
      t.tls++;
    } else {
      t.tcp++;
    }
    // Complete normally == probe success
  };
}

Future<void> Function(String, int, Duration) _throwing(
    Object Function() factory) {
  return (_, _, _) async {
    throw factory();
  };
}

void main() {
  group('DefaultRelayProbeService — L1 TCP outcomes (no TLS candidate)', () {
    final candidate = _c(type: 'vless'); // naked vless → no TLS
    late _CallTracker calls;

    setUp(() => calls = _CallTracker());

    test('TCP OK + no TLS needed → reachable=true, errorClass=null', () async {
      final svc = DefaultRelayProbeService(
        tcpConnect: _okAdapter(calls, tls: false),
        tlsHandshake: _okAdapter(calls, tls: true),
      );
      final r = await svc.probe(candidate);
      expect(r.reachable, isTrue);
      expect(r.errorClass, isNull);
      expect(r.latencyMs, isNotNull);
      expect(r.latencyMs, greaterThanOrEqualTo(0));
      expect(calls.tcp, 1);
      expect(calls.tls, 0, reason: 'naked vless must not trigger TLS path');
    });

    test('TCP timeout → errorClass=timeout', () async {
      final svc = DefaultRelayProbeService(
        tcpConnect: _throwing(() => TimeoutException('mock timeout')),
        tlsHandshake: _okAdapter(calls, tls: true),
      );
      final r = await svc.probe(candidate);
      expect(r.reachable, isFalse);
      expect(r.errorClass, ProbeError.timeout);
      expect(r.latencyMs, isNull);
    });

    test('TCP connection refused → errorClass=tcp_refused', () async {
      final svc = DefaultRelayProbeService(
        tcpConnect: _throwing(() => const SocketException(
              'Connection refused',
              osError: OSError('Connection refused', 61),
            )),
        tlsHandshake: _okAdapter(calls, tls: true),
      );
      final r = await svc.probe(candidate);
      expect(r.reachable, isFalse);
      expect(r.errorClass, ProbeError.tcpRefused);
    });

    test('DNS lookup failure → errorClass=dns_fail', () async {
      // Mirrors Dart's real SocketException for DNS failure on macOS/iOS.
      final svc = DefaultRelayProbeService(
        tcpConnect: _throwing(() => const SocketException(
              "Failed host lookup: 'relay.example.com'",
              osError:
                  OSError('nodename nor servname provided, or not known', 8),
            )),
        tlsHandshake: _okAdapter(calls, tls: true),
      );
      final r = await svc.probe(candidate);
      expect(r.reachable, isFalse);
      expect(r.errorClass, ProbeError.dnsFail);
    });

    test('DNS failure — Linux-style message also classified as dns_fail',
        () async {
      final svc = DefaultRelayProbeService(
        tcpConnect: _throwing(() => const SocketException(
              "Failed host lookup: 'relay.example.com'",
              osError: OSError('Name or service not known', 97),
            )),
        tlsHandshake: _okAdapter(calls, tls: true),
      );
      final r = await svc.probe(candidate);
      expect(r.errorClass, ProbeError.dnsFail);
    });

    test('unknown exception → falls back to tcp_refused, not a throw',
        () async {
      final svc = DefaultRelayProbeService(
        tcpConnect: _throwing(() => StateError('weird')),
        tlsHandshake: _okAdapter(calls, tls: true),
      );
      final r = await svc.probe(candidate);
      expect(r.reachable, isFalse);
      expect(r.errorClass, ProbeError.tcpRefused);
    });
  });

  group('DefaultRelayProbeService — L2 TLS outcomes', () {
    final tlsCandidate = _c(type: 'vless', extras: {'tls': true});
    late _CallTracker calls;

    setUp(() => calls = _CallTracker());

    test('TLS OK → reachable=true, latency populated, tcp adapter untouched',
        () async {
      final svc = DefaultRelayProbeService(
        tcpConnect: _okAdapter(calls, tls: false),
        tlsHandshake: _okAdapter(calls, tls: true),
      );
      final r = await svc.probe(tlsCandidate);
      expect(r.reachable, isTrue);
      expect(r.errorClass, isNull);
      expect(calls.tls, 1);
      expect(calls.tcp, 0, reason: 'TLS path subsumes TCP, no extra dial');
    });

    test('HandshakeException → errorClass=tls_fail', () async {
      final svc = DefaultRelayProbeService(
        tcpConnect: _okAdapter(calls, tls: false),
        tlsHandshake: _throwing(
            () => const HandshakeException('CERTIFICATE_VERIFY_FAILED')),
      );
      final r = await svc.probe(tlsCandidate);
      expect(r.reachable, isFalse);
      expect(r.errorClass, ProbeError.tlsFail);
    });

    test('TLS timeout → errorClass=timeout (not tls_fail)', () async {
      final svc = DefaultRelayProbeService(
        tcpConnect: _okAdapter(calls, tls: false),
        tlsHandshake: _throwing(() => TimeoutException('mock')),
      );
      final r = await svc.probe(tlsCandidate);
      expect(r.errorClass, ProbeError.timeout);
    });

    test('TLS path SocketException inherits TCP classification (dns_fail)',
        () async {
      // If DNS fails during TLS dial, classify as dns_fail — not tls_fail.
      // Otherwise "which layer broke" becomes ambiguous for telemetry.
      final svc = DefaultRelayProbeService(
        tcpConnect: _okAdapter(calls, tls: false),
        tlsHandshake: _throwing(() => const SocketException(
              "Failed host lookup: 'relay.example.com'",
              osError: OSError('not known', 8),
            )),
      );
      final r = await svc.probe(tlsCandidate);
      expect(r.errorClass, ProbeError.dnsFail);
    });
  });

  group('DefaultRelayProbeService — TLS need detection', () {
    late _CallTracker calls;
    late DefaultRelayProbeService svc;

    setUp(() {
      calls = _CallTracker();
      svc = DefaultRelayProbeService(
        tcpConnect: _okAdapter(calls, tls: false),
        tlsHandshake: _okAdapter(calls, tls: true),
      );
    });

    test('naked vless (no tls, no reality) → TCP path, no TLS', () async {
      await svc.probe(_c(type: 'vless'));
      expect(calls.tcp, 1);
      expect(calls.tls, 0);
    });

    test('vless + tls:true → TLS path', () async {
      await svc.probe(_c(type: 'vless', extras: {'tls': true}));
      expect(calls.tls, 1);
      expect(calls.tcp, 0);
    });

    test('vless + reality-opts → TLS path even without tls flag', () async {
      await svc.probe(_c(type: 'vless', extras: {
        'reality-opts': {'public-key': 'abc'},
      }));
      expect(calls.tls, 1);
      expect(calls.tcp, 0);
    });

    test('vless + alt reality key → TLS path', () async {
      await svc.probe(_c(type: 'vless', extras: {
        'reality': {'public-key': 'abc'},
      }));
      expect(calls.tls, 1);
    });

    test('vless with empty reality-opts map → NOT treated as reality',
        () async {
      // Guard against accidental `reality-opts: {}` in a subscription: an
      // empty map does not mean "reality configured".
      await svc.probe(_c(type: 'vless', extras: {'reality-opts': {}}));
      expect(calls.tcp, 1);
      expect(calls.tls, 0);
    });

    test('trojan (no extras) → TLS path (protocol requires TLS)', () async {
      await svc.probe(_c(type: 'trojan'));
      expect(calls.tls, 1);
    });

    test('anytls (no extras) → TLS path', () async {
      await svc.probe(_c(type: 'anytls'));
      expect(calls.tls, 1);
    });

    test('vmess + tls:true → TLS path (tls flag generalises across types)',
        () async {
      await svc.probe(_c(type: 'vmess', extras: {'tls': true}));
      expect(calls.tls, 1);
    });

    test('naked vmess → TCP path', () async {
      await svc.probe(_c(type: 'vmess'));
      expect(calls.tcp, 1);
      expect(calls.tls, 0);
    });

    test('direct candidate inherits detection from exitType + exitExtras',
        () async {
      // direct.toRelayProfile() would throw, but probing direct is legal —
      // TLS detection runs off type/extras regardless of kind.
      await svc.probe(_direct(exitType: 'trojan'));
      expect(calls.tls, 1);

      calls.reset();
      await svc.probe(_direct(exitType: 'vless'));
      expect(calls.tcp, 1);
      expect(calls.tls, 0);
    });

    test('TLS flag is strict boolean — "tls: \'true\'" (string) does NOT count',
        () async {
      await svc.probe(_c(type: 'vless', extras: {'tls': 'true'}));
      expect(calls.tcp, 1);
      expect(calls.tls, 0);
    });
  });

  group('DefaultRelayProbeService — enableL3 (not implemented in 1B)', () {
    late _CallTracker calls;

    setUp(() => calls = _CallTracker());

    test('enableL3=true short-circuits to l3_unsupported result', () async {
      final svc = DefaultRelayProbeService(
        tcpConnect: _okAdapter(calls, tls: false),
        tlsHandshake: _okAdapter(calls, tls: true),
      );
      final r = await svc.probe(_c(type: 'vless', extras: {'tls': true}),
          enableL3: true);
      expect(r.reachable, isFalse);
      expect(r.errorClass, ProbeError.l3Unsupported);
      expect(r.latencyMs, isNull);
    });

    test('enableL3=true does NOT invoke tcpConnect or tlsHandshake', () async {
      final svc = DefaultRelayProbeService(
        tcpConnect: _okAdapter(calls, tls: false),
        tlsHandshake: _okAdapter(calls, tls: true),
      );
      await svc.probe(_c(type: 'vless'), enableL3: true);
      await svc.probe(_c(type: 'trojan'), enableL3: true);
      expect(calls.tcp, 0,
          reason: 'enableL3=true must not reach the TCP adapter');
      expect(calls.tls, 0,
          reason: 'enableL3=true must not reach the TLS adapter');
    });

    test('enableL3=false (default) runs the normal L1/L2 path', () async {
      final svc = DefaultRelayProbeService(
        tcpConnect: _okAdapter(calls, tls: false),
        tlsHandshake: _okAdapter(calls, tls: true),
      );
      final r = await svc.probe(_c(type: 'vless'));
      expect(r.reachable, isTrue);
      expect(r.errorClass, isNull);
      expect(calls.tcp, 1);
    });
  });
}
