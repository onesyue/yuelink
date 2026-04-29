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

/// Section title — paints the all-caps label that introduces a
/// `SettingsCard` group. Matches `YLSection.header` so old call sites
/// (settings sub-pages still using SettingsCard) line up visually with
/// new ones using YLSection.
class SettingsSectionTitle extends StatelessWidget {
  final String text;
  const SettingsSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          YLSpacing.md, YLSpacing.lg, YLSpacing.md, YLSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.6,
          color: YLColors.zinc500,
        ),
      ),
    );
  }
}

/// Sub-page section title — same visual as [SettingsSectionTitle] but
/// with tighter horizontal padding, used inside `GeneralSettingsPage` /
/// `OverwritePage` etc. where the page already has its own outer
/// padding. Kept as a separate class so sub-page padding can drift
/// without dragging the main settings title with it.
class GsGeneralSectionTitle extends StatelessWidget {
  final String text;
  const GsGeneralSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          YLSpacing.md, YLSpacing.md, YLSpacing.md, YLSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.6,
          color: YLColors.zinc500,
        ),
      ),
    );
  }
}

/// iOS 26 inset-grouped card container — rounded surface, no border,
/// no shadow. Visually identical to `YLSection` so old call sites
/// (sub-pages still using `SettingsCard`) and new ones using
/// `YLSection` blend without seams.
class SettingsCard extends StatelessWidget {
  final Widget child;
  const SettingsCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(YLRadius.lg),
      child: Container(
        color: isDark ? YLColors.zinc900 : Colors.white,
        child: child,
      ),
    );
  }
}

/// A single settings row with a label on the left and a value or
/// trailing widget on the right. Visual anatomy matches `YLListTile`
/// (16dp horizontal padding, 12dp vertical, 16pt title) so old and new
/// rows line up when mixed inside the same section.
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
        ? (isDark ? Colors.white : YLColors.zinc900)
        : YLColors.zinc400;
    final valueColor = enabled
        ? (isDark ? YLColors.zinc400 : YLColors.zinc500)
        : YLColors.zinc300;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: YLSpacing.lg, vertical: YLSpacing.md),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: YLSpacing.md),
          ],
          Expanded(
            child: Text(
              label,
              style: labelStyle ??
                  YLText.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.1,
                    color: labelColor,
                  ),
            ),
          ),
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                value!,
                style: YLText.body.copyWith(fontSize: 13, color: valueColor),
              ),
            ),
          ?trailing,
        ],
      ),
    );

    if (onTap != null && enabled) {
      return Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: content),
      );
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
    final titleColor = isDark ? Colors.white : YLColors.zinc900;
    final descColor = isDark ? YLColors.zinc500 : YLColors.zinc500;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: YLSpacing.lg, vertical: YLSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: YLText.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.1,
                    color: titleColor,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: YLText.caption.copyWith(
                      fontSize: 12,
                      color: descColor,
                      height: 1.3,
                    ),
                  ),
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
