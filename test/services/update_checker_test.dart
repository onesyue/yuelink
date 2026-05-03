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

  group('UpdateChecker.downloadMirrors', () {
    test('GitHub release asset gets gh-proxy + ghfast prepended', () {
      final url =
          'https://github.com/onesyue/yuelink/releases/download/v1.1.16/YueLink-macOS.dmg';
      final mirrors = UpdateChecker.downloadMirrors(url);
      expect(mirrors, hasLength(3));
      expect(mirrors[0], startsWith('https://gh-proxy.com/'));
      expect(mirrors[0], endsWith('/YueLink-macOS.dmg'));
      expect(mirrors[1], startsWith('https://ghfast.top/'));
      // Direct URL is the LAST entry — mirrors are tried first because
      // they're CN-friendly; direct GitHub release downloads are
      // reliably 50–200 KB/s inside the GFW.
      expect(mirrors.last, url);
    });

    test('non-GitHub URL passes through unmodified', () {
      const url = 'https://cdn.example.com/yuelink/foo.dmg';
      final mirrors = UpdateChecker.downloadMirrors(url);
      expect(mirrors, [url]);
    });

    test('GitHub URL that is not a /releases/download/ asset is unmodified',
        () {
      // raw.githubusercontent.com or repo tarball — not a release asset,
      // so the proxies wouldn't necessarily understand it. Pass through.
      const url =
          'https://raw.githubusercontent.com/onesyue/yuelink/master/README.md';
      final mirrors = UpdateChecker.downloadMirrors(url);
      expect(mirrors, [url]);
    });
  });
}
