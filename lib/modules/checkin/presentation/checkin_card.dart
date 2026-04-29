import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../theme.dart';
import '../providers/checkin_provider.dart';
import 'calendar_page.dart';

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
        borderRadius: BorderRadius.circular(YLRadius.lg),
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
                Builder(
                  builder: (_) {
                    String text;
                    if (state.checkedInOnOtherDevice) {
                      text = s.checkinOtherDevice;
                    } else if (state.checkedIn) {
                      final r = state.lastResult;
                      final hasReward = r != null &&
                          r.amountText.isNotEmpty &&
                          r.amountText != '0 MB';
                      final base = hasReward
                          ? '${s.checkinReward}: ${r.amountText}'
                          : s.checkinDone;
                      // 带 streak 副标尾巴：连签 ≥ 2 天才显示，避免新用户首签 "1 天" 啰嗦
                      final streak = r?.streak ?? 0;
                      text = streak >= 2
                          ? '$base · ${s.checkinStreakSuffix(n: streak)}'
                          : base;
                    } else {
                      text = s.checkinDesc;
                    }
                    return Text(
                      text,
                      style: YLText.caption.copyWith(
                        color: state.checkedInOnOtherDevice
                            ? Colors.orange
                            : YLColors.zinc500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ],
            ),
          ),

          // ── 看日历入口（已签 / 已在其他设备签到时都显示，方便用户查月历） ──
          if (state.checkedIn || state.checkedInOnOtherDevice)
            IconButton(
              tooltip: s.calendarTitle,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: 36, minHeight: 36),
              visualDensity: VisualDensity.compact,
              onPressed: () => CheckinCalendarPage.push(context),
              icon: const Icon(
                Icons.calendar_month_rounded,
                size: 20,
                color: YLColors.zinc400,
              ),
            ),
          if (state.checkedIn || state.checkedInOnOtherDevice)
            const SizedBox(width: 4),

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
