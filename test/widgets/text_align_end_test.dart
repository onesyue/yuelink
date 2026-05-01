// Static guard: keep `textAlign:` named arguments using `TextAlign.end`
// (RTL-aware) rather than the hard-coded `TextAlign.right`.
//
// Note: positional uses of `TextAlign.right` (e.g. as a parameter to a
// custom column descriptor for tabular numeric columns in the connections
// table) are NOT covered here — they're intentional and locale-stable. The
// guard targets only the `textAlign: TextAlign.right` named-argument form,
// which is the one that affects RTL rendering of regular text widgets.
//
// File-level scan — no Flutter render.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'lib/modules uses textAlign: TextAlign.end (not .right) for named args',
    () {
      final modulesDir = Directory('lib/modules');
      expect(
        modulesDir.existsSync(),
        isTrue,
        reason: 'expected to run from project root (lib/modules must exist)',
      );

      final offenders = <String>[];
      // Match `textAlign: TextAlign.right` allowing arbitrary whitespace.
      final pattern = RegExp(r'textAlign\s*:\s*TextAlign\.right\b');

      for (final entity in modulesDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) continue;
          if (pattern.hasMatch(line)) {
            offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Use TextAlign.end (RTL-aware) instead of TextAlign.right for '
            '`textAlign:` named args. Offenders:\n${offenders.join('\n')}',
      );
    },
  );
}
