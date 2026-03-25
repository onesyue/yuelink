import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../yue_auth/providers/yue_auth_providers.dart';
import '../../../l10n/app_strings.dart';
import '../../../modules/store/store_page.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../shared/formatters/subscription_parser.dart' show formatBytes;
import '../../../theme.dart';

class SubscriptionCard extends ConsumerWidget {
  const SubscriptionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.watch(userProfileProvider);
    final isLoggedIn =
        ref.watch(authProvider.select((a) => a.status == AuthStatus.loggedIn));

    return GestureDetector(
      onTap: () {
        if (profile == null && isLoggedIn) {
          // Profile still loading — trigger manual refresh.
          ref.read(authProvider.notifier).syncSubscription();
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StorePage()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc800 : Colors.white,
          borderRadius: BorderRadius.circular(YLRadius.lg),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: YLShadow.card(context),
        ),
        child: profile == null
            ? _emptyState(s, isDark, loading: isLoggedIn)
            : _profileContent(s, isDark, profile),
      ),
    );
  }

  Widget _emptyState(S s, bool isDark, {bool loading = false}) {
    return Row(
      children: [
        Icon(
          loading ? Icons.sync_rounded : Icons.card_membership_outlined,
          size: 16,
          color: YLColors.zinc400,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            loading ? s.mineSyncing : s.dashNoPlan,
            style: YLText.body.copyWith(color: YLColors.zinc400),
          ),
        ),
        if (loading)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          const Icon(Icons.chevron_right_rounded,
              size: 16, color: YLColors.zinc400),
      ],
    );
  }

  Widget _profileContent(S s, bool isDark, UserProfile profile) {
    final used = (profile.uploadUsed ?? 0) + (profile.downloadUsed ?? 0);
    final total = profile.transferEnable;
    final percent = profile.usagePercent;
    final expiryText = _expiryText(s, profile);
    final expiryColor = _expiryColor(profile);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label + chevron (entire card is tappable → StorePage)
        Row(
          children: [
            const Icon(Icons.card_membership_outlined,
                size: 14, color: YLColors.zinc400),
            const SizedBox(width: 6),
            Text(s.dashMyPlan,
                style: YLText.caption.copyWith(color: YLColors.zinc500)),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: YLColors.zinc400),
          ],
        ),
        const SizedBox(height: 6),

        // Plan name
        Text(
          profile.planName ?? s.dashNoPlan,
          style: YLText.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        // Days remaining subtitle
        if (expiryText.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            expiryText,
            style: YLText.caption.copyWith(color: expiryColor),
          ),
        ],

        if (total != null) ...[
          const SizedBox(height: 10),

          // Traffic row (full-width)
          Row(
            children: [
              Text(s.authTraffic,
                  style: YLText.caption
                      .copyWith(color: YLColors.zinc500)),
              const Spacer(),
              Text(
                '${formatBytes(used)} / ${formatBytes(total)}',
                style: YLText.caption.copyWith(
                  color: isDark ? YLColors.zinc300 : YLColors.zinc600,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(YLRadius.pill),
            child: LinearProgressIndicator(
              value: (percent ?? 0.0).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(
                percent != null && percent > 0.9
                    ? YLColors.error
                    : YLColors.accent,
              ),
            ),
          ),
        ],

        // ── Renewal reminder banner (expired or ≤7 days) ─────────
        if (_shouldShowRenewalBanner(profile))
          _RenewalBanner(profile: profile, s: s),
      ],
    );
  }

  bool _shouldShowRenewalBanner(UserProfile profile) {
    if (profile.isExpired) return true;
    final days = profile.daysRemaining;
    return days != null && days <= 7;
  }

  String _expiryText(S s, UserProfile profile) {
    if (profile.isExpired) return s.authExpired;
    final days = profile.daysRemaining;
    if (days == null) return '';
    if (days == 0) return s.authExpiryToday;
    return s.authDaysRemaining(days);
  }

  Color _expiryColor(UserProfile profile) {
    if (profile.isExpired) return YLColors.error;
    final days = profile.daysRemaining;
    if (days != null && days == 0) return YLColors.error;
    if (days != null && days <= 7) return YLColors.connecting;
    return YLColors.zinc500;
  }
}

// ── Renewal reminder banner ───────────────────────────────────────────────────

class _RenewalBanner extends StatelessWidget {
  const _RenewalBanner({required this.profile, required this.s});
  final UserProfile profile;
  final S s;

  @override
  Widget build(BuildContext context) {
    final isExpired = profile.isExpired;
    final color = isExpired ? YLColors.error : Colors.orange;
    final label = isExpired ? s.storeExpiredReminder : s.storeRenewalReminder;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const StorePage()),
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(YLRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: YLText.caption.copyWith(color: color),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}
