// ignore_for_file: prefer_const_constructors

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/providers/core_provider.dart';
import 'package:yuelink/core/service/service_mode_provider.dart';
import 'package:yuelink/core/service/service_models.dart';
import 'package:yuelink/core/storage/settings_service.dart';
import 'package:yuelink/i18n/strings_g.dart';
import 'package:yuelink/modules/settings/providers/settings_providers.dart';
import 'package:yuelink/modules/settings/sub/general_settings_page.dart';
import 'package:yuelink/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync(
      'yuelink_settings_real_snapshot_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory' ||
                call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  setUp(SettingsService.invalidateCache);

  const enabled = bool.fromEnvironment('YUELINK_SETTINGS_SCREENSHOTS');
  if (!enabled) {
    testWidgets('real settings screenshot matrix disabled', (_) async {});
    return;
  }

  const sizes = {
    'iphone_se': Size(320, 568),
    'narrow_360x800': Size(360, 800),
    'tablet_768x1024': Size(768, 1024),
    'desktop_1440x900': Size(1440, 900),
  };
  const scales = [1.0, 1.3, 1.6];
  const brightnesses = {'light': Brightness.light, 'dark': Brightness.dark};
  const locales = {'zh': AppLocale.zhCn, 'en': AppLocale.en};
  const captures = {'top': 0.0, 'connection': 420.0, 'startup': 900.0};

  for (final locale in locales.entries) {
    for (final size in sizes.entries) {
      for (final scale in scales) {
        for (final theme in brightnesses.entries) {
          for (final capture in captures.entries) {
            testWidgets('real settings ${locale.key} ${capture.key} '
                '${size.key} ${theme.key} scale $scale', (tester) async {
              final outDir = Directory('/tmp/yuelink-settings-real-screens')
                ..createSync(recursive: true);
              final key = GlobalKey();
              tester.view.physicalSize = size.value;
              tester.view.devicePixelRatio = 1;
              addTearDown(() {
                tester.view.resetPhysicalSize();
                tester.view.resetDevicePixelRatio();
              });

              await tester.pumpWidget(
                RepaintBoundary(
                  key: key,
                  child: _SettingsHarness(
                    locale: locale.value,
                    brightness: theme.value,
                    textScale: scale,
                  ),
                ),
              );
              await tester.pumpAndSettle(const Duration(milliseconds: 50));

              if (capture.value > 0) {
                await tester.drag(
                  find.byType(Scrollable).first,
                  Offset(0, -capture.value),
                );
                await tester.pumpAndSettle(const Duration(milliseconds: 50));
              }

              expect(tester.takeException(), isNull);

              await tester.runAsync(() async {
                final boundary =
                    key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  '${outDir.path}/settings_real_${locale.key}_'
                  '${capture.key}_${size.key}_${theme.key}_'
                  'scale_${scale.toStringAsFixed(1)}.png',
                );
                file.writeAsBytesSync(bytes!.buffer.asUint8List());
                image.dispose();
              });
            });
          }
        }
      }
    }
  }
}

class _SettingsHarness extends StatelessWidget {
  const _SettingsHarness({
    required this.locale,
    required this.brightness,
    required this.textScale,
  });

  final AppLocale locale;
  final Brightness brightness;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    LocaleSettings.setLocaleSync(locale);
    final language = locale == AppLocale.en ? 'en' : 'zh';
    return ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) => ThemeMode.system),
        languageProvider.overrideWith((ref) => language),
        routingModeProvider.overrideWith((ref) => 'rule'),
        connectionModeProvider.overrideWith((ref) => 'tun'),
        desktopTunStackProvider.overrideWith((ref) => 'mixed'),
        closeBehaviorProvider.overrideWith((ref) => 'tray'),
        systemProxyOnConnectProvider.overrideWith((ref) => true),
        autoConnectProvider.overrideWith((ref) => false),
        subSyncIntervalProvider.overrideWith((ref) => 24),
        quicPolicyProvider.overrideWith(
          (ref) => SettingsService.quicPolicyGooglevideo,
        ),
        desktopServiceInfoProvider.overrideWith(
          (ref) async => const DesktopServiceInfo(
            installed: true,
            reachable: true,
            mihomoRunning: false,
            serviceVersion: 'test',
          ),
        ),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale.flutterLocale,
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(brightness),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const GeneralSettingsPage(),
          ),
        ),
      ),
    );
  }
}
