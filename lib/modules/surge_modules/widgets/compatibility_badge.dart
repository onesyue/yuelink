import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../domain/surge_modules/module_entity.dart';

/// Small badge summarising what capabilities a module uses
/// and whether they are active in the current version.
class CompatibilityBadge extends StatelessWidget {
  final UnsupportedCounts counts;

  const CompatibilityBadge({super.key, required this.counts});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!counts.hasUnsupported) {
      return _Badge(
        label: 'Rules only',
        color: isDark ? YLColors.zinc600 : YLColors.zinc300,
        textColor: isDark ? YLColors.zinc300 : YLColors.zinc600,
      );
    }

    // Build a combined label for the most prominent unsupported type
    final parts = <String>[];
    if (counts.mitmCount > 0) parts.add('MITM');
    if (counts.scriptCount > 0) parts.add('Script');
    if (counts.urlRewriteCount > 0) parts.add('Rewrite');
    if (counts.headerRewriteCount > 0) parts.add('Header');
    if (counts.mapLocalCount > 0) parts.add('MapLocal');
    if (counts.panelCount > 0) parts.add('Panel');

    final label = parts.length == 1
        ? '\u26a0 ${parts.first} detected'
        : '\u26a0 ${counts.total} items inactive';

    const warningColor = Color(0xFFF59E0B); // Amber-500
    return _Badge(
      label: label,
      color: isDark
          ? warningColor.withValues(alpha: 0.18)
          : warningColor.withValues(alpha: 0.12),
      textColor: warningColor,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _Badge({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Text(
        label,
        style: YLText.caption.copyWith(
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
