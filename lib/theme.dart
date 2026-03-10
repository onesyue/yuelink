import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════════════════════
// YueLink Design System — Premium Apple/Linear aesthetic
// ══════════════════════════════════════════════════════════════════════════════

class YLColors {
  YLColors._();

  // ── Backgrounds ──────────────────────────────────────────────────────────
  static const bgLight  = Color(0xFFF5F5F7); // Apple light gray
  static const bgDark   = Color(0xFF000000); // Pure OLED black

  // ── Surfaces (Cards) ─────────────────────────────────────────────────────
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark  = Color(0xFF1C1C1E); // Apple dark card

  // ── Neutrals (Zinc scale) ────────────────────────────────────────────────
  static const zinc50  = Color(0xFFFAFAFA);
  static const zinc100 = Color(0xFFF4F4F5);
  static const zinc200 = Color(0xFFE4E4E7);
  static const zinc300 = Color(0xFFD4D4D8);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc500 = Color(0xFF71717A);
  static const zinc600 = Color(0xFF52525B);
  static const zinc700 = Color(0xFF3F3F46);
  static const zinc800 = Color(0xFF27272A);
  static const zinc900 = Color(0xFF18181B);
  static const zinc950 = Color(0xFF09090B);

  // ── Brand ────────────────────────────────────────────────────────────────
  static const primary      = Color(0xFF007AFF); // Apple Blue
  static const primaryLight = Color(0xFFEBF5FF);

  // ── Status (Apple HIG) ───────────────────────────────────────────────────
  static const connected    = Color(0xFF34C759); // Apple Green
  static const connecting   = Color(0xFFFF9F0A); // Apple Orange
  static const error        = Color(0xFFFF3B30); // Apple Red
  static const errorLight   = Color(0xFFFEF2F2);
}

// ── Typography ──────────────────────────────────────────────────────────────

class YLText {
  YLText._();

  static const display = TextStyle(
      fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1.0,
      height: 1.15, fontFeatures: [FontFeature.tabularFigures()]);

  static const titleLarge = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.25);

  static const titleMedium = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3, height: 1.3);

  static const body = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: -0.2, height: 1.4);

  static const label = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0);

  static const caption = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.1);

  static const mono = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w500,
      fontFamily: 'Menlo',
      fontFeatures: [FontFeature.tabularFigures()]);
}

// ── Spacing ─────────────────────────────────────────────────────────────────

class YLSpacing {
  YLSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const massive = 32.0;
}

class YLRadius {
  YLRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const pill = 999.0;
}

// ── Theme Factory ───────────────────────────────────────────────────────────

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: isDark ? YLColors.bgDark : YLColors.bgLight,
    primaryColor: YLColors.primary,
    colorScheme: ColorScheme.fromSeed(
      seedColor: YLColors.primary,
      brightness: brightness,
      surface: isDark ? YLColors.surfaceDark : YLColors.surfaceLight,
    ),
    splashFactory: InkSparkle.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: isDark
        ? Colors.white.withOpacity(0.04)
        : Colors.black.withOpacity(0.02),
    fontFamily: '.SF Pro Text',
    dividerTheme: DividerThemeData(
      space: 1,
      thickness: 0.5,
      color: isDark
          ? Colors.white.withOpacity(0.08)
          : Colors.black.withOpacity(0.06),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: YLText.titleLarge.copyWith(
        color: isDark ? Colors.white : Colors.black,
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Reusable UI Components
// ══════════════════════════════════════════════════════════════════════════════

/// A polished card surface with subtle border and shadow.
class YLSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double borderRadius;

  const YLSurface({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderRadius = YLRadius.xl,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? YLColors.surfaceDark : YLColors.surfaceLight,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.04),
          width: 0.5,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Glassmorphism surface.
class YLGlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double blurSigma;
  final double borderRadius;
  final Color? customColor;

  const YLGlassSurface({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.blurSigma = 20,
    this.borderRadius = YLRadius.xl,
    this.customColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: customColor ??
                  (isDark
                      ? Colors.white.withOpacity(0.04)
                      : Colors.white.withOpacity(0.7)),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.white.withOpacity(0.4),
                width: 0.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// iOS-style grouped list item.
class YLGroupedListItem extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isFirst;
  final bool isLast;

  const YLGroupedListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? YLColors.surfaceDark : YLColors.surfaceLight,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(YLRadius.lg) : Radius.zero,
        bottom: isLast ? const Radius.circular(YLRadius.lg) : Radius.zero,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(YLRadius.lg) : Radius.zero,
          bottom: isLast ? const Radius.circular(YLRadius.lg) : Radius.zero,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: YLSpacing.lg, vertical: YLSpacing.md),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.05),
                      width: 0.5,
                    ),
                  ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(
                      style: YLText.body.copyWith(
                          color: isDark ? Colors.white : Colors.black),
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle(
                        style: YLText.caption.copyWith(color: YLColors.zinc500),
                        child: subtitle!,
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

/// Pill-shaped segmented control (Apple-style).
class YLPillSegmentedControl<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T selectedValue;
  final ValueChanged<T> onChanged;

  const YLPillSegmentedControl({
    super.key,
    required this.values,
    required this.labels,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.08)
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(YLRadius.pill),
      ),
      child: Row(
        children: List.generate(values.length, (index) {
          final isSelected = values[index] == selectedValue;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(values[index]),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark
                          ? YLColors.surfaceDark
                          : YLColors.surfaceLight)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(YLRadius.pill),
                  boxShadow: isSelected && !isDark
                      ? [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ]
                      : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[index],
                  style: YLText.label.copyWith(
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? (isDark ? Colors.white : Colors.black)
                        : YLColors.zinc500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Status indicator dot with optional glow.
class YLStatusDot extends StatelessWidget {
  final Color color;
  final double size;
  final bool glow;

  const YLStatusDot(
      {super.key, required this.color, this.size = 8, this.glow = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: glow
            ? [
                BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2)
              ]
            : null,
      ),
    );
  }
}

/// Section label (e.g. "GENERAL").
class YLSectionLabel extends StatelessWidget {
  final String text;
  const YLSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, YLSpacing.xxl, 4, YLSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
          color: YLColors.zinc400,
        ),
      ),
    );
  }
}

/// Delay badge showing latency.
class YLDelayBadge extends StatelessWidget {
  final int? delay;
  final bool testing;

  const YLDelayBadge({super.key, this.delay, this.testing = false});

  static Color colorFor(int d) {
    if (d <= 0) return YLColors.error;
    if (d < 150) return YLColors.connected;
    if (d < 300) return YLColors.connecting;
    return YLColors.error;
  }

  @override
  Widget build(BuildContext context) {
    if (testing) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CupertinoActivityIndicator(radius: 6),
      );
    }
    if (delay == null) {
      return Icon(Icons.speed_rounded,
          size: 14,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3));
    }
    final c = colorFor(delay!);
    return Text(
      delay! <= 0 ? 'Timeout' : '${delay}ms',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: c,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Empty state placeholder.
class YLEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;

  const YLEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(YLSpacing.massive),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 56,
                color: isDark ? YLColors.zinc700 : YLColors.zinc300),
            const SizedBox(height: YLSpacing.xl),
            Text(
              message,
              textAlign: TextAlign.center,
              style: YLText.body.copyWith(color: YLColors.zinc400),
            ),
            if (action != null) ...[
              const SizedBox(height: YLSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A small colored chip.
class YLChip extends StatelessWidget {
  final String label;
  final Color color;

  const YLChip(this.label, {super.key, this.color = YLColors.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// A single settings row — label + optional value/trailing.
class YLInfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const YLInfoRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.enabled = true,
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
          Expanded(
            child: Text(label, style: YLText.body.copyWith(color: labelColor)),
          ),
          if (value != null)
            Text(value!, style: YLText.body.copyWith(color: valueColor)),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap != null && enabled) {
      return InkWell(onTap: onTap, child: content);
    }
    return Opacity(opacity: enabled ? 1.0 : 0.5, child: content);
  }
}

/// A settings row with title, optional description, and trailing.
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
