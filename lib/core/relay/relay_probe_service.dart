import 'dart:async';
import 'dart:io';

import 'relay_candidate.dart';
import 'relay_metrics.dart';

/// Injectable TCP-connect adapter. Concrete contract: complete normally on
/// success; throw [TimeoutException] on timeout; throw [SocketException]
/// on any other failure (connection refused, DNS lookup failed, network
/// unreachable). Tests pass fakes that throw the specific exceptions they
/// want classified.
typedef TcpConnectFn = Future<void> Function(
  String host,
  int port,
  Duration timeout,
);

/// Injectable TLS-handshake adapter. Completes TCP + TLS in one call (the
/// production path uses [SecureSocket.connect]). Throws [TimeoutException],
/// [HandshakeException], [TlsException], or [SocketException] as appropriate.
typedef TlsHandshakeFn = Future<void> Function(
  String host,
  int port,
  Duration timeout,
);

/// Closed-set error classes that may appear in a ProbeResult from this
/// service. Exposed as constants so telemetry consumers can compare without
/// literal strings drifting across files.
abstract class ProbeError {
  static const timeout = 'timeout';
  static const tcpRefused = 'tcp_refused';
  static const dnsFail = 'dns_fail';
  static const tlsFail = 'tls_fail';

  /// Phase 1B sentinel: caller requested L3 but the real HTTP 204
  /// verification isn't implemented yet. Phase 1C will remove this
  /// value by actually performing the request.
  static const l3Unsupported = 'l3_unsupported';
}

/// Probes relay candidates to produce [ProbeResult] records for
/// [RelayMetrics]. Tier boundaries match the Phase 1B terminal spec:
///   L1 = TCP connect (always)
///   L2 = TLS handshake (when the candidate declares it needs TLS)
///   L3 = HTTP generate_204 (default off in 1B; 1C owns the real impl)
abstract class RelayProbeService {
  Future<ProbeResult> probe(
    RelayCandidate candidate, {
    bool enableL3 = false,
  });
}

/// Default implementation. Production uses [Socket.connect] /
/// [SecureSocket.connect]; tests inject fakes via [tcpConnect] /
/// [tlsHandshake] so no test ever touches the network.
class DefaultRelayProbeService implements RelayProbeService {
  final TcpConnectFn _tcpConnect;
  final TlsHandshakeFn _tlsHandshake;
  final Duration timeout;

  DefaultRelayProbeService({
    TcpConnectFn? tcpConnect,
    TlsHandshakeFn? tlsHandshake,
    this.timeout = const Duration(seconds: 3),
  })  : _tcpConnect = tcpConnect ?? _defaultTcpConnect,
        _tlsHandshake = tlsHandshake ?? _defaultTlsHandshake;

  @override
  Future<ProbeResult> probe(
    RelayCandidate candidate, {
    bool enableL3 = false,
  }) async {
    // L3 is not implemented in Phase 1B. Failing loudly (reachable: false
    // with a sentinel errorClass) is deliberate: a caller that flips this
    // flag on thinking it works will see the failure in metrics
    // immediately rather than silently degrade coverage.
    if (enableL3) {
      return ProbeResult(
        reachable: false,
        errorClass: ProbeError.l3Unsupported,
        at: DateTime.now(),
      );
    }

    final needsTls = _needsTls(candidate);
    final sw = Stopwatch()..start();

    try {
      if (needsTls) {
        // SecureSocket.connect wraps TCP + TLS into a single dial, so the
        // latency figure includes both phases — which is what we want to
        // compare against other TLS candidates.
        await _tlsHandshake(candidate.host, candidate.port, timeout);
      } else {
        await _tcpConnect(candidate.host, candidate.port, timeout);
      }
      sw.stop();
      return ProbeResult(
        reachable: true,
        latencyMs: sw.elapsedMilliseconds,
        at: DateTime.now(),
      );
    } catch (e) {
      return ProbeResult(
        reachable: false,
        errorClass: needsTls ? _classifyTlsError(e) : _classifyTcpError(e),
        at: DateTime.now(),
      );
    }
  }

  /// A candidate needs L2 TLS only when:
  ///   - extras['tls'] == true (explicit standard-TLS flag), or
  ///   - the type is trojan (TLS is part of the protocol surface).
  ///
  /// **Reality and AnyTLS are deliberately NOT here** even though they
  /// transport traffic inside something TLS-shaped. SecureSocket.connect
  /// can only validate plain TLS semantics; a successful dial against a
  /// Reality endpoint does NOT prove Reality steering accepts the
  /// client, and a failed dial can be misleading (steering may reject
  /// while the underlying TCP path would have worked for real VLESS
  /// traffic). Probing them at L1 (TCP only) at least confirms
  /// DNS/IP/port reachability without claiming protocol-level success
  /// we can't actually verify. mihomo exercises the real Reality / AnyTLS
  /// handshake at connect time. A5b decision — see related commit.
  ///
  /// Naked VLESS (no tls, no reality) also stays L1 — some deployments
  /// use VLESS over plain TCP on LAN or via a separate transport.
  static bool _needsTls(RelayCandidate c) {
    if (c.extras['tls'] == true) return true;
    final t = c.type.toLowerCase();
    if (t == 'trojan') return true;
    return false;
  }

  static String _classifyTcpError(Object error) {
    if (error is TimeoutException) return ProbeError.timeout;
    if (error is SocketException) {
      final combined =
          '${error.message.toLowerCase()} ${(error.osError?.message ?? '').toLowerCase()}';
      if (combined.contains('failed host lookup') ||
          combined.contains('no address associated') ||
          combined.contains('nodename nor servname') ||
          combined.contains('no such host') ||
          combined.contains('name or service not known')) {
        return ProbeError.dnsFail;
      }
      return ProbeError.tcpRefused;
    }
    return ProbeError.tcpRefused;
  }

  static String _classifyTlsError(Object error) {
    if (error is TimeoutException) return ProbeError.timeout;
    if (error is HandshakeException) return ProbeError.tlsFail;
    if (error is TlsException) return ProbeError.tlsFail;
    // A raw SocketException at TLS dial time is a TCP-layer failure;
    // inherit that classification so "DNS fail" and "refused" don't
    // silently get relabeled as tls_fail just because the candidate asked
    // for TLS.
    if (error is SocketException) return _classifyTcpError(error);
    return ProbeError.tlsFail;
  }

  static Future<void> _defaultTcpConnect(
    String host,
    int port,
    Duration timeout,
  ) async {
    final sock = await Socket.connect(host, port, timeout: timeout);
    await sock.close();
    sock.destroy();
  }

  static Future<void> _defaultTlsHandshake(
    String host,
    int port,
    Duration timeout,
  ) async {
    final sock = await SecureSocket.connect(host, port, timeout: timeout);
    await sock.close();
    sock.destroy();
  }
}
