import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/kernel/config/yaml_indent_detector.dart';

void main() {
  group('YamlIndentDetector.findTopLevelSection', () {
    test('returns null when key is absent', () {
      const config = 'mixed-port: 7890\nproxies: []\n';
      expect(
        YamlIndentDetector.findTopLevelSection(config, 'dns'),
        isNull,
      );
    });

    test('returns null when key is only present indented (not at col 0)', () {
      const config = 'dns:\n  enable: true\n  fake-ip-range: 198.18.0.1/16\n';
      // The nested "fake-ip-range" should NOT match a top-level "fake-ip-range:"
      expect(
        YamlIndentDetector.findTopLevelSection(config, 'fake-ip-range'),
        isNull,
      );
    });

    test('finds section in the middle of a document', () {
      const config = 'mixed-port: 7890\n'
          'dns:\n'
          '  enable: true\n'
          '  ipv6: false\n'
          'proxies: []\n';
      final range = YamlIndentDetector.findTopLevelSection(config, 'dns');
      expect(range, isNotNull);
      expect(range!.start, config.indexOf('dns:'));
      expect(range.bodyStart, config.indexOf('  enable: true'));
      expect(range.end, config.indexOf('proxies: []'));
      expect(range.body, '  enable: true\n  ipv6: false\n');
    });

    test('finds section at end of file (no trailing top-level key)', () {
      const config = 'mixed-port: 7890\n'
          'dns:\n'
          '  enable: true\n';
      final range = YamlIndentDetector.findTopLevelSection(config, 'dns');
      expect(range, isNotNull);
      expect(range!.end, config.length);
      expect(range.body, '  enable: true\n');
    });

    test('handles section with empty body', () {
      const config = 'mixed-port: 7890\ndns:\nproxies: []\n';
      final range = YamlIndentDetector.findTopLevelSection(config, 'dns');
      expect(range, isNotNull);
      expect(range!.bodyStart, range.end);
      expect(range.body, isEmpty);
    });

    test(
      'default mode: top-level # comment does NOT end section',
      () {
        const config = 'dns:\n'
            '  enable: true\n'
            '# top-level comment\n'
            '  ipv6: false\n'
            'proxies: []\n';
        final range = YamlIndentDetector.findTopLevelSection(config, 'dns');
        expect(range, isNotNull);
        // Body contains both lines AND the comment because the comment
        // does not break the section.
        expect(range!.body, contains('  enable: true'));
        expect(range.body, contains('# top-level comment'));
        expect(range.body, contains('  ipv6: false'));
      },
    );

    test(
      'topLevelCommentsEndSection: true — # comment at col 0 ends section',
      () {
        const config = 'rule-providers:\n'
            '  google:\n'
            '    type: http\n'
            '# divider\n'
            '  github:\n'
            '    type: http\n';
        final defaultRange = YamlIndentDetector.findTopLevelSection(
          config,
          'rule-providers',
        );
        final strictRange = YamlIndentDetector.findTopLevelSection(
          config,
          'rule-providers',
          topLevelCommentsEndSection: true,
        );
        // Default: comment is included, body covers both providers.
        expect(defaultRange!.body, contains('  github:'));
        // Strict: section ends at the comment, body excludes github block.
        expect(strictRange!.body, isNot(contains('  github:')));
        expect(strictRange.body, contains('  google:'));
        expect(strictRange.end, lessThan(defaultRange.end));
      },
    );

    test(
      'requireBlockHeader: false (default) accepts inline rules: []',
      () {
        const config = 'rules: []\n';
        final range = YamlIndentDetector.findTopLevelSection(config, 'rules');
        expect(range, isNotNull);
      },
    );

    test(
      'requireBlockHeader: true rejects inline rules: [] (no \\s*\\n match)',
      () {
        const config = 'rules: []\n';
        final range = YamlIndentDetector.findTopLevelSection(
          config,
          'rules',
          requireBlockHeader: true,
        );
        expect(
          range,
          isNull,
          reason:
              'inline flow-style empty list must not be picked up as a '
              'block-style section — injecting children would produce '
              'invalid YAML like `rules: []\\n  - X`',
        );
      },
    );

    test(
      'requireBlockHeader: true rejects rules: false (scalar, not block)',
      () {
        const config = 'rules: false\n';
        expect(
          YamlIndentDetector.findTopLevelSection(
            config,
            'rules',
            requireBlockHeader: true,
          ),
          isNull,
        );
      },
    );

    test(
      'requireBlockHeader: true accepts block-style rules with body',
      () {
        const config = 'rules:\n  - MATCH,DIRECT\n';
        final range = YamlIndentDetector.findTopLevelSection(
          config,
          'rules',
          requireBlockHeader: true,
        );
        expect(range, isNotNull);
        expect(range!.bodyStart, 'rules:\n'.length);
        expect(range.body, '  - MATCH,DIRECT\n');
      },
    );

    test(
      'requireBlockHeader: true greedy whitespace consumes blank header lines',
      () {
        // `\s*` after `rules:` may pull in blank lines before the first
        // child. The historical `^rules:\s*\n` pattern relied on this
        // greediness — body must start AFTER the consumed whitespace.
        const config = 'rules:\n\n  - MATCH,DIRECT\n';
        final range = YamlIndentDetector.findTopLevelSection(
          config,
          'rules',
          requireBlockHeader: true,
        );
        expect(range, isNotNull);
        // bodyStart is *after* the second \n (greedy match), so body
        // begins directly with the first child line.
        expect(range!.body, '  - MATCH,DIRECT\n');
      },
    );

    test('escapes regex metacharacters in key name', () {
      // "fake-ip-filter" contains a hyphen which is regex-safe; but a
      // hypothetical key with "." or "+" must be matched literally.
      const config = 'a.b:\n'
          '  value: 1\n'
          'other: 2\n';
      final range = YamlIndentDetector.findTopLevelSection(config, 'a.b');
      expect(range, isNotNull);
      expect(range!.body, '  value: 1\n');
    });
  });

  group('YamlIndentDetector.detectChildIndent', () {
    test('returns first child indent (2 spaces, allowTabs=false)', () {
      const body = '  enable: true\n  ipv6: false\n';
      expect(
        YamlIndentDetector.detectChildIndent(body, allowTabs: false),
        '  ',
      );
    });

    test('returns first child indent (4 spaces, allowTabs=false)', () {
      const body = '    enable: true\n    ipv6: false\n';
      expect(
        YamlIndentDetector.detectChildIndent(body, allowTabs: false),
        '    ',
      );
    });

    test('first line of body IS counted (no preceding newline gotcha)', () {
      // Regression for the "\\n(...)" anchoring trap that excluded the
      // first line. The new ^ multiLine form must include it.
      const body = '  first-line: yes\n  second-line: no\n';
      expect(
        YamlIndentDetector.detectChildIndent(body, allowTabs: false),
        '  ',
      );
    });

    test('returns fallback when body is empty', () {
      expect(
        YamlIndentDetector.detectChildIndent('', allowTabs: false),
        '  ',
      );
      expect(
        YamlIndentDetector.detectChildIndent(
          '',
          allowTabs: false,
          fallback: '    ',
        ),
        '    ',
      );
    });

    test('returns fallback when body has no indented lines', () {
      const body = 'no-indent: here\n';
      expect(
        YamlIndentDetector.detectChildIndent(body, allowTabs: false),
        '  ',
      );
    });

    test('allowTabs=false ignores tab-indented lines', () {
      const body = '\ttab-indented: yes\n  space-indented: no\n';
      expect(
        YamlIndentDetector.detectChildIndent(body, allowTabs: false),
        '  ',
      );
    });

    test('allowTabs=true matches tab-indented first line', () {
      const body = '\ttab-indented: yes\n  space-indented: no\n';
      expect(
        YamlIndentDetector.detectChildIndent(body, allowTabs: true),
        '\t',
      );
    });
  });

  group('YamlIndentDetector.detectListItemIndent', () {
    test('returns first list-item indent (4 spaces, allowTabs=false)', () {
      const body = '    - one\n    - two\n';
      expect(
        YamlIndentDetector.detectListItemIndent(body, allowTabs: false),
        '    ',
      );
    });

    test('first line of body IS counted', () {
      const body = '  - one\n  - two\n';
      expect(
        YamlIndentDetector.detectListItemIndent(body, allowTabs: false),
        '  ',
      );
    });

    test('returns fallback when body has no list items', () {
      const body = 'enable: true\nipv6: false\n';
      expect(
        YamlIndentDetector.detectListItemIndent(body, allowTabs: false),
        '  ',
      );
    });

    test(
      'allowTabs=false requires "- " (mandatory trailing space)',
      () {
        // "-x" with no space is not a YAML list item — old `\n( +)- ` form
        // would not match it either. New strict variant must match the
        // same shape.
        const body = '  -nospace: still-key\n  - real-item\n';
        expect(
          YamlIndentDetector.detectListItemIndent(body, allowTabs: false),
          '  ',
        );
      },
    );

    test('allowTabs=true accepts zero-indent list item', () {
      const body = '- one\n- two\n';
      expect(
        YamlIndentDetector.detectListItemIndent(body, allowTabs: true),
        '',
      );
    });

    test('allowTabs=false ignores zero-indent (needs >=1 space)', () {
      const body = '- one\n  - two\n';
      // strict regex `^( +)- ` requires one or more spaces, so first-line
      // "- one" is skipped and second-line "  - two" matches.
      expect(
        YamlIndentDetector.detectListItemIndent(body, allowTabs: false),
        '  ',
      );
    });
  });
}
