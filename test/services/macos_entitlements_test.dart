import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('macOS entitlements', () {
    for (final fileName in [
      'DebugProfile.entitlements',
      'Release.entitlements',
    ]) {
      test('$fileName allows user-selected read/write exports', () {
        final f = File('macos/Runner/$fileName');
        expect(f.existsSync(), isTrue);

        final xml = f.readAsStringSync();
        expect(
          xml,
          contains('com.apple.security.files.user-selected.read-write'),
          reason:
              'file_picker.saveFile() on macOS checks this entitlement before '
              'showing NSSavePanel. Without it, diagnostic export fails with '
              'ENTITLEMENT_REQUIRED_WRITE.',
        );
      });
    }
  });
}
