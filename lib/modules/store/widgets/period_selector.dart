import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme.dart';
import '../../../domain/store/store_plan.dart';

/// Horizontal pill-style period selector (月/季/年…).
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.plan,
    required this.selected,
    required this.onChanged,
  });

  final StorePlan plan;
  final PlanPeriod selected;
  final ValueChanged<PlanPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final isEn = S.of(context).isEn;
    final periods = plan.availablePeriods;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: periods.map((p) {
          final isSelected = p == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? YLColors.primary
                      : (isDark ? YLColors.zinc700 : YLColors.zinc100),
                  borderRadius: BorderRadius.circular(YLRadius.pill),
                  border: Border.all(
                    color: isSelected
                        ? YLColors.primary
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.08)),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.label(isEn),
                      style: YLText.caption.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? YLColors.zinc300 : YLColors.zinc700),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      plan.formattedPrice(p),
                      style: YLText.caption.copyWith(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? Colors.white70
                            : YLColors.zinc500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
