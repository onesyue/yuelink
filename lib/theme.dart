import 'dart:ui';

import 'package:flutter/material.dart';

// ── Semantic colour tokens (Vercel / Tailwind inspired) ──────────────────────

class YLColors {
  YLColors._();

  // ── Neutrals (zinc-based, highly refined) ──────────────────────────────────
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
  static const zinc950 = Color(0xFF09090B); // True dark for OLED/Premium feel

  // ── Brand (Sleek, professional Indigo/Black) ───────────────────────────────
  static const primary = Color(0xFF000000);     // Default to sleek black in light mode
  static const primaryDark = Color(0xFFFFFFFF); // White in dark mode
  static const accent = Color(0xFF3B82F6);      // Blue-500 for active states

  // ── Status semantics (Clear, accessible) ──────────────────────────────────
  static const connected    = Color(0xFF10B981); // Emerald-500
  static const connecting   = Color(0xFFF59E0B); // Amber-500
  static const disconnected = Color(0xFF71717A); // Zinc-500
  static const error        = Color(0xFFEF4444); // Red-500
  static const errorLight   = Color(0xFFFEF2F2); // Red-50
}

// ── Typography scale (Apple-like clarity) ─────────────────────────────────────

class YLText {
  YLText._();

  static const display = TextStyle(
      fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8,
      fontFeatures: [FontFeature.tabularFigures()]);

  static const titleLarge = TextStyle(
      fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.4);

  static const titleMedium = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2);

  static const body = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: -0.1);

  static const label = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.1);

  static const caption = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.2);

  static const mono = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w500,
      fontFamily: 'Menlo', // Fallback to system monospace
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
  static const massive = 48.0;
}

// ── Border radius scale (Apple squircle inspired) ─────────────────────────────

class YLRadius {
  YLRadius._();
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 14.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const pill = 999.0;
}

// ── Theme factory ─────────────────────────────────────────────────────────────

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final bg      = isDark ? YLColors.zinc950  : YLColors.zinc50;
  final surface = isDark ? YLColors.zinc900  : Colors.white;
  final border  = isDark ? YLColors.zinc800  : YLColors.zinc200;
  final primary = isDark ? YLColors.primaryDark : YLColors.primary;
  final divider = isDark ? const Color(0x1AFFFFFF) : const Color(0x0D000000);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
    surface: surface,
    background: bg,
  ).copyWith(
    primary: primary,
    onPrimary: isDark ? Colors.black : Colors.white,
    tertiary: isDark ? YLColors.zinc500 : YLColors.zinc400,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    brightness: brightness,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: bg,
    splashFactory: NoSplash.splashFactory, // Remove Android ripples for premium feel
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
    fontFamily: '.SF Pro Display', // Apple system font fallback

    // Surfaces
    cardTheme: CardTheme(
      elevation: 0,
      color: surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YLRadius.xl),
        side: BorderSide(color: border, width: 0.5), // Hairline borders
      ),
    ),

    // Dividers
    dividerTheme: DividerThemeData(
      space: 1, thickness: 0.5, color: divider,
    ),

    // List tiles
    listTileTheme: ListTileThemeData(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: YLSpacing.lg, vertical: YLSpacing.xs),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YLRadius.lg)),
    ),

    // Inputs (Vercel style)
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: isDark ? YLColors.zinc900 : Colors.white,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YLRadius.md)),
        textStyle: YLText.label.copyWith(fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YLRadius.md)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YLRadius.md)),
        textStyle: YLText.label.copyWith(fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),

    // Switch (iOS style)
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.all(Colors.white),
      trackColor: MaterialStateProperty.resolveWith((s) {
        if (s.contains(MaterialState.selected)) return YLColors.connected;
        return isDark ? YLColors.zinc700 : YLColors.zinc300;
      }),
      trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
    ),
  );
}

// ── Reusable components ───────────────────────────────────────────────────────

class YLStatusDot extends StatelessWidget {
  final Color color;
  final double size;
  final bool glow;
  
  const YLStatusDot({super.key, required this.color, this.size = 8, this.glow = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle, 
        color: color,
        boxShadow: glow ? [
          BoxShadow(color: color.withOpacity(0.4), blurRadius: 6, spreadRadius: 1)
        ] : null,
      ),
    );
  }
}

class YLSectionLabel extends StatelessWidget {
  final String text;
  const YLSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(YLSpacing.lg, YLSpacing.xl, YLSpacing.lg, YLSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: isDark ? YLColors.zinc500 : YLColors.zinc500,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Widget content = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
          width: 0.5,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
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
          borderRadius: BorderRadius.circular(YLRadius.xl),
          child: content,
        ),
      );
    }

    return content;
  }
}

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
    this.blurSigma = 20,
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
              color: isDark ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.4),
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
        width: 12, height: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (delay == null) {
      return Icon(Icons.speed_rounded, size: 14,
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
