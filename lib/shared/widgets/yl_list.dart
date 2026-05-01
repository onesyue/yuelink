import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';

/// iOS 26 / Apple Settings-style inset grouped list.
///
/// Use [YLSection] as the outer container for a group of related rows;
/// use [YLListTile] for each row inside. The two are designed as a
/// pair — `YLSection` paints the rounded surface + outer margin and
/// inserts hairline dividers between children, so each [YLListTile]
/// only needs to render its own anatomy (icon + title + trailing).
///
/// ```dart
/// YLSection(
///   header: '订阅',
///   children: [
///     YLListTile(
///       leading: const YLSettingIcon(
///         icon: Icons.cloud_rounded,
///         color: Color(0xFF3B82F6),
///       ),
///       title: '订阅管理',
///       trailing: YLListTrailing.chevron(),
///       onTap: () {...},
///     ),
///     YLListTile(
///       leading: const YLSettingIcon(...),
///       title: '同步订阅',
///       subtitle: '上次同步：5 分钟前',
///       trailing: YLListTrailing.chevron(),
///       onTap: () {...},
///     ),
///   ],
/// )
/// ```

class YLSection extends StatelessWidget {
  /// Optional all-caps small header above the section (iOS standard).
  /// Pass `null` for sections that visually belong to the row group
  /// above (e.g. profile card → first action group).
  final String? header;

  /// Optional caption below the section explaining what the rows
  /// affect. Renders in zinc500 12pt with comfortable line height.
  final String? footer;

  /// Section rows. Almost always [YLListTile], but accepts any widget
  /// — useful for custom row variants (a slider, an inline preview…).
  final List<Widget> children;

  /// Outer left/right margin. Defaults to [YLSpacing.lg] which matches
  /// iOS Settings; pages with their own outer padding can pass 0.
  final double horizontalMargin;

  const YLSection({
    super.key,
    this.header,
    this.footer,
    this.horizontalMargin = YLSpacing.lg,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? YLColors.zinc900 : Colors.white;
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final captionColor = isDark ? YLColors.zinc500 : YLColors.zinc500;

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        // Inset the divider so it starts past the leading icon column —
        // 56dp matches `YLListTile.leading`'s 29dp icon + 12dp spacing
        // + 16dp left padding. iOS divides between text columns, not
        // edge-to-edge.
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Container(height: 0.33, color: divider),
          ),
        );
      }
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                YLSpacing.md,
                YLSpacing.lg,
                YLSpacing.md,
                YLSpacing.sm,
              ),
              child: Text(
                header!.toUpperCase(),
                style: YLText.caption.copyWith(
                  color: captionColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(YLRadius.lg),
            child: Container(
              color: surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                YLSpacing.md,
                YLSpacing.sm,
                YLSpacing.md,
                YLSpacing.lg,
              ),
              child: Text(
                footer!,
                style: YLText.caption.copyWith(
                  color: captionColor,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Standard iOS Settings list row.
///
/// Anatomy (left → right):
///   * [leading]  — usually a `YLSettingIcon` colored squircle, but
///                  any widget works (avatar, status dot, etc.).
///   * Title block — required [title]; optional [subtitle] one line
///                  below in zinc500.
///   * [trailing] — chevron / value+chevron / switch / activity dot
///                  / nothing. Use the [YLListTrailing] factories so
///                  every row is sized + spaced identically.
class YLListTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool dense;

  const YLListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = destructive
        ? YLColors.error
        : (isDark ? Colors.white : YLColors.zinc900);
    final subtitleColor = isDark ? YLColors.zinc500 : YLColors.zinc500;
    final disabled = onTap == null;

    final titleStyle = YLText.rowTitle.copyWith(
      fontWeight: FontWeight.w400,
      color: titleColor,
    );
    final subtitleStyle = YLText.rowSubtitle.copyWith(color: subtitleColor);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: YLSpacing.lg,
            vertical: dense ? YLSpacing.sm : YLSpacing.md,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                Opacity(opacity: disabled ? 0.4 : 1.0, child: leading!),
                const SizedBox(width: YLSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: disabled ? 0.4 : 1.0,
                      child: Text(
                        title,
                        style: titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Opacity(
                        opacity: disabled ? 0.4 : 1.0,
                        child: Text(
                          subtitle!,
                          style: subtitleStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: YLSpacing.md),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pre-built trailing widgets for [YLListTile]. Sized + coloured so
/// rows align across a section regardless of which variant they use.
class YLListTrailing {
  YLListTrailing._();

  /// Apple Settings-style chevron — used for any row that pushes a
  /// detail page on tap.
  static Widget chevron() => const _Chevron();

  /// Value text on the right + chevron — for rows that show the
  /// current setting summary (e.g. "中文 ›"). Value is muted; the
  /// row's title remains the primary text.
  static Widget value(String text) => _ValueAndChevron(text: text);

  /// Trailing switch.
  static Widget toggle({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => _CompactSwitch(value: value, onChanged: onChanged);

  /// Plain right-aligned label with no chevron — for read-only rows
  /// (version number, build hash, etc).
  static Widget label(String text) => _ValueLabel(text: text);

  /// Activity indicator (CupertinoActivityIndicator) — for rows
  /// performing async work (e.g. "正在同步…").
  static Widget loading() => const SizedBox(
    width: 18,
    height: 18,
    child: CupertinoActivityIndicator(radius: 8),
  );

  /// Status badge — colored pill with short label. Variant for
  /// "已连接 / 未连接 / 已过期" indicators.
  static Widget badge({required String text, required Color color}) =>
      _StatusBadge(text: text, color: color);
}

class _Chevron extends StatelessWidget {
  const _Chevron();
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Icon(
      Icons.chevron_right_rounded,
      size: 18,
      color: isDark ? YLColors.zinc600 : YLColors.zinc400,
    );
  }
}

class _ValueAndChevron extends StatelessWidget {
  final String text;
  const _ValueAndChevron({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: YLText.body.copyWith(
              fontSize: 13,
              color: isDark ? YLColors.zinc400 : YLColors.zinc500,
            ),
          ),
        ),
        const SizedBox(width: 6),
        const _Chevron(),
      ],
    );
  }
}

class _ValueLabel extends StatelessWidget {
  final String text;
  const _ValueLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: YLText.body.copyWith(
        fontSize: 13,
        color: isDark ? YLColors.zinc400 : YLColors.zinc500,
      ),
    );
  }
}

class _CompactSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _CompactSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.85,
      child: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: YLColors.connected,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(YLRadius.pill),
      ),
      child: Text(
        text,
        style: YLText.caption.copyWith(
          color: color,
          fontSize: YLText.badge.fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
