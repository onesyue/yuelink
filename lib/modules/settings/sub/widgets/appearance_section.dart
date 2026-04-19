import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/settings_service.dart';
import '../../../../i18n/app_strings.dart';
import '../../../../shared/telemetry.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/primitives.dart';
import 'accent_color_row.dart';

/// Appearance section — theme / accent / language.
///
/// Self-contained: reads `themeProvider`, `accentColorProvider`,
/// `languageProvider` via Riverpod; writes back through `SettingsService`
/// and emits `Telemetry.event` for theme changes. No page-level state.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = ref.watch(themeProvider);
    final accentHex = ref.watch(accentColorProvider);
    final language = ref.watch(languageProvider);
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GsGeneralSectionTitle(s.sectionAppearance),
        SettingsCard(
          child: Column(
            children: [
              YLInfoRow(
                label: s.themeLabel,
                trailing: SizedBox(
                  width: 240,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    segments: [
                      ButtonSegment(
                          value: ThemeMode.system, label: Text(s.themeSystem)),
                      ButtonSegment(
                          value: ThemeMode.light, label: Text(s.themeLight)),
                      ButtonSegment(
                          value: ThemeMode.dark, label: Text(s.themeDark)),
                    ],
                    selected: {theme},
                    onSelectionChanged: (v) {
                      ref.read(themeProvider.notifier).state = v.first;
                      SettingsService.setThemeMode(v.first);
                      Telemetry.event(
                        TelemetryEvents.themeChange,
                        props: {'mode': v.first.name},
                      );
                    },
                  ),
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: dividerColor),
              AccentColorRow(
                currentHex: accentHex,
                onChanged: (hex) {
                  ref.read(accentColorProvider.notifier).state = hex;
                  SettingsService.setAccentColor(hex);
                },
                isEn: isEn,
              ),
              Divider(height: 1, thickness: 0.5, color: dividerColor),
              YLInfoRow(
                label: s.sectionLanguage,
                trailing: SizedBox(
                  width: 160,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    segments: [
                      ButtonSegment(
                          value: 'zh', label: Text(s.languageChinese)),
                      ButtonSegment(
                          value: 'en', label: Text(s.languageEnglish)),
                    ],
                    selected: {language},
                    onSelectionChanged: (v) async {
                      ref.read(languageProvider.notifier).state = v.first;
                      await SettingsService.setLanguage(v.first);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
