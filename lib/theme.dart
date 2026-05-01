import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ── Semantic colour tokens (Vercel / Tailwind inspired) ──────────────────────

class YLColors {
  YLColors._();

  // ── Neutrals (zinc-based, highly refined) ──────────────────────────────────
  static const zinc50 = Color(0xFFFAFAFA);
  static const zinc100 = Color(0xFFF4F4F5);
  static const zinc200 = Color(0xFFE4E4E7);
  static const zinc300 = Color(0xFFD4D4D8);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc500 = Color(0xFF71717A);
  static const zinc600 = Color(0xFF52525B);
  static const zinc700 = Color(0xFF3F3F46);
  static const zinc750 = Color(0xFF333338); // Between zinc700 and zinc800
  static const zinc800 = Color(0xFF27272A);
  static const zinc850 = Color(0xFF1F1F23); // Between zinc800 and zinc900
  static const zinc900 = Color(0xFF18181B);
  static const zinc950 = Color(0xFF09090B); // True dark for OLED/Premium feel

  // ── Brand (Sleek, professional Indigo/Black) ───────────────────────────────
  static const primary = Color(
    0xFF000000,
  ); // Default to sleek black in light mode
  static const primaryDark = Color(0xFFFFFFFF); // White in dark mode
  static const accent = Color(0xFF3B82F6); // Blue-500 for active states
  // Dynamic accent — set by buildTheme(), read by widgets via YLColors.currentAccent
  static Color _currentAccent = accent;
  static Color get currentAccent => _currentAccent;
  static const primaryLight = Color(0xFFF5F5F5); // Light primary background

  // ── Status semantics (Clear, accessible) ──────────────────────────────────
  static const connected = Color(0xFF10B981); // Emerald-500
  static const connecting = Color(0xFFF59E0B); // Amber-500
  static const disconnected = Color(0xFF71717A); // Zinc-500
  static const error = Color(0xFFEF4444); // Red-500
  static const errorLight = Color(0xFFFEF2F2); // Red-50

  /// TUN-mode connected accent. Indigo-500 (YueLink brand family) — visually
  /// distinct from the emerald [connected] used for system-proxy mode so the
  /// user can tell at a glance which connection mode is active on desktop.
  static const tunConnected = Color(0xFF6366F1); // Indigo-500

  /// Pick the "running" accent color based on the active connection mode.
  /// Use [connected] (emerald) for system-proxy, [tunConnected] (indigo)
  /// for TUN.
  static Color runningAccent({required bool tun}) =>
      tun ? tunConnected : connected;

  // ── Legacy aliases ────────────────────────────────────────────────────────
  static const bgLight = zinc100;
  static const bgDark = zinc950;
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = zinc900;
}

// ── Typography scale (Apple-like clarity) ─────────────────────────────────────

class YLText {
  YLText._();

  static const display = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.16,
    letterSpacing: 0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const pageTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.18,
    letterSpacing: 0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const collapsedTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.24,
    letterSpacing: 0,
  );

  static const titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.26,
    letterSpacing: 0,
  );

  static const titleMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.32,
    letterSpacing: 0,
  );

  static const rowTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.32,
    letterSpacing: 0,
  );

  static const rowSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
    letterSpacing: 0,
  );

  static const badge = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0,
  );

  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.42,
    letterSpacing: 0,
  );

  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.25,
    letterSpacing: 0,
  );

  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.34,
    letterSpacing: 0,
  );

  static const mono = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.34,
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const monoSmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.34,
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const price = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.12,
    letterSpacing: 0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const stat = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: 0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// iOS-style tabular figures — numbers align in fixed-width columns
  /// so digits don't shift when values update.
  static const tabularNums = [FontFeature.tabularFigures()];
}

// ── Spacing scale ─────────────────────────────────────────────────────────────

class YLSpacing {
  YLSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const massive = 48.0;
}

// ── Border radius scale (Apple squircle inspired) ─────────────────────────────

class YLRadius {
  YLRadius._();
  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 12.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const pill = 999.0;
}

// ── Shadow scale ─────────────────────────────────────────────────────────────

class YLShadow {
  YLShadow._();

  /// Small: selected pills, tabs, segmented controls. Light only.
  static List<BoxShadow> sm(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) return const [];
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// Card: standard content cards across all pages.
  static List<BoxShadow> card(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) return const [];
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// Hero: primary visual anchor (HeroCard only).
  static List<BoxShadow> hero(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) return const [];
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.07),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
    ];
  }

  /// Overlay: bottom sheets, floating panels.
  static List<BoxShadow> overlay(BuildContext context) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.12),
        blurRadius: 12,
        offset: const Offset(0, -2),
      ),
    ];
  }
}

// ── Glass material tokens ────────────────────────────────────────────────────

class YLGlass {
  YLGlass._();

  static Color surface(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? YLColors.zinc900.withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.72);
  }

  static Color strongSurface(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? YLColors.zinc900.withValues(alpha: 0.88)
        : Colors.white.withValues(alpha: 0.86);
  }

  static Color border(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.72);
  }

  static Color hairline(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.055);
  }

  static BoxDecoration pageBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = YLColors.currentAccent;
    if (isDark) {
      return BoxDecoration(
        color: YLColors.zinc950,
        gradient: RadialGradient(
          center: const Alignment(0.72, -1.12),
          radius: 1.18,
          colors: [
            accent.withValues(alpha: 0.13),
            YLColors.zinc950.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ),
      );
    }
    return BoxDecoration(
      color: YLColors.zinc100,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white,
          accent.withValues(alpha: 0.045),
          YLColors.zinc100,
        ],
        stops: const [0.0, 0.42, 1.0],
      ),
    );
  }

  static BoxDecoration surfaceDecoration(
    BuildContext context, {
    double radius = YLRadius.lg,
    bool elevated = true,
    bool strong = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = strong ? strongSurface(context) : surface(context);
    return BoxDecoration(
      color: base,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border(context), width: 0.7),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.055 : 0.30),
          base,
        ],
      ),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
                blurRadius: 18,
                spreadRadius: -12,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: isDark ? 0.03 : 0.42),
                blurRadius: 1,
                offset: const Offset(0, 1),
              ),
            ]
          : const [],
    );
  }
}

// ── Theme factory ─────────────────────────────────────────────────────────────

ThemeData buildTheme(
  Brightness brightness, {
  Color? accentColor,
  ColorScheme? dynamicScheme,
}) {
  final isDark = brightness == Brightness.dark;

  final bg = isDark ? YLColors.zinc950 : YLColors.zinc100;
  final surface = isDark ? YLColors.zinc900 : Colors.white;
  final border = isDark ? YLColors.zinc800 : YLColors.zinc300;
  final primary = isDark ? YLColors.primaryDark : YLColors.primary;
  final divider = isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000);
  // Store the accent color in a static so widgets can read it without context.
  YLColors._currentAccent = accentColor ?? YLColors.accent;

  // Material 3: generate the full tonal palette from the accent color.
  // This ensures Switch, FAB, ProgressIndicator, Slider, Checkbox, etc.
  // all respect the user's chosen color — not just a static secondary slot.
  final accent = accentColor ?? YLColors.accent;
  // When Material You dynamic color is available (Android 12+), use it as
  // the seed so primary/secondary/tertiary tint every M3 component to the
  // user's system wallpaper palette. Falls back to our brand-seeded
  // scheme on older Android / iOS / desktop.
  final seedScheme =
      dynamicScheme ??
      ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
  // Keep our custom zinc surfaces but take primary/secondary/tertiary
  // from the seed-generated scheme so Material components are tinted.
  final colorScheme = seedScheme.copyWith(
    surface: surface,
    surfaceContainerLowest: bg,
    surfaceContainerLow: isDark ? YLColors.zinc850 : YLColors.zinc50,
    surfaceContainer: isDark ? YLColors.zinc800 : YLColors.zinc100,
    surfaceContainerHigh: isDark ? YLColors.zinc750 : YLColors.zinc200,
    surfaceContainerHighest: isDark ? YLColors.zinc700 : YLColors.zinc300,
    onSurface: isDark ? YLColors.zinc100 : YLColors.zinc900,
    onSurfaceVariant: isDark ? YLColors.zinc400 : YLColors.zinc500,
    outline: border,
    outlineVariant: isDark ? YLColors.zinc800 : YLColors.zinc200,
  );

  // Typography: prefer each OS' native UI font, then add CJK/emoji fallbacks.
  // This keeps iOS/macOS close to Apple's SF metrics, Android close to
  // Roboto/Noto, and desktop close to the host platform instead of forcing
  // a web font everywhere.
  final typography = Typography.material2021(platform: defaultTargetPlatform);
  final baseTextTheme = isDark ? typography.white : typography.black;
  final textTheme = baseTextTheme.apply(
    fontFamily: _platformFontFamily(),
    fontFamilyFallback: _platformFontFallbacks(),
    bodyColor: colorScheme.onSurface,
    displayColor: colorScheme.onSurface,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    brightness: brightness,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: YLText.collapsedTitle.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface, size: 20),
      actionsIconTheme: IconThemeData(color: colorScheme.onSurface, size: 20),
    ),
    splashFactory:
        NoSplash.splashFactory, // Remove Android ripples for premium feel
    splashColor: Colors.transparent,
    // Unified push/pop transitions across all platforms:
    //   iOS/macOS — Cupertino (edge swipe-back supported on iOS)
    //   Android/Windows/Linux — Material 3 zoom (shared-axis feel)
    // Replaces the default Android slide-from-right which feels dated.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: ZoomPageTransitionsBuilder(
          allowEnterRouteSnapshotting: false,
        ),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(
          allowEnterRouteSnapshotting: false,
        ),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(
          allowEnterRouteSnapshotting: false,
        ),
      },
    ),
    // iOS-style press feedback: subtle gray fade instead of Material ripple.
    highlightColor: isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04),
    hoverColor: isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.03),
    typography: typography,
    fontFamily: _platformFontFamily(),
    fontFamilyFallback: _platformFontFallbacks(),
    textTheme: textTheme,

    // Surfaces
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark
          ? YLColors.zinc900.withValues(alpha: 0.86)
          : Colors.white.withValues(alpha: 0.86),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YLRadius.lg),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.72),
          width: 0.7,
        ),
      ),
    ),

    // Dividers — iOS-style: hairline + indent to align with text after icon.
    // Custom Divider() with explicit indent/thickness/space override these defaults.
    dividerTheme: DividerThemeData(
      space: 0.33,
      thickness: 0.33,
      indent: 60,
      endIndent: 0,
      color: divider,
    ),

    // List tiles
    listTileTheme: ListTileThemeData(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: YLSpacing.lg,
        vertical: YLSpacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YLRadius.lg),
      ),
    ),

    // Inputs (Vercel style)
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: isDark
          ? YLColors.zinc900.withValues(alpha: 0.74)
          : Colors.white.withValues(alpha: 0.76),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(YLRadius.md),
        borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.70),
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(YLRadius.md),
        borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.70),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(YLRadius.md),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: YLText.body.copyWith(color: YLColors.zinc500),
    ),

    // Buttons (Sleek, not pill-shaped unless specific)
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: isDark ? Colors.black : Colors.white,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YLRadius.md),
        ),
        textStyle: YLText.label.copyWith(fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YLRadius.md),
        ),
        side: BorderSide(color: border, width: 1),
        textStyle: YLText.label.copyWith(fontWeight: FontWeight.w600),
      ),
    ),

    // Segmented button (Apple style)
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: isDark ? YLColors.zinc700 : Colors.white,
        selectedForegroundColor: primary,
        backgroundColor: isDark ? YLColors.zinc900 : YLColors.zinc100,
        side: BorderSide(color: border, width: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YLRadius.md),
        ),
        textStyle: YLText.label.copyWith(fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),

    // Switch (iOS style)
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return YLColors.connected;
        return isDark ? YLColors.zinc700 : YLColors.zinc300;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}

String? _platformFontFamily() {
  if (Platform.isAndroid) return 'Roboto';
  if (Platform.isWindows) return 'Segoe UI';
  if (Platform.isLinux) return 'Noto Sans';
  return null;
}

List<String> _platformFontFallbacks() {
  if (Platform.isIOS || Platform.isMacOS) {
    return const [
      'PingFang SC',
      'PingFang TC',
      'Hiragino Sans GB',
      'Apple Color Emoji',
    ];
  }
  if (Platform.isWindows) {
    return const ['Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI Emoji'];
  }
  if (Platform.isAndroid) {
    return const ['Noto Sans CJK SC', 'Noto Sans SC', 'Noto Color Emoji'];
  }
  return const ['Noto Sans CJK SC', 'Noto Sans SC', 'Noto Color Emoji'];
}

// ── Reusable components ───────────────────────────────────────────────────────

class YLStatusDot extends StatelessWidget {
  final Color color;
  final double size;
  final bool glow;

  const YLStatusDot({
    super.key,
    required this.color,
    this.size = 8,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class YLSectionLabel extends StatelessWidget {
  final String text;
  const YLSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        YLSpacing.lg,
        YLSpacing.xl,
        YLSpacing.lg,
        YLSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: YLColors.zinc500,
        ),
      ),
    );
  }
}

class YLSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const YLSurface({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      margin: margin,
      padding: padding,
      decoration: YLGlass.surfaceDecoration(context),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(YLRadius.lg),
          child: content,
        ),
      );
    }

    return content;
  }
}

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
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (delay == null) {
      return Icon(
        Icons.speed_rounded,
        size: 14,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
      );
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
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A small colored chip label.
class YLChip extends StatelessWidget {
  final String label;
  final Color color;

  const YLChip(this.label, {super.key, this.color = YLColors.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Pill-shaped Segmented Control.
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
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(YLRadius.pill),
      ),
      child: Row(
        children: List.generate(values.length, (index) {
          final isSelected = values[index] == selectedValue;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(values[index]),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? YLColors.surfaceDark : YLColors.surfaceLight)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(YLRadius.pill),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[index],
                  style: YLText.label.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
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
            horizontal: YLSpacing.lg,
            vertical: YLSpacing.md,
          ),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
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
                        color: isDark ? Colors.white : Colors.black,
                      ),
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
