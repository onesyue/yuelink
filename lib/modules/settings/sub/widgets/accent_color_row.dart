import 'package:flutter/material.dart';

import '../../../../theme.dart';

/// Accent color picker row used in the General Settings sub-page.
///
/// Shows a label + current preset name, followed by a row of iOS-style
/// colored dots (one per preset). The selected dot is ringed + checked.
/// Selection is reported through [onChanged] — this widget holds no
/// state of its own.
///
/// Extracted from `sub/general_settings_page.dart` (Batch δ). The
/// underscored `_ColorDot` companion stays private to this file because
/// nothing outside the picker draws one. Rename from `_AccentColorRow`
/// to `AccentColorRow` is the minimum visibility change needed to
/// import it across the library boundary.
class AccentColorRow extends StatelessWidget {
  final String currentHex;
  final ValueChanged<String> onChanged;
  final bool isEn;

  const AccentColorRow({
    super.key,
    required this.currentHex,
    required this.onChanged,
    required this.isEn,
  });

  // Preset seed colors — Material 3 generates full tonal palette from each.
  static const _presets = <(String, String, String)>[
    ('3B82F6', 'Blue', '蓝色'),
    ('6366F1', 'Indigo', '靛蓝'),
    ('8B5CF6', 'Purple', '紫色'),
    ('EC4899', 'Pink', '粉色'),
    ('EF4444', 'Red', '红色'),
    ('F97316', 'Orange', '橙色'),
    ('F59E0B', 'Amber', '琥珀'),
    ('10B981', 'Green', '绿色'),
    ('14B8A6', 'Teal', '青色'),
    ('06B6D4', 'Cyan', '天蓝'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentPreset = _presets.firstWhere(
      (p) => p.$1.toUpperCase() == currentHex.toUpperCase(),
      orElse: () => _presets.first,
    );
    final currentName = isEn ? currentPreset.$2 : currentPreset.$3;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row: "主题色" + current color name on the right
          Row(
            children: [
              Expanded(
                child: Text(
                  isEn ? 'Theme color' : '主题色',
                  style: YLText.body.copyWith(
                    color: isDark ? YLColors.zinc200 : YLColors.zinc700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                currentName,
                style: YLText.caption.copyWith(
                  color: YLColors.zinc400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // iOS-style: row of colored dots with outline ring on selected.
          // Apple Settings / Apple Music / Telegram use this exact pattern.
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: _presets.map((preset) {
              final hex = preset.$1;
              final color = Color(int.parse('FF$hex', radix: 16));
              final isSelected = currentHex.toUpperCase() == hex.toUpperCase();
              return _ColorDot(
                color: color,
                selected: isSelected,
                isDark: isDark,
                onTap: () => onChanged(hex),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// iOS-style colored dot with outline ring when selected.
/// Size: 36px core + 8px gap + 2px ring = 48px total when selected.
class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: color, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: selected
                ? const Center(
                    child: Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
