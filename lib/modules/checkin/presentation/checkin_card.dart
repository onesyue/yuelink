import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../theme.dart';
import '../providers/checkin_provider.dart';

/// Compact check-in card for the Dashboard page.
///
/// Shows a check-in button with reward info. When checked in,
/// displays the reward received today.
class CheckinCard extends ConsumerWidget {
  const CheckinCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) return const SizedBox.shrink();

    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(checkinProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Row(
        children: [
          // ── Icon ─────────────────────────────────────────────────
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: state.checkedInOnOtherDevice
                  ? Colors.orange.withValues(alpha: 0.12)
                  : state.checkedIn
                      ? const Color(0xFF22C55E).withValues(alpha: 0.12)
                      : (isDark ? YLColors.zinc700 : YLColors.zinc100),
              borderRadius: BorderRadius.circular(YLRadius.lg),
            ),
            child: Icon(
              state.checkedInOnOtherDevice
                  ? Icons.devices_rounded
                  : state.checkedIn
                      ? Icons.check_circle_rounded
                      : Icons.calendar_today_rounded,
              size: 20,
              color: state.checkedInOnOtherDevice
                  ? Colors.orange
                  : state.checkedIn
                      ? const Color(0xFF22C55E)
                      : YLColors.zinc400,
            ),
          ),
          const SizedBox(width: 12),

          // ── Text ─────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.checkinTitle,
                  style: YLText.label.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  state.checkedInOnOtherDevice
                      ? s.checkinOtherDevice
                      : state.checkedIn
                          ? (state.lastResult != null &&
                                  state.lastResult!.amountText.isNotEmpty &&
                                  state.lastResult!.amountText != '0 MB'
                              ? '${s.checkinReward}: ${state.lastResult!.amountText}'
                              : s.checkinDone)
                          : s.checkinDesc,
                  style: YLText.caption.copyWith(
                    color: state.checkedInOnOtherDevice
                        ? Colors.orange
                        : YLColors.zinc500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // ── Button / Badge ────────────────────────────────────────
          if (state.checkedInOnOtherDevice)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(YLRadius.pill),
              ),
              child: Text(
                s.checkinDone,
                style: YLText.caption.copyWith(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (state.checkedIn)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(YLRadius.pill),
              ),
              child: Text(
                s.checkinDone,
                style: YLText.caption.copyWith(
                  color: const Color(0xFF22C55E),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            FilledButton(
              onPressed: state.loading
                  ? null
                  : () => ref.read(checkinProvider.notifier).checkin(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YLRadius.pill),
                ),
              ),
              child: state.loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(s.checkinAction,
                      style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
