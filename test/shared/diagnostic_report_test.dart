import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/diagnostic_report.dart';

/// Tests for [DiagnosticReport.redactForTest] (the privacy redaction
/// helper). Locks the contract that user-identifying paths and secrets
/// never leak into the "可直接整段粘贴" report.
void main() {
  group('DiagnosticReport redaction (privacy)', () {
    test('strips homeDir=<path> marker (the original leak)', () {
      // Real string from core_manager.dart::initCore step return value.
      // macOS Application Support path contains a space — a naive
      // `homeDir=\S+` regex stops at the first space and leaves
      // "Support/YueLink" exposed. This fixture locks the full-path
      // strip behaviour.
      const raw = 'homeDir=/Users/beita/Library/Application Support/YueLink';
      final redacted = DiagnosticReport.redactForTest(raw);
      expect(redacted, contains('homeDir=<redacted>'));
      expect(redacted, isNot(contains('beita')));
      // Whole path swallowed, not just the username segment.
      expect(redacted, isNot(contains('Library')));
      expect(redacted, isNot(contains('Application Support')));
      expect(redacted, isNot(contains('Support/YueLink')));
    });

    test('strips homeDir=<path> mid-detail (comma boundary preserved)', () {
      // Real string from desktop_service_mode.dart::buildConfig step
      // return value. homeDir is one of several `key=value` pairs
      // separated by `, `; redaction must stop at the `, ` boundary so
      // non-PII keys (apiPort / mixedPort) survive intact.
      const raw =
          'output=12345b, apiPort=9090, mixedPort=7890, '
          'homeDir=/Users/eve/Library/Application Support/YueLink, '
          'tunFd=42';
      final redacted = DiagnosticReport.redactForTest(raw);
      expect(redacted, contains('homeDir=<redacted>'));
      expect(redacted, isNot(contains('eve')));
      expect(redacted, isNot(contains('Application Support')));
      // Non-PII context preserved on either side of homeDir.
      expect(redacted, contains('apiPort=9090'));
      expect(redacted, contains('mixedPort=7890'));
      expect(redacted, contains('tunFd=42'));
      expect(redacted, contains('output=12345b'));
    });

    test('strips macOS user paths', () {
      const raw = 'failed to load /Users/alice/Documents/foo.yaml';
      final redacted = DiagnosticReport.redactForTest(raw);
      expect(redacted, isNot(contains('alice')));
      expect(redacted, contains('/Users/<redacted>'));
    });

    test('strips Linux user paths', () {
      const raw = 'home dir=/home/bob/.config/yuelink';
      final redacted = DiagnosticReport.redactForTest(raw);
      expect(redacted, isNot(contains('bob')));
      expect(redacted, contains('/home/<redacted>'));
    });

    test('strips Windows user paths (case-insensitive drive)', () {
      // PowerShell may return mixed case; cmd output sometimes lower.
      const raw1 = r'C:\Users\Carol\AppData\Roaming\yuelink';
      const raw2 = r'd:\users\dave\appdata\roaming\yuelink';
      final r1 = DiagnosticReport.redactForTest(raw1);
      final r2 = DiagnosticReport.redactForTest(raw2);
      expect(r1, isNot(contains('Carol')));
      expect(r1, contains(r'Users\<redacted>'));
      expect(r2, isNot(contains('dave')));
      expect(r2, contains(r'Users\<redacted>'));
    });

    test('strips Android per-user data path (Secure Folder leak)', () {
      const raw =
          'flushed cache to /data/user/95/com.yueto.yuelink/cache/foo.bin';
      final redacted = DiagnosticReport.redactForTest(raw);
      // Both the user index (95 = Samsung Secure Folder) and package
      // name carry signal — strip the package name component.
      expect(redacted, isNot(contains('com.yueto.yuelink')));
      expect(redacted, contains('/data/user/0/<redacted>'));
    });

    test('strips controller secret hex', () {
      const raw =
          'failed: secret=deadbeefdeadbeefdeadbeefdeadbeef rejected by API';
      final redacted = DiagnosticReport.redactForTest(raw);
      expect(redacted, isNot(contains('deadbeef')));
      expect(redacted, contains('secret=<redacted>'));
    });

    test('preserves non-PII content (mihomo error codes, ports)', () {
      const raw =
          '[E007_API_TIMEOUT] waitApi: 14000ms exceeded, mixedPort=7891';
      final redacted = DiagnosticReport.redactForTest(raw);
      // Must keep error code + diagnostic numbers
      expect(redacted, contains('E007_API_TIMEOUT'));
      expect(redacted, contains('waitApi'));
      expect(redacted, contains('14000ms'));
      expect(redacted, contains('mixedPort=7891'));
    });

    test('idempotent — already-redacted strings stay stable', () {
      const raw = 'homeDir=<redacted> at /Users/<redacted>/foo';
      final once = DiagnosticReport.redactForTest(raw);
      final twice = DiagnosticReport.redactForTest(once);
      expect(twice, equals(once));
    });

    test('multi-pattern in single line all redacted', () {
      const raw = '''
boot failed:
  homeDir=/Users/eve/Library/X
  secret=cafebabecafebabecafebabecafebabe
  detail=C:\\Users\\Frank\\AppData
''';
      final redacted = DiagnosticReport.redactForTest(raw);
      expect(redacted, isNot(contains('eve')));
      expect(redacted, isNot(contains('cafebabe')));
      expect(redacted, isNot(contains('Frank')));
    });
  });
}
