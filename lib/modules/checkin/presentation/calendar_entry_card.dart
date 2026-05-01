import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../theme.dart';
import 'calendar_page.dart';

/// 仪表盘签到日历独立入口卡片。与 CheckinCard 互补：
///  - CheckinCard 关注「今天是否签了」，签到后顺手看日历用图标按钮
///  - CalendarEntryCard 是独立入口，未签到时也显眼可达，承载月度成就感
class CheckinCalendarEntryCard extends ConsumerWidget {
  const CheckinCalendarEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) return const SizedBox.shrink();

    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => CheckinCalendarPage.push(context),
      borderRadius: BorderRadius.circular(YLRadius.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(YLSpacing.md),
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(YLRadius.lg),
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                size: 20,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.calendarEntryTitle,
                    style: YLText.rowTitle.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.calendarEntrySubtitle,
                    style: YLText.caption.copyWith(color: YLColors.zinc500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: YLColors.zinc400,
            ),
          ],
        ),
      ),
    );
  }
}
