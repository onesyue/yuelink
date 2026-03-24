import 'package:flutter/material.dart';

import '../../theme.dart';

/// Emby page colors that follow the main app theme.
///
/// Dark mode uses the same zinc palette as the rest of YueLink.
/// Light mode uses white/zinc tones for consistency.
class EmbyTheme {
  EmbyTheme._();

  /// Page scaffold background.
  static Color scaffoldBg(BuildContext context) =>
      _dark(context) ? YLColors.zinc950 : YLColors.zinc100;

  /// AppBar background (matches scaffold).
  static Color appBarBg(BuildContext context) =>
      _dark(context) ? YLColors.zinc950 : Colors.white;

  /// Card / elevated surface (episode tiles, placeholder).
  static Color surface(BuildContext context) =>
      _dark(context) ? YLColors.zinc900 : Colors.white;

  /// Gradient bottom color (matches scaffold for seamless blend).
  static Color gradientEnd(BuildContext context) =>
      _dark(context) ? YLColors.zinc950 : YLColors.zinc100;

  /// Text colors.
  static Color textPrimary(BuildContext context) =>
      _dark(context) ? Colors.white : YLColors.zinc900;

  static Color textSecondary(BuildContext context) =>
      _dark(context) ? YLColors.zinc400 : YLColors.zinc500;

  static Color textTertiary(BuildContext context) =>
      _dark(context) ? YLColors.zinc500 : YLColors.zinc400;

  /// Chip / tag background.
  static Color chipBg(BuildContext context) => _dark(context)
      ? Colors.white.withValues(alpha: 0.1)
      : Colors.black.withValues(alpha: 0.06);

  /// Chip text.
  static Color chipText(BuildContext context) =>
      _dark(context) ? YLColors.zinc300 : YLColors.zinc600;

  /// Placeholder image background.
  static Color placeholder(BuildContext context) =>
      _dark(context) ? YLColors.zinc900 : YLColors.zinc200;

  /// Selected pill.
  static Color pillSelected(BuildContext context) =>
      _dark(context) ? Colors.white : YLColors.zinc900;

  static Color pillSelectedText(BuildContext context) =>
      _dark(context) ? Colors.black87 : Colors.white;

  /// Unselected pill.
  static Color pillUnselected(BuildContext context) =>
      _dark(context) ? Colors.white12 : Colors.black.withValues(alpha: 0.06);

  static Color pillUnselectedText(BuildContext context) =>
      _dark(context) ? YLColors.zinc300 : YLColors.zinc600;

  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}
