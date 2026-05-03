import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/providers/core_provider.dart';
import 'package:yuelink/i18n/strings_g.dart';
import 'package:yuelink/modules/settings/connection_repair/widgets/desktop_tun_layered_status.dart';
import 'package:yuelink/modules/settings/connection_repair/widgets/ios_tun_layered_status.dart';
import 'package:yuelink/modules/settings/connection_repair/widgets/network_diagnostics.dart';
import 'package:yuelink/modules/settings/connection_repair/widgets/status_tile.dart';
import 'package:yuelink/theme.dart';

Widget _harness(Widget child) {
  LocaleSettings.setLocaleSync(AppLocale.zhCn);
  return ProviderScope(
    overrides: [
      connectionModeProvider.overrideWith(
        () => ConnectionModeNotifier('systemProxy'),
      ),
    ],
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
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('StatusTile renders idle state', (tester) async {
    await tester.pumpWidget(_harness(const StatusTile()));

    expect(find.text('未连接'), findsOneWidget);
  });

  testWidgets('DesktopTunLayeredStatus renders system-proxy state', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const DesktopTunLayeredStatus()));

    expect(find.text('当前模式'), findsOneWidget);
    expect(find.text('系统代理 · TUN 未开启'), findsOneWidget);
  });

  testWidgets('IosTunLayeredStatus renders system-proxy state', (tester) async {
    await tester.pumpWidget(_harness(const IosTunLayeredStatus()));

    expect(find.text('当前模式'), findsOneWidget);
    expect(find.text('系统代理 · TUN 未开启'), findsOneWidget);
  });

  testWidgets('NetworkDiagnostics renders idle rows without running probes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const NetworkDiagnostics(header: 'DIAG', isDark: false)),
    );

    expect(find.text('DIAG'), findsOneWidget);
    expect(find.text('开始检测'), findsOneWidget);
    expect(find.text('等待检测'), findsWidgets);
  });
}
