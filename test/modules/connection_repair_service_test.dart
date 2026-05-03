import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/settings/connection_repair/connection_diagnostics_service.dart';

void main() {
  group('ConnectionDiagnosticsService.buildLogBundle', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('yl_diag_bundle_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('success path: existing files appear under their headers', () async {
      File('${tmp.path}/core.log').writeAsStringSync('CORE_BODY_LINE\n');
      File('${tmp.path}/event.log').writeAsStringSync('EVENT_BODY_LINE\n');

      final bundle = await ConnectionDiagnosticsService.buildLogBundle(
        appDir: tmp,
      );

      expect(bundle.filesFound, 2);
      expect(bundle.content, contains('CORE_BODY_LINE'));
      expect(bundle.content, contains('EVENT_BODY_LINE'));
      expect(bundle.content, contains('═══ core.log'));
      expect(bundle.content, contains('═══ event.log'));
      // Absent canonical files still emit a header so the reader can see
      // which expected files were missing.
      expect(bundle.content, contains('═══ crash.log'));
      expect(bundle.content, contains('<not present>'));
    });

    test('empty path: zero files yields filesFound=0 with placeholders',
        () async {
      final bundle = await ConnectionDiagnosticsService.buildLogBundle(
        appDir: tmp,
      );

      expect(bundle.filesFound, 0);
      // Bundle header still rendered.
      expect(bundle.content, contains('YueLink diagnostic bundle'));
      // Each canonical source has its <not present> marker.
      expect(bundle.content, contains('═══ core.log'));
      expect(bundle.content, contains('═══ mihomo-service.log'));
      expect(bundle.content, contains('═══ crash.log'));
      expect(bundle.content, contains('═══ event.log'));
      expect(bundle.content, contains('═══ startup_report.json'));
      // Absent rotated sidecars are silently skipped — no header for them.
      expect(bundle.content, isNot(contains('═══ core.log.1')));
      expect(bundle.content, isNot(contains('═══ core.log.2')));
    });

    test(
      'partial path: existing + absent mix; filesFound counts only present',
      () async {
        File('${tmp.path}/crash.log').writeAsStringSync('CRASH_BODY\n');

        final bundle = await ConnectionDiagnosticsService.buildLogBundle(
          appDir: tmp,
        );

        expect(bundle.filesFound, 1);
        expect(bundle.content, contains('CRASH_BODY'));
        expect(bundle.content, contains('<not present>'));
      },
    );

    test('extraSection appended under desktop_tun_diagnostics header',
        () async {
      File('${tmp.path}/core.log').writeAsStringSync('X\n');

      final bundle = await ConnectionDiagnosticsService.buildLogBundle(
        appDir: tmp,
        extraSection: 'TUN_PROBE_SNAPSHOT_LINE',
      );

      expect(bundle.content, contains('═══ desktop_tun_diagnostics'));
      expect(bundle.content, contains('TUN_PROBE_SNAPSHOT_LINE'));
    });

    test('rotated sidecars included when present', () async {
      File('${tmp.path}/core.log').writeAsStringSync('NEW\n');
      File('${tmp.path}/core.log.1').writeAsStringSync('OLD_1\n');
      File('${tmp.path}/core.log.2').writeAsStringSync('OLD_2\n');

      final bundle = await ConnectionDiagnosticsService.buildLogBundle(
        appDir: tmp,
      );

      expect(bundle.filesFound, 3);
      expect(bundle.content, contains('NEW'));
      expect(bundle.content, contains('OLD_1'));
      expect(bundle.content, contains('OLD_2'));
    });
  });

  group('ConnectionDiagnosticsService.redactDiagnosticText', () {
    test('masks IPv4 addresses', () {
      final out = ConnectionDiagnosticsService.redactDiagnosticText(
        'gateway 192.168.1.1 reached via 10.0.0.5',
      );
      expect(out, isNot(contains('192.168.1.1')));
      expect(out, isNot(contains('10.0.0.5')));
      expect(out, contains('<ip>'));
    });

    test('masks MAC addresses (colon and dash separators)', () {
      final out = ConnectionDiagnosticsService.redactDiagnosticText(
        'iface aa:bb:cc:dd:ee:ff peer 11-22-33-44-55-66',
      );
      expect(out, isNot(contains('aa:bb:cc:dd:ee:ff')));
      expect(out, isNot(contains('11-22-33-44-55-66')));
      expect(out.split('<mac>').length - 1, 2);
    });

    test('masks Bearer tokens', () {
      final out = ConnectionDiagnosticsService.redactDiagnosticText(
        'Authorization: Bearer abc.def-ghi_jkl~mno+pqr',
      );
      expect(out, isNot(contains('abc.def-ghi_jkl~mno+pqr')));
      expect(out, contains('Bearer <redacted>'));
    });

    test('leaves clean text unchanged', () {
      const input = 'no secrets here, just words';
      expect(
        ConnectionDiagnosticsService.redactDiagnosticText(input),
        input,
      );
    });
  });

  group('ConnectionDiagnosticsService.classifyHttpResponse', () {
    test('2xx maps to success', () {
      final r = ConnectionDiagnosticsService.classifyHttpResponse(
        statusCode: 200,
        latencyMs: 123,
        aiTarget: false,
      );
      expect(r.status, EndpointStatus.success);
      expect(r.errorClass, 'ok');
      expect(r.latencyMs, 123);
      expect(r.statusCode, 200);
    });

    test('3xx maps to success (reachable)', () {
      final r = ConnectionDiagnosticsService.classifyHttpResponse(
        statusCode: 301,
        latencyMs: 50,
        aiTarget: false,
      );
      expect(r.status, EndpointStatus.success);
    });

    test('4xx maps to success when not aiTarget (reachable but rejected)',
        () {
      final r = ConnectionDiagnosticsService.classifyHttpResponse(
        statusCode: 404,
        latencyMs: 80,
        aiTarget: false,
      );
      expect(r.status, EndpointStatus.success);
    });

    test('aiTarget 403 maps to limited with ai_blocked', () {
      final r = ConnectionDiagnosticsService.classifyHttpResponse(
        statusCode: 403,
        latencyMs: 90,
        aiTarget: true,
      );
      expect(r.status, EndpointStatus.limited);
      expect(r.errorClass, 'ai_blocked');
      expect(r.error, contains('AI 出口受限'));
    });

    test('aiTarget 429 maps to limited with http_429', () {
      final r = ConnectionDiagnosticsService.classifyHttpResponse(
        statusCode: 429,
        latencyMs: 90,
        aiTarget: true,
      );
      expect(r.status, EndpointStatus.limited);
      expect(r.errorClass, 'http_429');
    });

    test('non-aiTarget 403 still maps to success (reachable)', () {
      final r = ConnectionDiagnosticsService.classifyHttpResponse(
        statusCode: 403,
        latencyMs: 90,
        aiTarget: false,
      );
      expect(r.status, EndpointStatus.success);
    });

    test('5xx maps to failed with target_failed', () {
      final r = ConnectionDiagnosticsService.classifyHttpResponse(
        statusCode: 503,
        latencyMs: 90,
        aiTarget: false,
      );
      expect(r.status, EndpointStatus.failed);
      expect(r.errorClass, 'target_failed');
    });
  });

  group('ConnectionDiagnosticsService.classifyHttpError', () {
    test('TimeoutException → timeout', () {
      final r = ConnectionDiagnosticsService.classifyHttpError(
        TimeoutException('took too long'),
      );
      expect(r.status, EndpointStatus.failed);
      expect(r.errorClass, 'timeout');
    });

    test('"Failed host lookup" → dns_failed', () {
      final r = ConnectionDiagnosticsService.classifyHttpError(
        const SocketException('Failed host lookup: example.com'),
      );
      expect(r.errorClass, 'dns_failed');
    });

    test('handshake error → tls_failed', () {
      final r = ConnectionDiagnosticsService.classifyHttpError(
        const HandshakeException('handshake failed'),
      );
      expect(r.errorClass, 'tls_failed');
    });

    test('certificate error → tls_failed', () {
      final r = ConnectionDiagnosticsService.classifyHttpError(
        Exception('CERTIFICATE_VERIFY_FAILED'),
      );
      expect(r.errorClass, 'tls_failed');
    });

    test('"Connection reset" → connection_reset', () {
      final r = ConnectionDiagnosticsService.classifyHttpError(
        const SocketException('Connection reset by peer'),
      );
      expect(r.errorClass, 'connection_reset');
    });

    test('unknown error falls through to tcp_failed', () {
      final r = ConnectionDiagnosticsService.classifyHttpError(
        Exception('something else entirely'),
      );
      expect(r.errorClass, 'tcp_failed');
    });

    test('long unknown messages are truncated', () {
      final long = 'X' * 500;
      final r = ConnectionDiagnosticsService.classifyHttpError(
        Exception(long),
      );
      expect(r.errorClass, 'tcp_failed');
      expect((r.error ?? '').length, lessThanOrEqualTo(45));
      expect(r.error, endsWith('...'));
    });
  });

  group('ConnectionDiagnosticsService.desktopDiagnosticCommands', () {
    test('returns nonempty list on supported desktop platforms', () {
      final cmds = ConnectionDiagnosticsService.desktopDiagnosticCommands();
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        expect(cmds, isNotEmpty);
        for (final c in cmds) {
          expect(c.exe, isNotEmpty);
        }
      } else {
        expect(cmds, isEmpty);
      }
    });
  });
}
