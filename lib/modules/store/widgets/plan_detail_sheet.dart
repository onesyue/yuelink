import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme.dart';
import '../../../domain/store/store_plan.dart';
import '../store_providers.dart';
import 'period_selector.dart';
import 'purchase_confirm_sheet.dart';

/// Bottom sheet showing full plan details with period selection + buy action.
class PlanDetailSheet extends ConsumerStatefulWidget {
  const PlanDetailSheet({
    super.key,
    required this.plan,
    this.initialPeriod,
    this.isCurrentPlan = false,
  });

  final StorePlan plan;
  final PlanPeriod? initialPeriod;
  final bool isCurrentPlan;

  @override
  ConsumerState<PlanDetailSheet> createState() => _PlanDetailSheetState();
}

class _PlanDetailSheetState extends ConsumerState<PlanDetailSheet> {
  late PlanPeriod _period;

  @override
  void initState() {
    super.initState();
    final periods = widget.plan.availablePeriods;
    _period = widget.initialPeriod ??
        ref.read(selectedPeriodProvider(widget.plan.id)) ??
        periods.firstOrNull ??
        PlanPeriod.monthly;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.of(context);
    final isEn = s.isEn;
    final plan = widget.plan;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(YLRadius.xxl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Handle ─────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? YLColors.zinc700 : YLColors.zinc200,
                  borderRadius: BorderRadius.circular(YLRadius.pill),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: YLSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Plan name ───────────────────────────────────
                  Text(plan.name,
                      style: YLText.titleLarge
                          .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: YLSpacing.lg),

                  // ── Spec grid ───────────────────────────────────
                  _SpecGrid(plan: plan, isEn: isEn),
                  const SizedBox(height: YLSpacing.lg),

                  // ── Feature description ─────────────────────────
                  if (plan.content != null && plan.content!.trim().isNotEmpty) ...[
                    Text(
                      isEn ? 'Features' : '套餐特点',
                      style: YLText.label.copyWith(color: YLColors.zinc500),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      plan.content!.trim(),
                      style: YLText.body.copyWith(
                        color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: YLSpacing.lg),
                  ],

                  // ── Period selector ─────────────────────────────
                  Text(
                    isEn ? 'Billing Period' : '计费周期',
                    style: YLText.label.copyWith(color: YLColors.zinc500),
                  ),
                  const SizedBox(height: 8),
                  PeriodSelector(
                    plan: plan,
                    selected: _period,
                    onChanged: (p) {
                      setState(() => _period = p);
                      ref
                          .read(selectedPeriodProvider(plan.id).notifier)
                          .state = p;
                    },
                  ),

                  const SizedBox(height: YLSpacing.xl),

                  // ── Price + buy button ──────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.formattedPrice(_period),
                            style: YLText.titleLarge.copyWith(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : YLColors.zinc900,
                            ),
                          ),
                          Text(
                            '/ ${_period.label(isEn)}',
                            style: YLText.caption
                                .copyWith(color: YLColors.zinc500),
                          ),
                        ],
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 46,
                        child: FilledButton(
                          onPressed: () => _confirmPurchase(context),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                isDark ? Colors.white : YLColors.primary,
                            foregroundColor:
                                isDark ? YLColors.primary : Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(YLRadius.md),
                            ),
                          ),
                          child: Text(
                            widget.isCurrentPlan
                                ? (isEn ? 'Renew' : '续订')
                                : (isEn ? 'Subscribe Now' : '立即订阅'),
                            style: YLText.label
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: YLSpacing.lg),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmPurchase(BuildContext context) {
    Navigator.pop(context); // Close detail sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PurchaseConfirmSheet(
        plan: widget.plan,
        period: _period,
      ),
    );
  }
}

// ── Spec grid ─────────────────────────────────────────────────────────────────

class _SpecGrid extends StatelessWidget {
  const _SpecGrid({required this.plan, required this.isEn});
  final StorePlan plan;
  final bool isEn;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final items = [
      (isEn ? 'Traffic' : '流量', plan.trafficLabel, Icons.data_usage_rounded),
      (isEn ? 'Speed' : '速度', plan.speedLabel, Icons.speed_rounded),
      (
        isEn ? 'Devices' : '设备数',
        plan.deviceLabel,
        Icons.devices_rounded
      ),
    ];

    return Row(
      children: items.map((item) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(
                horizontal: YLSpacing.sm, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? YLColors.zinc800 : YLColors.zinc50,
              borderRadius: BorderRadius.circular(YLRadius.md),
            ),
            child: Column(
              children: [
                Icon(item.$3, size: 18, color: YLColors.zinc400),
                const SizedBox(height: 4),
                Text(
                  item.$2,
                  style: YLText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  item.$1,
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
