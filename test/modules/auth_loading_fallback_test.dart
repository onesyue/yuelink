import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/yue_auth/presentation/auth_loading_fallback.dart';

/// Lock the contract that `_AuthGate`'s `AuthStatus.unknown` branch
/// no longer renders an empty component (v1.0.22 P0-4c). Pre-fix this
/// branch returned `SizedBox.shrink()` and produced a blank window
/// during slow-Keychain cold starts; the regression guard here just
/// asserts a real visible widget materialises.

void main() {
  testWidgets('renders a non-empty loading view (not SizedBox.shrink)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthLoadingFallback()));

    // The Scaffold + Center + CircularProgressIndicator triplet is the
    // entire surface area — assert all three so a future tweak that
    // accidentally drops the loader (back to a blank widget) trips
    // a test rather than re-introducing the white-screen UX.
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(Center), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Belt and suspenders: the rendered widget must take up real
    // pixels, not the zero-size SizedBox.shrink the previous code
    // path returned.
    final size = tester.getSize(find.byType(AuthLoadingFallback));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
  });
}
