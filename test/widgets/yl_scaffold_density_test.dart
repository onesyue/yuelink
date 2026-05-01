import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/widgets/yl_scaffold.dart';
import 'package:yuelink/theme.dart';

void main() {
  testWidgets('secondary pages default to a single compact title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const YLLargeTitleScaffold(
          title: '订单记录',
          slivers: [SliverToBoxAdapter(child: SizedBox(height: 200))],
        ),
      ),
    );

    final titleSizes = tester
        .widgetList<Text>(find.text('订单记录'))
        .map((text) => text.style?.fontSize)
        .whereType<double>()
        .toSet();

    expect(titleSizes, equals({17}));
    expect(titleSizes, isNot(contains(32)));
    expect(find.text('订单记录'), findsOneWidget);
  });

  testWidgets('large title mode is explicit opt-in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const YLLargeTitleScaffold(
          title: '首页',
          titleMode: YLTitleMode.large,
          slivers: [SliverToBoxAdapter(child: SizedBox(height: 200))],
        ),
      ),
    );

    final titleSizes = tester
        .widgetList<Text>(find.text('首页'))
        .map((text) => text.style?.fontSize)
        .whereType<double>()
        .toSet();

    expect(titleSizes, contains(17));
    expect(titleSizes, contains(30));
    expect(titleSizes, isNot(contains(32)));
  });

  testWidgets('compact title survives viewport, scale and theme matrix', (
    tester,
  ) async {
    const sizes = [
      Size(320, 568), // iPhone SE
      Size(360, 800),
      Size(768, 1024), // tablet
      Size(1440, 900), // desktop
    ];
    const scales = [1.0, 1.3, 1.6];
    const brightnesses = [Brightness.light, Brightness.dark];

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final size in sizes) {
      for (final scale in scales) {
        for (final brightness in brightnesses) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;

          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(brightness),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: const YLLargeTitleScaffold(
                  title: '非常长的订阅套餐订单记录标题',
                  slivers: [SliverToBoxAdapter(child: SizedBox(height: 200))],
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
          final titleTexts = tester.widgetList<Text>(
            find.text('非常长的订阅套餐订单记录标题'),
          );
          expect(
            titleTexts.every((text) => text.overflow == TextOverflow.ellipsis),
            isTrue,
            reason: 'size=$size scale=$scale brightness=$brightness',
          );
        }
      }
    }
  });
}
