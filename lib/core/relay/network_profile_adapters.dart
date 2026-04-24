import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'network_profile.dart';

/// Production implementations of the four [NetworkProfileService] adapters.
///
/// Each adapter is a static method that maps onto the corresponding
/// typedef in `network_profile_service.dart`. They never throw —
/// failures are translated to conservative defaults so a single broken
/// probe can't cap the whole sample.
///
/// Tested at the protocol-parser level (STUN response parsing) and at
/// the IPv6 address classification level. End-to-end real-network paths
/// are exercised in integration / production; tests in this PR don't
/// hit the network.
class NetworkProfileAdapters {
  NetworkProfileAdapters._();

  static const stunHost = 'stun.l.google.com';
  static const stunPort = 19302;
  static const ipv6ProbeHost = '2001:4860:4860::8888'; // Google Public DNS v6
  static const ipv6ProbePort = 443;
  static const probeTimeout = Duration(seconds: 3);

  /// True iff at least one local interface carries a global-unicast IPv6
  /// address (`2000::/3`, i.e. first byte in [0x20, 0x3F]). Loopback and
  /// link-local addresses are filtered by [NetworkInterface.list]
  /// itself; the byte check additionally excludes ULA (`fc00::/7`) and
  /// any other reserved range that survives the filter.
  static Future<bool> hasPublicIpv6() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv6,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final raw = addr.rawAddress;
          if (raw.isEmpty) continue;
          final first = raw[0];
          if (first >= 0x20 && first <= 0x3F) return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// True iff a TCP connect to a known public IPv6 destination
  /// completes within [probeTimeout]. Distinct from [hasPublicIpv6]:
  /// an interface can carry a global v6 address while the operator
  /// blocks outbound 443, or vice-versa.
  static Future<bool> ipv6Reachable() async {
    Socket? sock;
    try {
      sock = await Socket.connect(
        ipv6ProbeHost,
        ipv6ProbePort,
        timeout: probeTimeout,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await sock?.close();
      } catch (_) {}
      sock?.destroy();
    }
  }

  /// One STUN binding query against `stun.l.google.com`. Returns the
  /// XOR-MAPPED-ADDRESS the server saw, or null on any failure
  /// (timeout, DNS, parse error, etc.). The returned tuple is
  /// stage-of-call only; [NetworkProfileService] consumes it for NAT
  /// classification and discards immediately. **Never persisted.**
  static Future<({String ip, int port})?> stunQuery() async {
    RawDatagramSocket? socket;
    StreamSubscription? sub;
    try {
      // Bind to ephemeral port — the source-port differs across calls,
      // which is what enables the symmetric/non-symmetric distinction
      // in [NetworkProfileService._probeNat].
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      final addrs = await InternetAddress.lookup(stunHost,
          type: InternetAddressType.IPv4);
      if (addrs.isEmpty) return null;

      final txId = _randomTransactionId();
      final request = buildBindingRequest(txId);
      socket.send(request, addrs.first, stunPort);

      final completer = Completer<({String ip, int port})?>();
      late final Timer timer;
      timer = Timer(probeTimeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });
      sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket?.receive();
        if (dg == null) return;
        final result = parseBindingResponse(dg.data, txId);
        if (result != null && !completer.isCompleted) {
          completer.complete(result);
          timer.cancel();
        }
      });
      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      await sub?.cancel();
      socket?.close();
    }
  }

  /// Best-effort network kind. Without `connectivity_plus` (kept out of
  /// pubspec to avoid a new dependency in 1B) mobile platforms always
  /// return [NetworkKind.unknown]; desktop uses Linux interface naming
  /// conventions (`wlan*`/`wlp*` for wifi, `eth*`/`enp*`/`eno*` for
  /// ethernet). macOS naming (`en0`, `en1`, …) is intentionally not
  /// matched — `en0` is wifi on most laptops but ethernet on some
  /// configurations, and a wrong answer is worse than `unknown`.
  static Future<NetworkKind> networkKind() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        return NetworkKind.unknown;
      }
      final interfaces = await NetworkInterface.list(includeLoopback: false);
      for (final iface in interfaces) {
        if (iface.addresses.isEmpty) continue;
        final name = iface.name.toLowerCase();
        if (Platform.isLinux) {
          if (name.startsWith('wlan') || name.startsWith('wlp')) {
            return NetworkKind.wifi;
          }
          if (name.startsWith('eth') ||
              name.startsWith('enp') ||
              name.startsWith('eno')) {
            return NetworkKind.ethernet;
          }
        }
      }
      return NetworkKind.unknown;
    } catch (_) {
      return NetworkKind.unknown;
    }
  }

  // ── STUN protocol helpers (public for unit tests only) ─────────────

  /// Build a STUN binding request (RFC 5389 §6.2.1).
  /// 20-byte header, no attributes.
  static Uint8List buildBindingRequest(Uint8List transactionId) {
    if (transactionId.length != 12) {
      throw ArgumentError('transactionId must be exactly 12 bytes');
    }
    final buf = Uint8List(20);
    // Message type: 0x0001 Binding Request
    buf[0] = 0x00;
    buf[1] = 0x01;
    // Message length: 0 (no attributes)
    buf[2] = 0x00;
    buf[3] = 0x00;
    // Magic cookie: 0x2112A442
    buf[4] = 0x21;
    buf[5] = 0x12;
    buf[6] = 0xA4;
    buf[7] = 0x42;
    // Transaction ID
    for (var i = 0; i < 12; i++) {
      buf[8 + i] = transactionId[i];
    }
    return buf;
  }

  /// Parse a STUN binding response, returning the XOR-MAPPED-ADDRESS as
  /// a `(ip, port)` record. Returns null when the response isn't a valid
  /// binding response, doesn't match the expected transaction id, or
  /// doesn't contain XOR-MAPPED-ADDRESS.
  ///
  /// Only XOR-MAPPED-ADDRESS (type 0x0020) is parsed — older
  /// MAPPED-ADDRESS (type 0x0001) is intentionally NOT supported. The
  /// XOR variant exists specifically because middleboxes rewrite the
  /// older form; any modern STUN server we'd talk to returns the XOR
  /// form.
  static ({String ip, int port})? parseBindingResponse(
      Uint8List data, Uint8List expectedTransactionId) {
    if (data.length < 20) return null;
    // Verify message type 0x0101 (Binding Response)
    if (data[0] != 0x01 || data[1] != 0x01) return null;
    // Verify magic cookie
    if (data[4] != 0x21 ||
        data[5] != 0x12 ||
        data[6] != 0xA4 ||
        data[7] != 0x42) {
      return null;
    }
    // Verify transaction ID matches
    if (expectedTransactionId.length != 12) return null;
    for (var i = 0; i < 12; i++) {
      if (data[8 + i] != expectedTransactionId[i]) return null;
    }

    var pos = 20;
    while (pos + 4 <= data.length) {
      final attrType = (data[pos] << 8) | data[pos + 1];
      final attrLen = (data[pos + 2] << 8) | data[pos + 3];
      pos += 4;
      if (pos + attrLen > data.length) break;

      if (attrType == 0x0020 && attrLen >= 8) {
        // XOR-MAPPED-ADDRESS
        // [0] reserved [1] family [2..3] port [4..] address
        final family = data[pos + 1];
        final port = ((data[pos + 2] << 8) | data[pos + 3]) ^ 0x2112;
        if (family == 0x01 && attrLen >= 8) {
          // IPv4 — XOR with first 4 bytes of magic cookie
          final a = data[pos + 4] ^ 0x21;
          final b = data[pos + 5] ^ 0x12;
          final c = data[pos + 6] ^ 0xA4;
          final d = data[pos + 7] ^ 0x42;
          return (ip: '$a.$b.$c.$d', port: port);
        }
        if (family == 0x02 && attrLen >= 20) {
          // IPv6 — XOR with magic cookie + transaction id
          final ipBytes = Uint8List(16);
          ipBytes[0] = data[pos + 4] ^ 0x21;
          ipBytes[1] = data[pos + 5] ^ 0x12;
          ipBytes[2] = data[pos + 6] ^ 0xA4;
          ipBytes[3] = data[pos + 7] ^ 0x42;
          for (var i = 0; i < 12; i++) {
            ipBytes[4 + i] = data[pos + 8 + i] ^ expectedTransactionId[i];
          }
          return (
            ip: InternetAddress.fromRawAddress(ipBytes,
                    type: InternetAddressType.IPv6)
                .address,
            port: port,
          );
        }
      }
      // Attributes are 4-byte aligned
      pos += attrLen;
      final pad = attrLen % 4;
      if (pad != 0) pos += 4 - pad;
    }
    return null;
  }

  static final _rng = Random.secure();

  static Uint8List _randomTransactionId() {
    final id = Uint8List(12);
    for (var i = 0; i < 12; i++) {
      id[i] = _rng.nextInt(256);
    }
    return id;
  }
}
