import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/event_log.dart';

void main() {
  group('EventLog.formatTagged', () {
    test('formats tag, event, and context fields', () {
      final line = EventLog.formatTagged(
        'Auth',
        'login_failed',
        context: {'status': 401, 'host': 'api.example.com'},
      );

      expect(line, '[Auth] login_failed status=401 host=api.example.com');
    });

    test('redacts sensitive context values', () {
      final line = EventLog.formatTagged(
        'MihomoStream',
        'connect',
        context: {
          'token': 'abc123',
          'authorization': 'Bearer abc123',
          'path': '/traffic',
        },
      );

      expect(line, contains('token=<redacted>'));
      expect(line, contains('authorization=<redacted>'));
      expect(line, contains('path=/traffic'));
      expect(line, isNot(contains('abc123')));
    });

    test(
      'redacts PII keys (subscribe_url / order_no / email / phone / ip)',
      () {
        const sensitive = {
          'subscribe_url': 'https://sub.example/abc',
          'order_no': 'ORDER_123',
          'email': 'user@example.com',
          'phone': '+8613800000000',
          'ip': '203.0.113.10',
        };
        final line = EventLog.formatTagged(
          'Sync',
          'profile_refresh',
          context: {...sensitive, 'status': 'ok'},
        );

        // Every sensitive key must end up redacted — raw value must not leak.
        for (final entry in sensitive.entries) {
          expect(
            line,
            contains('${entry.key}=<redacted>'),
            reason: '${entry.key} must be redacted',
          );
          expect(
            line,
            isNot(contains(entry.value)),
            reason: 'raw value for ${entry.key} must not appear in log',
          );
        }
        // Non-sensitive field must still render verbatim (sanity: redaction
        // is opt-in per key, not a blanket mask).
        expect(line, contains('status=ok'));
      },
    );

    test('normalizes whitespace and truncates long values', () {
      final longValue =
          '${List.filled(80, 'x').join()}\n${List.filled(80, 'y').join()}';
      final line = EventLog.formatTagged(
        '[ModuleRuntime]',
        'parse_failed',
        context: {'error': longValue},
      );

      expect(line, startsWith('[ModuleRuntime] parse_failed error='));
      expect(line, isNot(contains('\n')));
      expect(line.length, lessThan(170));
      expect(line, endsWith('...'));
    });
  });
}
