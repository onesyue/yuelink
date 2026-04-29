import 'package:flutter/material.dart';

import '../../../domain/checkin/sign_calendar_entity.dart';
import '../../../i18n/app_strings.dart';
import '../../../theme.dart';

/// 7×6 month grid for sign-in history.
///
/// 2026 redesign (was emoji-per-cell): rounded squares with soft colour
/// wash for signed / resign-card days, a small icon corner-mark, and a
/// subtle dot for missed days. Today gets an outline ring in the
/// status's accent colour. Removes the ◽✅⭐⛔🔴⏳ emoji set, which
/// rendered inconsistently across vendor emoji fonts (especially on
/// Samsung & MIUI) and read as AI-template clipart.
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
    final s = S.of(context);
    final weeks = _buildWeeks();
    final byDate = data.byDate;
    final today = data.today;
    final headerColor = isDark ? YLColors.zinc500 : YLColors.zinc500;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            children:
                <String>[
                      s.weekMon,
                      s.weekTue,
                      s.weekWed,
                      s.weekThu,
                      s.weekFri,
                      s.weekSat,
                      s.weekSun,
                    ]
                    .map(
                      (w) => Expanded(
                        child: Center(
                          child: Text(
                            w,
                            style: YLText.caption.copyWith(
                              color: headerColor,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ),
        const SizedBox(height: 4),
        ...weeks.map(
          (week) => _WeekRow(
            week: week,
            byDate: byDate,
            today: today,
            targetMonth:
                int.tryParse(data.month.split('-').last) ?? today.month,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  /// Build 6 weeks × 7 days, starting from the Monday of the first row.
  List<List<DateTime>> _buildWeeks() {
    final parts = data.month.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final first = DateTime(year, month, 1);
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
  final bool isDark;

  const _WeekRow({
    required this.week,
    required this.byDate,
    required this.today,
    required this.targetMonth,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: week.map((d) {
          final inMonth = d.month == targetMonth;
          if (!inMonth) {
            return Expanded(
              child: _Cell(
                day: d.day,
                status: _CellStatus.outOfMonth,
                isToday: false,
                isDark: isDark,
              ),
            );
          }
          final iso = _iso(d);
          final isToday = _sameDay(d, today);
          final entry = byDate[iso];
          final isFuture = d.isAfter(today);

          return Expanded(
            child: _Cell(
              day: d.day,
              status: _statusFor(
                entry: entry,
                isToday: isToday,
                isFuture: isFuture,
              ),
              isToday: isToday,
              isDark: isDark,
            ),
          );
        }).toList(),
      ),
    );
  }

  static _CellStatus _statusFor({
    required SignDay? entry,
    required bool isToday,
    required bool isFuture,
  }) {
    if (entry != null) {
      return entry.isCardResign ? _CellStatus.resigned : _CellStatus.signed;
    }
    if (isToday) return _CellStatus.todayPending;
    if (isFuture) return _CellStatus.future;
    return _CellStatus.missed;
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

enum _CellStatus { signed, resigned, missed, todayPending, future, outOfMonth }

/// Single day cell. Variant geometry is uniform (rounded square, ~48px);
/// the visual differentiation comes from background wash + corner mark
/// + ring for today.
class _Cell extends StatelessWidget {
  final int day;
  final _CellStatus status;
  final bool isToday;
  final bool isDark;

  const _Cell({
    required this.day,
    required this.status,
    required this.isToday,
    required this.isDark,
  });

  static const _amber = Color(0xFFF59E0B);
  static const _danger = Color(0xFFEF4444);

  Color? get _accent {
    switch (status) {
      case _CellStatus.signed:
        return YLColors.connected;
      case _CellStatus.resigned:
        return _amber;
      case _CellStatus.missed:
        return _danger;
      case _CellStatus.todayPending:
        return _danger;
      case _CellStatus.future:
      case _CellStatus.outOfMonth:
        return null;
    }
  }

  Color get _bg {
    switch (status) {
      case _CellStatus.signed:
        return YLColors.connected.withValues(alpha: isDark ? 0.16 : 0.10);
      case _CellStatus.resigned:
        return _amber.withValues(alpha: isDark ? 0.16 : 0.10);
      default:
        return Colors.transparent;
    }
  }

  Color get _fg {
    switch (status) {
      case _CellStatus.signed:
      case _CellStatus.resigned:
      case _CellStatus.todayPending:
        return isDark ? Colors.white : YLColors.zinc900;
      case _CellStatus.missed:
        return isDark ? YLColors.zinc300 : YLColors.zinc700;
      case _CellStatus.future:
        return isDark ? YLColors.zinc600 : YLColors.zinc400;
      case _CellStatus.outOfMonth:
        return isDark ? YLColors.zinc800 : YLColors.zinc300;
    }
  }

  FontWeight get _fw {
    if (isToday ||
        status == _CellStatus.signed ||
        status == _CellStatus.resigned) {
      return FontWeight.w700;
    }
    return FontWeight.w500;
  }

  IconData? get _cornerIcon {
    switch (status) {
      case _CellStatus.signed:
        return Icons.check_rounded;
      case _CellStatus.resigned:
        return Icons.auto_awesome_rounded;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ringColor = _accent ?? YLColors.zinc400;
    return AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Container(
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(YLRadius.md),
            border: isToday
                ? Border.all(
                    color: ringColor.withValues(alpha: 0.55),
                    width: 1.4,
                  )
                : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  '$day',
                  style: TextStyle(
                    color: _fg,
                    fontSize: 13,
                    fontWeight: _fw,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1.0,
                  ),
                ),
              ),
              if (_cornerIcon != null)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Icon(_cornerIcon, size: 9, color: _accent),
                )
              else if (status == _CellStatus.missed)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 5,
                  child: Center(
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: _danger.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
