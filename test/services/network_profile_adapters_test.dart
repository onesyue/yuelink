import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/relay/network_profile_adapters.dart';

/// Construct a STUN binding response with the given XOR-MAPPED-ADDRESS.
/// This is a test-side helper — production never builds responses.
Uint8List _stunResponseIpv4({
  required Uint8List txId,
  required int port,
  required List<int> ipBytes,
}) {
  // Header (20) + attribute (4) + value (8) = 32 bytes
  final buf = Uint8List(32);
  // Type: Binding Response 0x0101
  buf[0] = 0x01;
  buf[1] = 0x01;
  // Length: 12 (one attribute, type+len header 4 + value 8)
  buf[2] = 0x00;
  buf[3] = 0x0C;
  // Magic cookie
  buf[4] = 0x21;
  buf[5] = 0x12;
  buf[6] = 0xA4;
  buf[7] = 0x42;
  for (var i = 0; i < 12; i++) {
    buf[8 + i] = txId[i];
  }
  // Attribute: XOR-MAPPED-ADDRESS (0x0020), length 8
  buf[20] = 0x00;
  buf[21] = 0x20;
  buf[22] = 0x00;
  buf[23] = 0x08;
  // Value: reserved + family + port (XOR'd) + address (XOR'd)
  buf[24] = 0x00;
  buf[25] = 0x01; // IPv4
  final xorPort = port ^ 0x2112;
  buf[26] = (xorPort >> 8) & 0xFF;
  buf[27] = xorPort & 0xFF;
  buf[28] = ipBytes[0] ^ 0x21;
  buf[29] = ipBytes[1] ^ 0x12;
  buf[30] = ipBytes[2] ^ 0xA4;
  buf[31] = ipBytes[3] ^ 0x42;
  return buf;
}

Uint8List _txId(int seed) {
  return Uint8List.fromList(List.generate(12, (i) => (i * 17 + seed) & 0xFF));
}

void main() {
  group('NetworkProfileAdapters.buildBindingRequest', () {
    test('produces a 20-byte RFC-5389 binding request', () {
      final tx = _txId(1);
      final req = NetworkProfileAdapters.buildBindingRequest(tx);
      expect(req.length, 20);
      // Type: 0x0001
      expect(req[0], 0x00);
      expect(req[1], 0x01);
      // Length: 0
      expect(req[2], 0x00);
      expect(req[3], 0x00);
      // Magic cookie
      expect(req.sublist(4, 8), [0x21, 0x12, 0xA4, 0x42]);
      // Transaction ID echoed verbatim
      expect(req.sublist(8, 20), tx);
    });

    test('rejects wrong-length transaction ID', () {
      expect(
        () => NetworkProfileAdapters.buildBindingRequest(Uint8List(11)),
        throwsArgumentError,
      );
      expect(
        () => NetworkProfileAdapters.buildBindingRequest(Uint8List(13)),
        throwsArgumentError,
      );
    });
  });

  group('NetworkProfileAdapters.parseBindingResponse', () {
    test('parses a valid IPv4 XOR-MAPPED-ADDRESS', () {
      final tx = _txId(2);
      final resp = _stunResponseIpv4(
        txId: tx,
        port: 54321,
        ipBytes: [203, 0, 113, 5],
      );
      final parsed = NetworkProfileAdapters.parseBindingResponse(resp, tx);
      expect(parsed, isNotNull);
      expect(parsed!.ip, '203.0.113.5');
      expect(parsed.port, 54321);
    });

    test('rejects mismatched transaction ID', () {
      final resp = _stunResponseIpv4(
        txId: _txId(3),
        port: 1000,
        ipBytes: [1, 2, 3, 4],
      );
      // Same response, but parse with a different expected txId.
      final parsed =
          NetworkProfileAdapters.parseBindingResponse(resp, _txId(99));
      expect(parsed, isNull);
    });

    test('rejects non-binding-response message types', () {
      final tx = _txId(4);
      final resp = _stunResponseIpv4(
        txId: tx,
        port: 1000,
        ipBytes: [1, 2, 3, 4],
      );
      // Mutate type to 0x0001 (binding request, not response)
      resp[0] = 0x00;
      resp[1] = 0x01;
      expect(NetworkProfileAdapters.parseBindingResponse(resp, tx), isNull);
    });

    test('rejects bad magic cookie', () {
      final tx = _txId(5);
      final resp = _stunResponseIpv4(
        txId: tx,
        port: 1000,
        ipBytes: [1, 2, 3, 4],
      );
      resp[4] = 0x00; // corrupt cookie
      expect(NetworkProfileAdapters.parseBindingResponse(resp, tx), isNull);
    });

    test('returns null on truncated input', () {
      expect(
        NetworkProfileAdapters.parseBindingResponse(
            Uint8List(10), _txId(6)),
        isNull,
      );
      expect(
        NetworkProfileAdapters.parseBindingResponse(
            Uint8List(0), _txId(6)),
        isNull,
      );
    });

    test('returns null when XOR-MAPPED-ADDRESS attribute is absent', () {
      // Header-only response (20 bytes) → no attributes
      final tx = _txId(7);
      final resp = Uint8List(20);
      resp[0] = 0x01;
      resp[1] = 0x01;
      resp[4] = 0x21;
      resp[5] = 0x12;
      resp[6] = 0xA4;
      resp[7] = 0x42;
      for (var i = 0; i < 12; i++) {
        resp[8 + i] = tx[i];
      }
      expect(NetworkProfileAdapters.parseBindingResponse(resp, tx), isNull);
    });

    test('parses XOR-MAPPED-ADDRESS even with trailing unknown attribute',
        () {
      final tx = _txId(8);
      // Build a response with XOR-MAPPED-ADDRESS + an unknown 4-byte attr
      final base = _stunResponseIpv4(
        txId: tx,
        port: 1234,
        ipBytes: [10, 20, 30, 40],
      );
      // Extend message length to include the trailing unknown attr.
      final extra = Uint8List(8); // 4-byte header + 4-byte value
      extra[0] = 0xFF;
      extra[1] = 0xFE;
      extra[2] = 0x00;
      extra[3] = 0x04;
      final extended = Uint8List(base.length + extra.length);
      extended.setAll(0, base);
      extended.setAll(base.length, extra);
      // Update message length: 12 (XOR attr) + 8 (extra) = 20 bytes.
      extended[2] = 0x00;
      extended[3] = 0x14;
      final parsed =
          NetworkProfileAdapters.parseBindingResponse(extended, tx);
      expect(parsed, isNotNull);
      expect(parsed!.ip, '10.20.30.40');
    });
  });
}
