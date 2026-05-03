import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/settings/widgets/primitives.dart';
import 'package:yuelink/theme.dart';

void main() {
  Widget harness({
    required Widget child,
    double width = 220,
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('adaptive segmented control keeps Chinese labels single line', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        textScale: 1.6,
        child: YLAdaptiveSegmentedControl<String>(
          selectedValue: 'system',
          segments: const [
            YLAdaptiveSegment(value: 'system', label: '跟随系统'),
            YLAdaptiveSegment(value: 'light', label: '浅色'),
            YLAdaptiveSegment(value: 'dark', label: '深色'),
          ],
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final systemText = tester.widget<Text>(find.text('跟随系统'));
    expect(systemText.maxLines, 1);
    expect(systemText.softWrap, isFalse);
    expect(systemText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('settings row stacks complex trailing control on narrow width', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        width: 250,
        brightness: Brightness.dark,
        textScale: 1.6,
        child: YLInfoRow(
          label: '窗口关闭行为',
          trailing: YLAdaptiveSegmentedControl<String>(
            selectedValue: 'tray',
            segments: const [
              YLAdaptiveSegment(value: 'tray', label: '最小化到托盘'),
              YLAdaptiveSegment(value: 'exit', label: '退出应用'),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (final label in ['最小化到托盘', '退出应用']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
    }
  });

  testWidgets('settings row keeps simple trailing controls content-sized', (
    tester,
  ) async {
    const title =
        'VeryLongPreferenceTitleWithoutSpacesThatShouldUseTheAvailableWidth';

    await tester.pumpWidget(
      harness(
        width: 680,
        child: const YLSettingsRow(
          title: title,
          description: '这行应该把大部分宽度留给左侧说明，而不是让右侧开关占半屏。',
          trailing: SizedBox(width: 44, height: 28),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text(title)).width, greaterThan(520));
  });

  testWidgets('info row keeps expanded dropdown in a compact trailing lane', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        width: 680,
        child: YLInfoRow(
          label: '订阅更新频率',
          trailing: DropdownButton<int>(
            value: 24,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 1, child: Text('每小时')),
              DropdownMenuItem(value: 24, child: Text('每天')),
              DropdownMenuItem(value: 48, child: Text('每2天')),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final dropdownWidth = tester
        .getSize(find.byType(DropdownButton<int>))
        .width;
    expect(dropdownWidth, inInclusiveRange(144, 208));
  });

  testWidgets('adaptive segmented control handles English without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        width: 260,
        textScale: 1.3,
        child: YLAdaptiveSegmentedControl<String>(
          selectedValue: 'system',
          segments: const [
            YLAdaptiveSegment(value: 'system', label: 'Follow System'),
            YLAdaptiveSegment(value: 'light', label: 'Light'),
            YLAdaptiveSegment(value: 'dark', label: 'Dark'),
          ],
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text('Follow System')).maxLines, 1);
  });

  testWidgets('targeted zh/en setting labels stay single-line', (tester) async {
    const labels = [
      '跟随系统',
      '最小化到托盘',
      '路由模式',
      '自动',
      '系统',
      'Light',
      'Dark',
      'Auto',
      'Follow System',
      'Minimize to Tray',
    ];

    await tester.pumpWidget(
      harness(
        width: 260,
        textScale: 1.6,
        child: YLAdaptiveSegmentedControl<String>(
          selectedValue: labels.first,
          segments: [
            for (final label in labels)
              YLAdaptiveSegment(value: label, label: label),
          ],
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (final label in labels) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.maxLines, 1, reason: label);
      expect(text.softWrap, isFalse, reason: label);
      expect(text.overflow, TextOverflow.ellipsis, reason: label);
    }
  });
}
