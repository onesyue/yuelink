// Pure-Dart unit tests for GeoDataService's checksum verifier.
//
// We don't spin up an HTTP server here — the verifier is pure (bytes in,
// digest-line in, bool out) and that's all we need to prove the two
// production paths: legitimate match (accept the download) and digest
// mismatch (force the next mirror). Network I/O around this helper is
// covered by MihomoStream-style integration tests, not here.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/kernel/geodata_service.dart';

void main() {
  group('GeoDataService checksum', () {
    final bytes = utf8.encode('hello-yuelink-geodata');
    final realDigest = sha256.convert(bytes).toString();

    test('verifyChecksumForTest accepts a matching GNU sha256sum line', () {
      // `sha256sum <file>` format: "<64 hex>  <name>".
      final line = '$realDigest  GeoIP.dat\n';
      expect(
        GeoDataService.verifyChecksumForTest(bytes, line),
        isTrue,
        reason: 'matching digest should verify',
      );
    });

    test('verifyChecksumForTest accepts a bare-digest body (no filename)', () {
      // Some mirrors publish just the hex with a trailing newline.
      expect(
        GeoDataService.verifyChecksumForTest(bytes, '$realDigest\n'),
        isTrue,
      );
    });

    test('verifyChecksumForTest rejects a wrong digest (MITM simulation)', () {
      // All-zeros digest — legal hex, length 64, but won't match any real
      // payload. This is the "next mirror please" signal.
      const wrong =
          '0000000000000000000000000000000000000000000000000000000000000000';
      const line = '$wrong  GeoIP.dat\n';
      expect(
        GeoDataService.verifyChecksumForTest(bytes, line),
        isFalse,
        reason: 'non-matching digest must fail closed',
      );
    });

    test('verifyChecksumForTest rejects an unparseable sidecar body', () {
      // HTML 404 page, empty string, short hex — all should yield false.
      expect(GeoDataService.verifyChecksumForTest(bytes, ''), isFalse);
      expect(
        GeoDataService.verifyChecksumForTest(bytes, '<html>404</html>'),
        isFalse,
      );
      expect(GeoDataService.verifyChecksumForTest(bytes, 'deadbeef'), isFalse);
    });

    test('parseSha256Line handles canonical and CRLF variants', () {
      expect(
        GeoDataService.parseSha256Line('$realDigest  GeoIP.dat\r\n'),
        equals(realDigest),
      );
      expect(
        GeoDataService.parseSha256Line('   $realDigest\tGeoIP.dat'),
        equals(realDigest),
      );
      expect(GeoDataService.parseSha256Line(''), isNull);
      // Short hex token — not 64 chars.
      expect(GeoDataService.parseSha256Line('abc123  file'), isNull);
    });
  });
}
