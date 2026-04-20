import 'package:flutter/material.dart';

import '../../../theme.dart';

/// Settings page primitive widgets.
///
/// Extracted from `settings_page.dart` so the page file can shrink and
/// sub-pages / widget tests can reach them without reaching through the
/// page file. Behaviour, look, and public constructor signatures of
/// `YLInfoRow` / `YLSettingsRow` are preserved verbatim.
///
/// `_SectionTitle` and `_SettingsCard` were renamed to
/// `SettingsSectionTitle` / `SettingsCard` because private-to-library
/// classes can't be imported across files. This is the minimal visibility
/// adjustment called out in the Batch γ spec — no API redesign beyond
/// stripping the leading underscore.

/// Section title — matches the dashboard top bar label style.
class SettingsSectionTitle extends StatelessWidget {
  final String text;
  const SettingsSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: YLColors.zinc500,
          letterSpacing: -0.08,
        ),
      ),
    );
  }
}

/// Narrower section title variant used by the General Settings sub-page.
///
/// Different on purpose from [SettingsSectionTitle]: the sub-page layout
/// is tighter (4 vs 20 horizontal padding), the label runs at 12/w500
/// with positive letterSpacing instead of 13/w400 with negative. Kept as
/// a separate class so sub-page styling can evolve without dragging the
/// dashboard-style title with it.
class GsGeneralSectionTitle extends StatelessWidget {
  final String text;
  const GsGeneralSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          color: YLColors.zinc500,
        ),
      ),
    );
  }
}

/// Card container matching the dashboard card style.
class SettingsCard extends StatelessWidget {
  final Widget child;
  const SettingsCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: child,
    );
  }
}

/// A single settings row with a label on the left and a value or trailing widget on the right.
class YLInfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool enabled;
  final TextStyle? labelStyle;

  const YLInfoRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
    this.leading,
    this.onTap,
    this.enabled = true,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = enabled
        ? (isDark ? YLColors.zinc200 : YLColors.zinc700)
        : YLColors.zinc400;
    final valueColor = enabled
        ? (isDark ? YLColors.zinc400 : YLColors.zinc500)
        : YLColors.zinc300;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(label,
                style: labelStyle ?? YLText.body.copyWith(color: labelColor)),
          ),
          if (value != null)
            Text(value!, style: YLText.body.copyWith(color: valueColor)),
          ?trailing,
        ],
      ),
    );

    if (onTap != null && enabled) {
      return InkWell(onTap: onTap, child: content);
    }
    return Opacity(opacity: enabled ? 1.0 : 0.5, child: content);
  }
}

class YLSettingsRow extends StatelessWidget {
  final String title;
  final String? description;
  final Widget trailing;

  const YLSettingsRow({
    super.key,
    required this.title,
    this.description,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? YLColors.zinc200 : YLColors.zinc700;
    final descColor = isDark ? YLColors.zinc500 : YLColors.zinc400;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: YLText.body.copyWith(color: titleColor)),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description!,
                      style: YLText.caption.copyWith(color: descColor)),
                ],
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
