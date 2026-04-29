import 'package:flutter/material.dart';

import '../../../domain/checkin/sign_calendar_entity.dart';
import '../../../theme.dart';

/// 7×N 月历网格。每天用 emoji + 数字双行表达，emoji 表达签到状态：
/// ✅ 已签 ｜⭐ 补签 ｜⛔ 断签 ｜🔴 今天未签 ｜⏳ 未来 ｜◽ 上月余日
class SignCalendarWidget extends StatelessWidget {
  final SignCalendarMonth data;
  final bool isDark;

  const SignCalendarWidget({
    super.key,
    required this.data,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final weeks = _buildWeeks();
    final byDate = data.byDate;
    final today = data.today;
    final headerColor = isDark ? YLColors.zinc400 : YLColors.zinc500;
    final cellTextColor = isDark ? YLColors.zinc300 : YLColors.zinc600;

    return Column(
      children: [
        // 周标题
        Row(
          children: const ['一', '二', '三', '四', '五', '六', '日']
              .map((w) => Expanded(
                    child: SizedBox(
                      height: 22,
                      child: Center(
                        child: Text(w),
                      ),
                    ),
                  ))
              .toList()
              .map((e) => DefaultTextStyle(
                    style: YLText.caption.copyWith(color: headerColor),
                    child: e,
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        // 6 周
        ...weeks.map((week) => _WeekRow(
              week: week,
              byDate: byDate,
              today: today,
              targetMonth: int.tryParse(data.month.split('-').last) ?? today.month,
              cellTextColor: cellTextColor,
            )),
      ],
    );
  }

  /// 构造 6 周 × 7 天的 DateTime 网格。第 1 行从该月 1 号当周的周一开始。
  List<List<DateTime>> _buildWeeks() {
    final parts = data.month.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final first = DateTime(year, month, 1);
    // 周一为 0；DateTime.weekday 周一=1...周日=7
    final firstWeekday = first.weekday - 1;
    final start = first.subtract(Duration(days: firstWeekday));

    final weeks = <List<DateTime>>[];
    for (int w = 0; w < 6; w++) {
      weeks.add(List.generate(7, (i) => start.add(Duration(days: w * 7 + i))));
    }
    return weeks;
  }
}

class _WeekRow extends StatelessWidget {
  final List<DateTime> week;
  final Map<String, SignDay> byDate;
  final DateTime today;
  final int targetMonth;
  final Color cellTextColor;

  const _WeekRow({
    required this.week,
    required this.byDate,
    required this.today,
    required this.targetMonth,
    required this.cellTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: week.map((d) {
          final inMonth = d.month == targetMonth;
          if (!inMonth) {
            return const Expanded(child: _Cell(emoji: '◽', label: '', dim: true));
          }
          final iso = _iso(d);
          final isToday = _sameDay(d, today);
          final entry = byDate[iso];

          String emoji;
          if (entry != null) {
            emoji = entry.isCardResign ? '⭐' : '✅';
          } else if (isToday) {
            emoji = '🔴';
          } else if (d.isAfter(today)) {
            emoji = '⏳';
          } else {
            emoji = '⛔';
          }

          return Expanded(
            child: _Cell(
              emoji: emoji,
              label: '${d.day}',
              dim: false,
              highlight: isToday,
              labelColor: cellTextColor,
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Cell extends StatelessWidget {
  final String emoji;
  final String label;
  final bool dim;
  final bool highlight;
  final Color? labelColor;

  const _Cell({
    required this.emoji,
    required this.label,
    this.dim = false,
    this.highlight = false,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      margin: const EdgeInsets.all(2),
      decoration: highlight
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                width: 1.2,
              ),
            )
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            emoji,
            style: TextStyle(fontSize: 18, color: dim ? YLColors.zinc400 : null),
          ),
          if (label.isNotEmpty) const SizedBox(height: 2),
          if (label.isNotEmpty)
            Text(
              label,
              style: YLText.caption.copyWith(
                color: dim ? YLColors.zinc400 : labelColor,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}
