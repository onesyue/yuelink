import 'dart:ui';

import 'package:flutter/material.dart';

// ── Semantic colour tokens ────────────────────────────────────────────────────

class YLColors {
  YLColors._();

  // ── Neutrals (zinc-based) ──────────────────────────────────────────────────
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
  static const zinc950 = Color(0xFF0F0F10);

  // ── Brand ──────────────────────────────────────────────────────────────────
  static const primary = Color(0xFF4F46E5);     // indigo-600 — muted, trust
  static const primaryLight = Color(0xFFEEF2FF); // indigo-50

  // ── Status semantics ──────────────────────────────────────────────────────
  static const connected    = Color(0xFF16A34A); // green-700
  static const connecting   = Color(0xFFD97706); // amber-600
  static const disconnected = Color(0xFF71717A); // zinc-500
  static const error        = Color(0xFFDC2626); // red-600
  static const errorLight   = Color(0xFFFEF2F2); // red-50
}

// ── Typography scale ──────────────────────────────────────────────────────────

class YLText {
  YLText._();

  // 28px — traffic numbers, big status
  static const display = TextStyle(
      fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.8,
      fontFeatures: [FontFeature.tabularFigures()]);

  // 17px — page title, section header
  static const titleLarge = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3);

  // 15px — card header, list item primary
  static const titleMedium = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2);

  // 13px — body text, list item secondary
  static const body = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);

  // 12px — labels, chips, form hints
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);

  // 11px — timestamps, captions
  static const caption = TextStyle(fontSize: 11, fontWeight: FontWeight.w400);

  // Numbers with tabular figure alignment
  static const mono = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w500,
      fontFeatures: [FontFeature.tabularFigures()]);
}

// ── Spacing scale ─────────────────────────────────────────────────────────────

class YLSpacing {
  YLSpacing._();
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 12.0;
  static const lg  = 16.0;
  static const xl  = 24.0;
  static const xxl = 32.0;
}

// ── Border radius scale ───────────────────────────────────────────────────────

class YLRadius {
  YLRadius._();
  static const sm = 4.0;
  static const md = 6.0;
  static const lg = 8.0;
  static const xl = 12.0;
}

// ── Theme factory ─────────────────────────────────────────────────────────────

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final bg      = isDark ? YLColors.zinc900  : YLColors.zinc50;
  final surface = isDark ? YLColors.zinc800  : Colors.white;
  final border  = isDark ? YLColors.zinc700  : YLColors.zinc200;
  final divider = isDark
      ? const Color(0x18FFFFFF)
      : const Color(0x0E000000);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: YLColors.primary,
    brightness: brightness,
    surface: surface,
  ).copyWith(
    // Override to prevent overly saturated generated colours
    tertiary: isDark ? YLColors.zinc500 : YLColors.zinc400,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    brightness: brightness,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: bg,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.04),

    // Surfaces
    cardTheme: CardTheme(
      elevation: 0,
      color: surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YLRadius.lg),
        side: BorderSide(color: border, width: 1),
      ),
    ),

    // Dividers
    dividerTheme: DividerThemeData(
      space: 1, thickness: 1, color: divider,
    ),

    // List tiles
    listTileTheme: ListTileThemeData(
      dense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: YLSpacing.lg, vertical: 0),
      minVerticalPadding: 0,
      visualDensity: VisualDensity.compact,
    ),

    // Inputs
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: isDark ? YLColors.zinc700 : YLColors.zinc100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(YLRadius.md),
        borderSide: BorderSide(color: border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(YLRadius.md),
        borderSide: BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(YLRadius.md),
        borderSide: const BorderSide(color: YLColors.primary, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),

    // Buttons — never pill-shaped, modest size
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: YLColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YLRadius.md)),
        textStyle: YLText.body.copyWith(fontWeight: FontWeight.w500),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YLRadius.md)),
        side: BorderSide(color: border, width: 1),
        textStyle: YLText.body.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: YLText.body.copyWith(fontWeight: FontWeight.w500),
      ),
    ),

    // Segmented button
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor:
            isDark ? YLColors.zinc700 : YLColors.primary.withValues(alpha: 0.10),
        selectedForegroundColor: YLColors.primary,
        backgroundColor:
            isDark ? YLColors.zinc800 : YLColors.zinc100,
        side: BorderSide(color: border, width: 1),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YLRadius.md)),
        textStyle: YLText.label,
        visualDensity: VisualDensity.compact,
      ),
    ),

    // Switch
    switchTheme: SwitchThemeData(
      thumbColor:
          WidgetStateProperty.resolveWith((s) => Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return YLColors.primary;
        return isDark ? YLColors.zinc600 : YLColors.zinc300;
      }),
      trackOutlineColor:
          WidgetStateProperty.all(Colors.transparent),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),

    // Navigation rail — compact, soft selection
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: isDark ? YLColors.zinc900 : YLColors.zinc50,
      selectedIconTheme:
          const IconThemeData(color: YLColors.primary, size: 18),
      unselectedIconTheme:
          IconThemeData(color: YLColors.zinc500, size: 18),
      selectedLabelTextStyle:
          YLText.caption.copyWith(color: YLColors.primary, fontWeight: FontWeight.w600, fontSize: 10),
      unselectedLabelTextStyle:
          YLText.caption.copyWith(color: YLColors.zinc500, fontSize: 10),
      indicatorColor: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : YLColors.primary.withValues(alpha: 0.08),
      indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YLRadius.lg)),
      minWidth: 56,
      labelType: NavigationRailLabelType.all,
    ),

    // Navigation bar (mobile bottom nav)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: YLColors.primary.withValues(alpha: 0.10),
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(
            size: 20,
            color: s.contains(WidgetState.selected)
                ? YLColors.primary
                : YLColors.zinc500,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) =>
          YLText.caption.copyWith(
            color: s.contains(WidgetState.selected)
                ? YLColors.primary
                : YLColors.zinc500,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
          )),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
    ),
  );
}

// ── Reusable components ───────────────────────────────────────────────────────

/// Small status dot with semantic colour.
class YLStatusDot extends StatelessWidget {
  final Color color;
  final double size;
  const YLStatusDot({super.key, required this.color, this.size = 7});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// A section header that uses macOS-style uppercase label.
class YLSectionLabel extends StatelessWidget {
  final String text;
  const YLSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          YLSpacing.lg, YLSpacing.xl, YLSpacing.lg, YLSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: isDark ? YLColors.zinc400 : YLColors.zinc500,
        ),
      ),
    );
  }
}

/// A row with label on the left, value/control on the right.
/// Used consistently across Settings and info panels.
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
    final faded = !enabled;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: YLSpacing.lg, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: YLText.body.copyWith(
                color: faded
                    ? (isDark ? YLColors.zinc600 : YLColors.zinc400)
                    : null,
              ),
            ),
          ),
          if (value != null)
            Text(
              value!,
              style: YLText.body.copyWith(
                color: isDark ? YLColors.zinc400 : YLColors.zinc500,
              ),
            ),
          if (trailing != null) ...[
            const SizedBox(width: YLSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap != null && !faded) {
      content = InkWell(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}

/// A settings row: title + optional description + trailing control.
class YLSettingsRow extends StatelessWidget {
  final String title;
  final String? description;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const YLSettingsRow({
    super.key,
    required this.title,
    this.description,
    required this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: YLSpacing.lg, vertical: 10),
      child: Row(
        crossAxisAlignment: description != null
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: YLText.body.copyWith(
                        color: enabled
                            ? null
                            : (isDark
                                ? YLColors.zinc600
                                : YLColors.zinc400))),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description!,
                      style: YLText.caption.copyWith(
                        color:
                            isDark ? YLColors.zinc500 : YLColors.zinc400,
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(width: YLSpacing.md),
          trailing,
        ],
      ),
    );

    if (onTap != null && enabled) {
      content = InkWell(onTap: onTap, child: content);
    }

    return content;
  }
}

/// Surfaces with consistent border + bg — replaces raw Card everywhere.
class YLSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const YLSurface({
    super.key,
    required this.child,
    this.margin,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A chip indicating connection/node status.
class YLChip extends StatelessWidget {
  final String label;
  final Color? color;

  const YLChip(this.label, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? YLColors.zinc500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Text(label,
          style: YLText.caption.copyWith(
              color: c, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Business components ───────────────────────────────────────────────────────

/// Centered empty / disconnected state used on all pages.
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36,
              color: (isDark ? YLColors.zinc500 : YLColors.zinc400)
                  .withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: YLText.body.copyWith(
                  color: isDark ? YLColors.zinc500 : YLColors.zinc400)),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Delay badge — shows colored latency or testing spinner.
/// Always uses tabular figures per spec §3.
class YLDelayBadge extends StatelessWidget {
  final int? delay;   // null = untested; ≤0 = timeout
  final bool testing;

  const YLDelayBadge({super.key, this.delay, this.testing = false});

  static Color colorFor(int d) {
    if (d <= 0) return YLColors.error;
    if (d < 100) return const Color(0xFF34C759);
    if (d < 300) return YLColors.connecting;
    return YLColors.error;
  }

  @override
  Widget build(BuildContext context) {
    if (testing) {
      return const SizedBox(
        width: 10, height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    }
    if (delay == null) {
      return Icon(Icons.speed_outlined, size: 11,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.5));
    }
    final c = colorFor(delay!);
    return Text(
      delay! <= 0 ? 'timeout' : '${delay}ms',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: c,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A node list tile — selection state + delay badge.
/// Replaces grid card with a compact list row for cleaner presentation.
class YLNodeTile extends StatelessWidget {
  final String name;
  final bool isSelected;
  final int? delay;
  final bool isTesting;
  final VoidCallback onSelect;
  final VoidCallback onTest;

  const YLNodeTile({
    super.key,
    required this.name,
    required this.isSelected,
    required this.onSelect,
    required this.onTest,
    this.delay,
    this.isTesting = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(YLRadius.lg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(YLRadius.lg),
        ),
        child: Row(
          children: [
            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: isSelected ? primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            // Node name
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Delay badge (tappable for single test)
            GestureDetector(
              onTap: onTest,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: YLDelayBadge(delay: delay, testing: isTesting),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glassmorphism surface — frosted glass effect with subtle blur.
class YLGlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double blurSigma;
  final double borderRadius;

  const YLGlassSurface({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.blurSigma = 12,
    this.borderRadius = YLRadius.xl,
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
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.70),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.80),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A stat card for the Home page: icon + label + value.
/// Uses frosted glass effect with micro-shadow.
class YLStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  const YLStatCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return YLGlassSurface(
      borderRadius: YLRadius.xl,
      blurSigma: 10,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 13, color: iconColor),
                  const SizedBox(width: 4),
                  Text(label,
                      style: YLText.caption.copyWith(
                        color: isDark ? YLColors.zinc500 : YLColors.zinc400,
                      )),
                  const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 5),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YLText.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
