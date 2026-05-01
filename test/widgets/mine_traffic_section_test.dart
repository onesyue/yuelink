// Regression guard for the v1.1.9 type-scale tightening of the Mine
// (我的) traffic-summary card — `_MineTrafficSection` in
// `lib/modules/settings/settings_page.dart`.
//
// What we lock down:
//   1. The "used / total" headline uses YLText.titleMedium (15pt).
//   2. That headline enables tabular figures via YLText.tabularNums so
//      digits don't shift width as the values tick.
//   3. Both right-hand stats (used/total + expiry) align to the line end
//      (textAlign.end), preserving symmetric inset against the card edge.
//
// `_MineTrafficSection` is a private widget — pumping it directly would
// require either an exported test entry-point or rendering the entire
// SettingsPage (which depends on auth/updater/surge providers). Instead
// we assert against the source file. The targeted region is small enough
// that a regex over the class body gives reliable signal without needing
// AST parsing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _settingsPagePath = 'lib/modules/settings/settings_page.dart';

void main() {
  late String fullSource;
  late String classBody;

  setUpAll(() {
    final file = File(_settingsPagePath);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'expected to run from project root ($_settingsPagePath must exist)',
    );
    fullSource = file.readAsStringSync();

    // Slice from the class declaration to the end of file; the class is
    // near the bottom and is followed only by `_GuestLoginCard` etc., so
    // we don't need a precise upper bound — only the lower bound is used
    // to make sure we're inspecting THIS class and not a copy elsewhere.
    final classStart = fullSource.indexOf(
      'class _MineTrafficSection extends ConsumerWidget',
    );
    expect(
      classStart,
      isNonNegative,
      reason:
          'Could not find class _MineTrafficSection in $_settingsPagePath. '
          'If you renamed it, update this test.',
    );

    // Slice up to the next top-level `class _` declaration (or EOF).
    final after = fullSource.substring(classStart);
    final nextClassMatch = RegExp(
      r'\nclass\s+\w',
      multiLine: true,
    ).firstMatch(after.substring(1));
    final endRel = nextClassMatch?.start ?? after.length - 1;
    classBody = after.substring(0, endRel + 1);
  });

  test('headline uses YLText.titleMedium', () {
    expect(
      classBody.contains('style: YLText.titleMedium.copyWith('),
      isTrue,
      reason:
          'Expected the used/total headline to use YLText.titleMedium '
          '(15pt). Reverting to a different scale would regress v1.1.9.',
    );
  });

  test('headline enables tabular figures', () {
    expect(
      classBody.contains('fontFeatures: YLText.tabularNums'),
      isTrue,
      reason:
          'Expected YLText.tabularNums on the used/total headline so that '
          'digits don\'t reflow as bytes update. Drop this and the number '
          'jitters every refresh.',
    );
  });

  test('right-hand stats align to TextAlign.end', () {
    // Two `textAlign: TextAlign.end` are expected: one on the headline,
    // one on the expiry text.
    final endCount = RegExp(
      r'textAlign:\s*TextAlign\.end',
    ).allMatches(classBody).length;
    expect(
      endCount,
      greaterThanOrEqualTo(2),
      reason:
          'Expected at least two textAlign: TextAlign.end occurrences in '
          '_MineTrafficSection (headline + expiry). Found $endCount.',
    );
  });

  test('uses formatBytes (not raw int interpolation)', () {
    // `formatBytes(overview.transferUsedBytes)` etc. — guarantees the
    // bytes->human-readable contract documented in CLAUDE.md.
    expect(
      classBody.contains('formatBytes(overview.transferUsedBytes)'),
      isTrue,
      reason:
          'Expected formatBytes() on transferUsedBytes — XBoard returns '
          'bytes (per UserProfile traffic-units rule in CLAUDE.md).',
    );
    expect(
      classBody.contains('formatBytes(overview.transferTotalBytes)'),
      isTrue,
    );
  });

  test('color picks white in dark mode, zinc900 in light', () {
    // YLColors.primary is pure black — never use it as foreground in
    // dark mode (CLAUDE.md UI/theme rule).
    expect(
      classBody.contains(
        'isDark ? Colors.white : YLColors.zinc900',
      ),
      isTrue,
      reason:
          'Expected the headline foreground to be (isDark ? Colors.white '
          ': YLColors.zinc900) — using YLColors.primary in dark mode '
          'would regress contrast (per CLAUDE.md).',
    );
  });
}
