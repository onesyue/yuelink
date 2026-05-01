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
        YLSpacing.md,
        YLSpacing.lg,
        YLSpacing.md,
        YLSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
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
        YLSpacing.md,
        YLSpacing.md,
        YLSpacing.md,
        YLSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(YLRadius.lg),
      child: DecoratedBox(
        decoration: YLGlass.surfaceDecoration(context, elevated: false),
        child: child,
      ),
    );
  }
}

/// A single settings row with a label on the left and a value or
/// trailing widget on the right. Visual anatomy matches `YLListTile`
/// (16dp horizontal padding, 8-12dp vertical, 14pt title) so old and new
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
        horizontal: YLSpacing.lg,
        vertical: YLSpacing.md,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: YLSpacing.md),
              ],
              Flexible(
                child: Text(
                  label,
                  style:
                      labelStyle ??
                      YLText.rowTitle.copyWith(
                        fontWeight: FontWeight.w400,
                        color: labelColor,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

          // Narrow rows with adaptive segmented controls should stack instead
          // of squeezing Chinese labels into wrapped text or causing Windows
          // text-overpaint. Simple trailing widgets (switches, chevrons) stay
          // inline so ordinary settings rows keep their familiar shape.
          final shouldStackTrailing =
              trailing is YLAdaptiveSegmentedControl &&
              constraints.maxWidth < 360;
          if (trailing != null && value == null && shouldStackTrailing) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                labelWidget,
                const SizedBox(height: YLSpacing.sm),
                Align(alignment: Alignment.centerRight, child: trailing!),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: labelWidget),
              if (value != null)
                Flexible(
                  fit: FlexFit.loose,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      value!,
                      style: YLText.caption.copyWith(
                        fontSize: 12,
                        color: valueColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
              if (trailing != null)
                Flexible(
                  fit: FlexFit.loose,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailing!,
                  ),
                ),
            ],
          );
        },
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

class YLAdaptiveSegment<T> {
  final T value;
  final String label;

  const YLAdaptiveSegment({required this.value, required this.label});
}

/// Compact segmented control for settings rows.
///
/// Material's `SegmentedButton` distributes fixed row width across every
/// segment; on zh-CN Windows with 1.3x+ text scale that squeezed labels such
/// as "跟随系统" into two lines and sometimes overpainted neighbouring rows.
/// This control is content-sized, keeps every label to one line, and lets the
/// segments wrap as whole pills when the row is genuinely too narrow.
class YLAdaptiveSegmentedControl<T> extends StatelessWidget {
  final List<YLAdaptiveSegment<T>> segments;
  final T selectedValue;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  const YLAdaptiveSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedValue,
    required this.onChanged,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.045);

    return Semantics(
      label: semanticLabel,
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(YLRadius.lg),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 2,
            runSpacing: 2,
            children: [
              for (final segment in segments)
                _YLAdaptiveSegmentButton<T>(
                  segment: segment,
                  selected: segment.value == selectedValue,
                  onTap: () => onChanged(segment.value),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YLAdaptiveSegmentButton<T> extends StatelessWidget {
  final YLAdaptiveSegment<T> segment;
  final bool selected;
  final VoidCallback onTap;

  const _YLAdaptiveSegmentButton({
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected
        ? (isDark ? Colors.white : YLColors.zinc900)
        : (isDark ? YLColors.zinc400 : YLColors.zinc600);
    final selectedBg = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.88);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(YLRadius.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 30, minWidth: 42),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(YLRadius.md),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.16 : 0.08,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            segment.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: YLText.caption.copyWith(
              fontSize: 12,
              height: 1.1,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ),
    );
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
        horizontal: YLSpacing.lg,
        vertical: YLSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: YLText.rowTitle.copyWith(
                    fontWeight: FontWeight.w400,
                    color: titleColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: YLText.rowSubtitle.copyWith(color: descColor),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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
