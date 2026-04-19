import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yuelink/theme.dart';

// buildTheme() calls GoogleFonts.interTextTheme(). In a test environment
// the font isn't bundled and runtime fetching is disabled, so
// `loadFontIfNecessary`:
//   1. reads AssetManifest.bin (stubbed below to an empty manifest),
//   2. finds no matching asset,
//   3. hits the `!allowRuntimeFetching` branch and *throws* after
//      unconditionally `print`-ing a multi-line diagnostic to stderr,
//   4. the async throw would otherwise fail the test with
//      "This test failed after it had already completed".
//
// `_quietFontZone` wraps the call so that:
//   - the async throw is swallowed via `runZonedGuarded`,
//   - google_fonts' `print` diagnostics are dropped via ZoneSpecification.
//   The AssetManifest stub separately suppresses the earlier
//   "Unable to load asset: AssetManifest.bin" warning.
T _quietFontZone<T>(T Function() body) {
  late T result;
  runZonedGuarded(
    () {
      result = body();
    },
    (_, __) {},
    zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
  );
  return result;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;

    final emptyManifest = const StandardMessageCodec()
        .encodeMessage(<String, Object>{}) as ByteData;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      if (message == null) return null;
      final key = utf8.decode(message.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      if (key == 'AssetManifest.bin') return emptyManifest;
      return null;
    });
  });

  test('buildTheme generates all 6 surface tiers', () {
    final theme = _quietFontZone(() => buildTheme(Brightness.light));
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
    final theme = _quietFontZone(
      () => buildTheme(Brightness.light, accentColor: const Color(0xFFEF4444)),
    );
    expect(theme.colorScheme.primary, isNot(const Color(0xFF000000)));
  });
}
