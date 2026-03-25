import 'package:flutter/material.dart';

import '../../../infrastructure/store/store_repository.dart';
import '../../../l10n/app_strings.dart';
import '../../../theme.dart';

/// Top card on the store page showing user's current plan + traffic.
class CurrentPlanCard extends StatelessWidget {
  const CurrentPlanCard({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final usagePercent = profile.usagePercent ?? 0.0;
    final barColor = usagePercent > 0.9
        ? YLColors.error
        : usagePercent > 0.7
            ? Colors.orange
            : YLColors.connected;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Padding(
        padding: const EdgeInsets.all(YLSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Plan name + expiry ──────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.storeCurrentPlan,
                        style: YLText.caption.copyWith(color: YLColors.zinc500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.planName?.isNotEmpty == true
                            ? profile.planName!
                            : s.dashNoPlan,
                        style: YLText.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _expiryChip(context, s),
              ],
            ),

            const SizedBox(height: YLSpacing.md),

            // ── Traffic bar ─────────────────────────────────────────
            if (profile.transferEnable != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    s.authTraffic,
                    style: YLText.caption.copyWith(color: YLColors.zinc500),
                  ),
                  Text(
                    _trafficText(profile),
                    style: YLText.caption.copyWith(color: YLColors.zinc400),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(YLRadius.pill),
                child: LinearProgressIndicator(
                  value: usagePercent.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor:
                      isDark ? YLColors.zinc700 : YLColors.zinc100,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _expiryChip(BuildContext context, S s) {
    if (profile.expiredAt == null) return const SizedBox.shrink();

    final isExpired = profile.isExpired;
    final days = profile.daysRemaining ?? 0;

    String label;
    Color color;
    if (isExpired) {
      label = s.authExpired;
      color = YLColors.error;
    } else if (days <= 7) {
      label = s.authDaysRemaining(days);
      color = Colors.orange;
    } else {
      label = s.authDaysRemaining(days);
      color = YLColors.zinc500;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(YLRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style:
            YLText.caption.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _trafficText(UserProfile p) {
    String fmt(int? bytes) {
      if (bytes == null) return '?';
      const gb = 1024 * 1024 * 1024;
      if (bytes >= gb) {
        final g = bytes / gb;
        return '${g.toStringAsFixed(g == g.truncate() ? 0 : 1)}G';
      }
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}M';
    }

    final used = (p.uploadUsed ?? 0) + (p.downloadUsed ?? 0);
    return '${fmt(used)} / ${fmt(p.transferEnable)}';
  }
}
