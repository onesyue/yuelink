import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/updater/update_checker.dart';

void main() {
  group('UpdateChecker manifest decoding', () {
    test('decodes UTF-8 release notes without mojibake', () {
      final bytes = utf8.encode(
        '{"version":"1.0.22-pre","notes":"发现新版本：启动兜底与诊断修复"}',
      );

      final manifest = UpdateChecker.decodeManifestForTest(bytes);

      expect(manifest, isNotNull);
      expect(manifest!['notes'], '发现新版本：启动兜底与诊断修复');
    });
  });
}
