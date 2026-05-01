// Regression guard for the price row inside PlanCard.
//
// The store list lives or dies on this layout: price text on the left and
// the FilledButton ("续订" / "立即订阅") aligned to the right edge of the card
// content area. Several recent visual sweeps touched this file, so we lock
// down the rendered geometry instead of a fragile Row child order.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/store/store_plan.dart';
import 'package:yuelink/i18n/strings_g.dart';
import 'package:yuelink/modules/store/widgets/plan_card.dart';
import 'package:yuelink/theme.dart';

const _plan = StorePlan(
  id: 99,
  name: 'Test Plan',
  transferEnable: 100,
  speedLimit: 1000,
  deviceLimit: 3,
  monthPrice: 1800, // ¥18.00
  yearPrice: 18000, // ¥180.00
);

Widget _harness({required bool isCurrentPlan}) {
  // Lock to zh so we can assert on the exact button label.
  LocaleSettings.setLocaleSync(AppLocale.zhCn);
  return ProviderScope(
    child: TranslationProvider(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: AppLocale.zhCn.flutterLocale,
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PlanCard(plan: _plan, isCurrentPlan: isCurrentPlan),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('price row right-aligns the subscribe button', (tester) async {
    await tester.pumpWidget(_harness(isCurrentPlan: false));
    await tester.pump();

    // The price row contains the cheapest period's formatted price first.
    expect(find.text('¥18'), findsOneWidget);

    // ── Subscribe button is rendered with the zh label. ───────────────────
    final buttonFinder = find.widgetWithText(FilledButton, '立即订阅');
    expect(buttonFinder, findsOneWidget);

    final cardRect = tester.getRect(find.byType(PlanCard));
    final buttonRect = tester.getRect(buttonFinder);
    final priceRect = tester.getRect(find.text('¥18'));

    expect(
      buttonRect.right,
      closeTo(cardRect.right - YLSpacing.md, 1),
      reason:
          'The subscribe button should sit on the right edge of the card '
          'content area, leaving only the PlanCard inner padding.',
    );
    expect(
      priceRect.left,
      closeTo(cardRect.left + YLSpacing.md, 1),
      reason:
          'The price should remain anchored to the left edge of the card '
          'content area.',
    );
    expect(
      buttonRect.left,
      greaterThan(priceRect.right),
      reason: 'Price and subscribe button should not overlap.',
    );
  });

  testWidgets('renew label appears for the current plan', (tester) async {
    await tester.pumpWidget(_harness(isCurrentPlan: true));
    await tester.pump();

    expect(find.widgetWithText(FilledButton, '续订'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '立即订阅'), findsNothing);

    // Current-plan badge.
    expect(find.text('当前'), findsOneWidget);
  });
}
