import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme.dart';
import '../../../domain/store/store_plan.dart';
import '../store_providers.dart';
import 'plan_detail_sheet.dart';

/// Compact plan card for the store home list.
class PlanCard extends ConsumerWidget {
  const PlanCard({
    super.key,
    required this.plan,
    this.isCurrentPlan = false,
  });

  final StorePlan plan;
  final bool isCurrentPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEn = S.of(context).isEn;

    // Use the cheapest available period as the headline price
    final periods = plan.availablePeriods;
    final selectedPeriod =
        ref.watch(selectedPeriodProvider(plan.id)) ?? periods.firstOrNull;
    final price = selectedPeriod != null
        ? plan.formattedPrice(selectedPeriod)
        : '-';
    final periodLabel = selectedPeriod?.label(isEn) ?? '';

    return GestureDetector(
      onTap: () => _showDetail(context, ref, selectedPeriod),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc900 : Colors.white,
          borderRadius: BorderRadius.circular(YLRadius.xl),
          border: Border.all(
            color: isCurrentPlan
                ? YLColors.connected.withValues(alpha: 0.5)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06)),
            width: isCurrentPlan ? 1.0 : 0.5,
          ),
          boxShadow: YLShadow.card(context),
        ),
        child: Padding(
          padding: const EdgeInsets.all(YLSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: name + badge ─────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.name,
                      style: YLText.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isCurrentPlan)
                    _Badge(label: isEn ? 'Current' : '当前', color: YLColors.connected),
                ],
              ),

              const SizedBox(height: YLSpacing.sm),

              // ── Info chips ────────────────────────────────────────
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _InfoChip(icon: Icons.data_usage_rounded, label: plan.trafficLabel),
                  _InfoChip(icon: Icons.speed_rounded, label: plan.speedLabel),
                  if (plan.deviceLimit != null)
                    _InfoChip(icon: Icons.devices_rounded, label: plan.deviceLabel),
                ],
              ),

              const SizedBox(height: YLSpacing.md),

              // ── Price row ─────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: YLText.titleLarge.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : YLColors.zinc900,
                    ),
                  ),
                  if (periodLabel.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '/ $periodLabel',
                        style: YLText.caption.copyWith(color: YLColors.zinc500),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Quick buy button
                  FilledButton(
                    onPressed: () => _showDetail(context, ref, selectedPeriod),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isDark ? Colors.white : YLColors.primary,
                      foregroundColor:
                          isDark ? YLColors.primary : Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YLRadius.sm),
                      ),
                    ),
                    child: Text(
                      isCurrentPlan
                          ? (isEn ? 'Renew' : '续订')
                          : (isEn ? 'Subscribe' : '立即订阅'),
                      style: YLText.caption
                          .copyWith(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref, PlanPeriod? period) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlanDetailSheet(
        plan: plan,
        initialPeriod: period,
        isCurrentPlan: isCurrentPlan,
      ),
    );
  }
}

// ── Small badge chip ──────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(YLRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: YLText.caption.copyWith(
            color: color, fontWeight: FontWeight.w600, fontSize: 10),
      ),
    );
  }
}

// ── Info chip ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : YLColors.zinc100,
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: YLColors.zinc500),
          const SizedBox(width: 3),
          Text(
            label,
            style: YLText.caption
                .copyWith(fontSize: 10, color: YLColors.zinc500),
          ),
        ],
      ),
    );
  }
}
