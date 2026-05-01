import 'package:flutter/cupertino.dart' show CupertinoTabBar;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/app/main_shell.dart';
import 'package:yuelink/theme.dart';

void main() {
  testWidgets('glass bottom nav is lightweight and exposes four tabs', (
    tester,
  ) async {
    var tapped = -1;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: YLGlassBottomNav(
            key: const ValueKey('main_glass_bottom_nav'),
            currentIndex: 1,
            items: const [
              YLGlassTabSpec(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: '首页',
              ),
              YLGlassTabSpec(
                icon: Icons.public_outlined,
                activeIcon: Icons.public,
                label: '线路',
              ),
              YLGlassTabSpec(
                icon: Icons.play_circle_outline,
                activeIcon: Icons.play_circle_filled,
                label: '悦视频',
              ),
              YLGlassTabSpec(
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: '我的',
              ),
            ],
            onSelect: (index) => tapped = index,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('main_glass_bottom_nav')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('main_glass_nav_indicator')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(CupertinoTabBar), findsNothing);

    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('main_glass_nav_item_$i')), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('main_glass_nav_item_2')));
    expect(tapped, 2);
  });
}
