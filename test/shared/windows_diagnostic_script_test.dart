import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/windows_diagnostic_script.dart';

void main() {
  group('WindowsDiagnosticScript.generate', () {
    test('substitutes mixedPort and apiPort placeholders', () {
      final script = WindowsDiagnosticScript.generate(
        mixedPort: 7891,
        apiPort: 9091,
      );
      expect(script, contains('mixedPort: 7891'));
      expect(script, contains('apiPort: 9091'));
      expect(script, contains('http://127.0.0.1:9091/configs'));
      // Verify placeholders fully replaced (none left raw)
      expect(script, isNot(contains('__MIXED_PORT__')));
      expect(script, isNot(contains('__API_PORT__')));
    });

    test('contains all 9 numbered diagnostic sections', () {
      final script = WindowsDiagnosticScript.generate();
      for (var i = 1; i <= 9; i++) {
        expect(
          script,
          contains('"$i.'),
          reason: 'missing section $i in PowerShell script',
        );
      }
    });

    test('emits markdown report with code fences', () {
      final script = WindowsDiagnosticScript.generate();
      expect(script, contains("[void]\$out.AppendLine('```')"));
      expect(script, contains('# YueLink Windows 诊断报告'));
    });

    test('does NOT modify any system state (read-only sanity check)', () {
      final script = WindowsDiagnosticScript.generate();
      // No `Set-` cmdlets, no `New-` writes, no `Remove-`. Only
      // `Get-`, `pnputil /enum-drivers` (read), `route print` (read),
      // `sc query` (read), `Invoke-WebRequest -UseBasicParsing` (read).
      const writeCmdlets = ['Set-Item', 'New-NetIPAddress', 'Remove-Item'];
      for (final cmd in writeCmdlets) {
        expect(
          script,
          isNot(contains(cmd)),
          reason: '$cmd would modify system state — script must be read-only',
        );
      }
    });
  });
}
