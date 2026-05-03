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
                trailing: YLAdaptiveSegmentedControl<ThemeMode>(
                  semanticLabel: s.themeLabel,
                  selectedValue: theme,
                  segments: [
                    YLAdaptiveSegment(
                      value: ThemeMode.system,
                      label: s.themeSystem,
                    ),
                    YLAdaptiveSegment(
                      value: ThemeMode.light,
                      label: s.themeLight,
                    ),
                    YLAdaptiveSegment(
                      value: ThemeMode.dark,
                      label: s.themeDark,
                    ),
                  ],
                  onChanged: (mode) {
                    ref.read(themeProvider.notifier).set(mode);
                    SettingsService.setThemeMode(mode);
                    Telemetry.event(
                      TelemetryEvents.themeChange,
                      props: {'mode': mode.name},
                    );
                  },
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: dividerColor),
              AccentColorRow(
                currentHex: accentHex,
                onChanged: (hex) {
                  ref.read(accentColorProvider.notifier).set(hex);
                  SettingsService.setAccentColor(hex);
                },
                isEn: isEn,
              ),
              Divider(height: 1, thickness: 0.5, color: dividerColor),
              YLInfoRow(
                label: s.sectionLanguage,
                trailing: YLAdaptiveSegmentedControl<String>(
                  semanticLabel: s.sectionLanguage,
                  selectedValue: language,
                  segments: [
                    YLAdaptiveSegment(value: 'zh', label: s.languageChinese),
                    YLAdaptiveSegment(value: 'en', label: s.languageEnglish),
                  ],
                  onChanged: (value) async {
                    ref.read(languageProvider.notifier).set(value);
                    await SettingsService.setLanguage(value);
                  },
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
