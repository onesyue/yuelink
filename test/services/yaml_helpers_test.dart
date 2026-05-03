import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/kernel/config/yaml_helpers.dart';

void main() {
  group('yaml_helpers.hasKey', () {
    test('matches top-level key only', () {
      const config = 'dns:\n  enable: true\n  fake-ip-range: 198.18.0.1/16\n';

      expect(hasKey(config, 'dns'), isTrue);
      expect(hasKey(config, 'fake-ip-range'), isFalse);
    });

    test('escapes regex metacharacters in key names', () {
      const config = 'a.b:\n  value: 1\n';

      expect(hasKey(config, 'a.b'), isTrue);
      expect(hasKey(config, 'axb'), isFalse);
    });
  });

  group('yaml_helpers.replaceScalar', () {
    test('replaces top-level scalar value', () {
      const config = 'find-process-mode: always\ndns:\n  enable: true\n';

      expect(
        replaceScalar(config, 'find-process-mode', 'off'),
        'find-process-mode: off\ndns:\n  enable: true\n',
      );
    });

    test('escapes regex metacharacters in key names', () {
      const config = 'a.b: old\naxb: keep\n';

      expect(replaceScalar(config, 'a.b', 'new'), 'a.b: new\naxb: keep\n');
    });
  });

  group('yaml_helpers.bodyOf', () {
    test('returns text after the header newline', () {
      expect(bodyOf('dns:\n  enable: true\n'), '  enable: true\n');
    });

    test('returns empty string when section has no body', () {
      expect(bodyOf('dns:'), isEmpty);
    });
  });
}
