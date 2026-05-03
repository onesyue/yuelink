import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/widgets/yl_list.dart';
import 'package:yuelink/theme.dart';

void main() {
  Widget harness({required Widget child, double width = 680}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    );
  }

  testWidgets('YLListTile constrains long trailing values', (tester) async {
    const title = 'Startup diagnostics result';
    const trailing =
        'VeryLongTrailingValueThatShouldNotStealTheWholeSettingsRow';

    await tester.pumpWidget(
      harness(
        child: YLListTile(
          title: title,
          subtitle: 'The title and subtitle column should remain readable.',
          trailing: YLListTrailing.label(trailing),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text(title)).width, greaterThan(350));
    expect(tester.getSize(find.text(trailing)).width, lessThanOrEqualTo(260));
  });
}
