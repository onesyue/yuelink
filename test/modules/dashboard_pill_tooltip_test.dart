import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/dashboard/widgets/hero_card.dart';

/// Lock the v1.0.22 P2-1 contract: when a `Pill` is tappable AND a
/// tooltip is supplied, the tooltip wrapper is attached so hover
/// (desktop) and long-press (mobile) surface the hint without
/// requiring dedicated onboarding UI. Decorative pills (no `onTap`)
/// or tappable pills without a hint stay un-tooltipped.

void main() {
  group('Pill tooltip', () {
    testWidgets('tappable + tooltip → Tooltip wrapper present', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Pill(
              'Rule',
              primary: true,
              onTap: () {},
              tooltip: 'Tap to switch routing mode',
            ),
          ),
        ),
      );
      final tip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tip.message, 'Tap to switch routing mode');
    });

    testWidgets('tappable but no tooltip → no Tooltip wrapper', (tester) async {
      // Verifies the additive contract: existing call sites that
      // didn't pass a tooltip get the same widget tree as before.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Pill('Rule', primary: true, onTap: () {})),
        ),
      );
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets(
      'decorative pill (no onTap) + tooltip provided → no Tooltip',
      (tester) async {
        // Tooltip is intentionally only attached when the pill is
        // actually tappable — otherwise we'd be hinting at an
        // affordance that doesn't exist.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Pill('Profile', tooltip: 'Tap to switch'),
            ),
          ),
        );
        expect(find.byType(Tooltip), findsNothing);
      },
    );

    testWidgets('shows tooltip text on long press (mobile gesture)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Pill(
                'Rule',
                primary: true,
                onTap: () {},
                tooltip: 'Tap to switch routing mode',
              ),
            ),
          ),
        ),
      );

      // Trigger the platform-default long-press to surface the
      // tooltip overlay. Same gesture used by Material's stock
      // tooltip integration tests.
      final gesture = await tester.createGesture();
      await gesture.addPointer(location: tester.getCenter(find.byType(Pill)));
      await gesture.down(tester.getCenter(find.byType(Pill)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Tap to switch routing mode'), findsOneWidget);

      await gesture.up();
      await gesture.removePointer();
    });
  });
}
