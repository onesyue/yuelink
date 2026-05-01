// Static guard: prevent regression to raw `BorderRadius.circular(<n>)` calls
// in lib/modules/. These should all go through the YLRadius design tokens
// (sm = 6, md = 8, lg = 12, xl = 20) so a future radius re-tuning has one
// source of truth.
//
// This is a file-level scan — no Flutter render needed. If it fails, the
// failure message lists every offending file:line:source so the drift is
// trivial to find and fix.
//
// Allowlist:
//  - YLRadius.* references (the canonical pattern)
//  - non-token integers (e.g. circular(3), circular(4), circular(999))
//    are intentionally left alone for now to keep the guard tight on the
//    four magic numbers that previously appeared throughout the modules.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _forbiddenLiterals = <int>[6, 8, 12, 20];

void main() {
  test('lib/modules has no raw BorderRadius.circular(6|8|12|20)', () {
    final modulesDir = Directory('lib/modules');
    expect(
      modulesDir.existsSync(),
      isTrue,
      reason: 'expected to run from project root (lib/modules must exist)',
    );

    final offenders = <String>[];
    final pattern = RegExp(
      r'BorderRadius\.circular\(\s*(\d+)(?:\.0)?\s*\)',
    );

    for (final entity in modulesDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Skip comments — the `//` may not be the first column on a long line
        // but for our purposes any comment-style line is fine to ignore.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        for (final m in pattern.allMatches(line)) {
          final n = int.tryParse(m.group(1) ?? '');
          if (n != null && _forbiddenLiterals.contains(n)) {
            offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'BorderRadius.circular(6|8|12|20) should be replaced with '
          'YLRadius.sm/md/lg/xl. Offenders:\n${offenders.join('\n')}',
    );
  });
}
