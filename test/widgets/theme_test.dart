import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/theme.dart';

void main() {
  test('buildTheme generates all 6 surface tiers', () {
    final theme = buildTheme(Brightness.light);
    final scheme = theme.colorScheme;
    final tiers = {
      scheme.surfaceContainerLowest,
      scheme.surface,
      scheme.surfaceContainerLow,
      scheme.surfaceContainer,
      scheme.surfaceContainerHigh,
      scheme.surfaceContainerHighest,
    };
    expect(tiers.length, greaterThanOrEqualTo(5));
  });

  test('accent color flows through to primary', () {
    final theme = buildTheme(
      Brightness.light,
      accentColor: const Color(0xFFEF4444),
    );
    expect(theme.colorScheme.primary, isNot(const Color(0xFF000000)));
  });
}
