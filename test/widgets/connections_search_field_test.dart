// Regression guard for P4-B: after scoping filteredConnectionsProvider into
// a local Consumer, the parent page no longer rebuilds on every 500 ms tick.
// The search field's `suffixIcon` visibility used to piggy-back on that
// implicit rebuild — without the ListenableBuilder wrapper it gets stuck
// in its previous state. These three cases lock that down.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/connections/connections_page.dart'
    show ConnectionsSearchField;

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

void main() {
  group('ConnectionsSearchField', () {
    testWidgets('starts with no clear button when controller is empty',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(ConnectionsSearchField(
        controller: controller,
        hintText: 'Search',
        onClear: () {},
      )));

      expect(find.byIcon(Icons.cancel_rounded), findsNothing);
    });

    testWidgets('clear button appears once text is entered', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(ConnectionsSearchField(
        controller: controller,
        hintText: 'Search',
        onClear: () {},
      )));

      await tester.enterText(find.byType(TextField), 'google');
      await tester.pump();

      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
      expect(controller.text, 'google');
    });

    testWidgets('tapping clear empties controller, hides button, '
        'and fires onClear', (tester) async {
      final controller = TextEditingController(text: 'seed');
      addTearDown(controller.dispose);
      var onClearCalls = 0;

      await tester.pumpWidget(_wrap(ConnectionsSearchField(
        controller: controller,
        hintText: 'Search',
        onClear: () => onClearCalls++,
      )));

      // Sanity — with seeded text, the clear button must already be visible.
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.cancel_rounded));
      await tester.pump();

      expect(find.byIcon(Icons.cancel_rounded), findsNothing,
          reason: 'clear button should disappear when text becomes empty');
      expect(controller.text, isEmpty);
      expect(onClearCalls, 1);
    });
  });
}
