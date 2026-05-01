// Regression guard for the v1.1.7 visual sweep that wrapped Nodes /
// Connections / Logs pages in `DecoratedBox(decoration:
// YLGlass.pageBackground(context))`.
//
// We assert at the *source* level rather than mounting these pages —
// each one pulls in heavy provider graphs (proxyGroupsProvider,
// connections WebSocket, log streams) that would require a full app
// bootstrap to render. The wrapper pattern is simple enough that a
// regex check is reliable: it covers both the "running" and "offline"
// branches of these pages without needing live data.
//
// If a future refactor moves the wrapper into a shared widget (e.g.
// `YLPageBackground(child: ...)`), update this test to look for that
// instead.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _filesUnderGuard = <String>[
  'lib/modules/nodes/nodes_page.dart',
  'lib/modules/connections/connections_page.dart',
  'lib/modules/logs/logs_page.dart',
];

// Match `DecoratedBox(... decoration: YLGlass.pageBackground(...)`
// across line breaks.
final _wrapperPattern = RegExp(
  r'DecoratedBox\s*\([^)]*decoration\s*:\s*YLGlass\.pageBackground\s*\(',
  multiLine: true,
  dotAll: true,
);

void main() {
  for (final path in _filesUnderGuard) {
    test('$path wraps Scaffold body in YLGlass.pageBackground', () {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'expected to run from project root ($path must exist)',
      );

      final source = file.readAsStringSync();
      final matches = _wrapperPattern.allMatches(source).length;

      expect(
        matches,
        greaterThanOrEqualTo(1),
        reason:
            'Expected at least one DecoratedBox(decoration: '
            'YLGlass.pageBackground(...)) wrapper in $path. '
            'The page background visual is part of the v1.1.7 sweep '
            'and must remain wired up — see CLAUDE.md.',
      );
    });
  }

  test('all three pages combined have at least one wrapper each', () {
    final perFile = <String, int>{};
    for (final path in _filesUnderGuard) {
      final source = File(path).readAsStringSync();
      perFile[path] = _wrapperPattern.allMatches(source).length;
    }
    final missing = perFile.entries.where((e) => e.value == 0).toList();
    expect(
      missing,
      isEmpty,
      reason:
          'All three pages must wire YLGlass.pageBackground at least '
          'once. Missing: ${missing.map((e) => e.key).join(', ')}',
    );
  });
}
