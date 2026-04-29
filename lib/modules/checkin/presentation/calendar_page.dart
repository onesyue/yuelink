import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/checkin/sign_calendar_entity.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/widgets/yl_scaffold.dart';
import '../../../theme.dart';
import '../../yue_auth/providers/yue_auth_providers.dart';
import '../providers/checkin_provider.dart';
import 'calendar_widget.dart';
import 'resign_dialog.dart';

/// 签到日历主页 — 月视图 + 摘要 + 行动按钮。
///
/// 触发场景：
///   1. 设置页 → "签到日历" 入口（用户主动）
///   2. 仪表盘签到卡上 "看日历" 按钮（仅签到后可见）
class CheckinCalendarPage extends ConsumerStatefulWidget {
  const CheckinCalendarPage({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CheckinCalendarPage()),
    );
  }

  @override
  ConsumerState<CheckinCalendarPage> createState() =>
      _CheckinCalendarPageState();
}

class _CheckinCalendarPageState extends ConsumerState<CheckinCalendarPage> {
  SignCalendarMonth? _data;
  bool _loading = true;
  String? _error;
  late DateTime _viewMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewMonth = DateTime(now.year, now.month, 1);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = ref.read(authProvider).token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = S.current.calendarPleaseLogin;
      });
      return;
    }

    final monthStr =
        '${_viewMonth.year.toString().padLeft(4, '0')}-${_viewMonth.month.toString().padLeft(2, '0')}';
    // 必须走 checkinRepositoryProvider 拿 mihomo-proxy-aware 实例 —— 直接 new 出来
    // 的 CheckinRepository 不带 proxyPort，在中国境内会被 GFW 拦截 yue.yuebao.website
    // 导致永远 loading（签到 POST 走 provider 没事，新加的日历 GET 没复用provider 直接挂）。
    final repo = ref.read(checkinRepositoryProvider);
    final data = await repo.fetchHistory(token, month: monthStr);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      _error = data == null ? S.current.calendarLoadFailed : null;
    });
  }

  void _gotoPrev() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1, 1);
    });
    _load();
  }

  void _gotoNext() {
    final now = DateTime.now();
    if (_viewMonth.year == now.year && _viewMonth.month == now.month) return;
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 1);
    });
    _load();
  }

  Future<void> _onResign() async {
    final data = _data;
    if (data == null) return;
    final result = await ResignDialog.show(
      context,
      currentPoints: data.gamblingPoints,
      cost: data.signCardCost,
    );
    if (!mounted) return;
    if (result?.success == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? YLColors.zinc900 : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return YLLargeTitleScaffold(
      title: s.calendarTitle,
      onRefresh: _load,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            YLSpacing.lg,
            0,
            YLSpacing.lg,
            YLSpacing.xl,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _MonthHeader(
                viewMonth: _viewMonth,
                onPrev: _gotoPrev,
                onNext: _gotoNext,
                isDark: isDark,
              ),
              const SizedBox(height: YLSpacing.md),
              Container(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(YLRadius.lg),
                  border: Border.all(color: border, width: 0.5),
                ),
                padding: const EdgeInsets.all(YLSpacing.md),
                child: _buildBody(isDark),
              ),
              const SizedBox(height: YLSpacing.md),
              _buildSummary(isDark, surface, border),
              const SizedBox(height: YLSpacing.lg),
              _buildActions(),
              const SizedBox(height: YLSpacing.md),
              _buildLegend(isDark),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            children: [
              Text(_error!, style: YLText.body),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: Text(S.current.calendarRetry),
              ),
            ],
          ),
        ),
      );
    }
    if (_data == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(S.current.calendarEmpty)),
      );
    }
    return SignCalendarWidget(data: _data!, isDark: isDark);
  }

  Widget _buildSummary(bool isDark, Color surface, Color border) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final signedDays = data.days.length;

    final s = S.current;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(color: border, width: 0.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              label: s.calendarStreakLabel,
              value: '${data.streak}',
              suffix: s.calendarUnit,
              color: const Color(0xFFEF4444),
            ),
          ),
          Container(width: 1, height: 36, color: border),
          Expanded(
            child: _StatTile(
              label: s.calendarSignedThisMonth,
              value: '$signedDays',
              suffix: s.calendarSuffixOf(total: '${data.daysInMonth}'),
            ),
          ),
          Container(width: 1, height: 36, color: border),
          Expanded(
            child: _StatTile(
              label: s.calendarMultiplier,
              value: '×${data.multiplier.toStringAsFixed(1)}'.replaceAll(
                RegExp(r'\.0$'),
                '',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();

    final s = S.current;
    final canResign = !data.todaySigned;

    return Row(
      children: [
        if (canResign) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _onResign,
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: Text(
                s.calendarBtnResignWithCost(cost: '${data.signCardCost}'),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(
              canResign ? s.calendarBtnClose : s.calendarBtnSignedToday,
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegend(bool isDark) {
    final s = S.current;
    final color = isDark ? YLColors.zinc400 : YLColors.zinc500;
    const amber = Color(0xFFF59E0B);
    const danger = Color(0xFFEF4444);
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children:
          <_LegendItem>[
                _LegendItem.icon(
                  icon: Icons.check_rounded,
                  color: YLColors.connected,
                  text: s.calendarLegendSigned,
                ),
                _LegendItem.icon(
                  icon: Icons.auto_awesome_rounded,
                  color: amber,
                  text: s.calendarLegendCard,
                ),
                _LegendItem.dot(color: danger, text: s.calendarLegendMissed),
                _LegendItem.ring(
                  color: danger,
                  text: s.calendarLegendTodayMiss,
                ),
                _LegendItem.muted(text: s.calendarLegendFuture, isDark: isDark),
              ]
              .map(
                (e) => DefaultTextStyle(
                  style: YLText.caption.copyWith(color: color, fontSize: 11),
                  child: e,
                ),
              )
              .toList(),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime viewMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool isDark;

  const _MonthHeader({
    required this.viewMonth,
    required this.onPrev,
    required this.onNext,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final now = DateTime.now();
    final isCurrent =
        viewMonth.year == now.year && viewMonth.month == now.month;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.calendarMonthLabel(
                year: '${viewMonth.year}',
                month: '${viewMonth.month}',
              ),
              style: YLText.titleLarge.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          _ChevronButton(
            icon: Icons.chevron_left_rounded,
            tooltip: s.calendarPrevMonth,
            onTap: onPrev,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _ChevronButton(
            icon: Icons.chevron_right_rounded,
            tooltip: s.calendarNextMonth,
            onTap: isCurrent ? null : onNext,
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

/// Compact chevron button — iOS 26-style soft-fill pill, ~32px square.
/// Disabled state drops opacity instead of returning null so layout
/// stays stable when the user pages to the latest month.
class _ChevronButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isDark;

  const _ChevronButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);
    final fg = isDark
        ? Colors.white.withValues(alpha: enabled ? 0.85 : 0.30)
        : Colors.black.withValues(alpha: enabled ? 0.75 : 0.25);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(YLRadius.md),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(YLRadius.md),
            ),
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;
  final Color? color;

  const _StatTile({
    required this.label,
    required this.value,
    this.suffix = '',
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: YLText.caption.copyWith(color: YLColors.zinc500)),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: YLText.titleLarge.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: color ?? YLColors.primary,
                ),
              ),
              if (suffix.isNotEmpty)
                TextSpan(
                  text: suffix,
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Legend chip — small swatch + label. Visual variants:
///   * [_LegendItem.icon]  — colored mini-icon (signed / resigned)
///   * [_LegendItem.dot]   — small filled dot (missed)
///   * [_LegendItem.ring]  — outlined ring (today)
///   * [_LegendItem.muted] — dim placeholder (future / out-of-month)
class _LegendItem extends StatelessWidget {
  final Widget swatch;
  final String text;
  const _LegendItem._({required this.swatch, required this.text});

  factory _LegendItem.icon({
    required IconData icon,
    required Color color,
    required String text,
  }) => _LegendItem._(
    swatch: Icon(icon, size: 11, color: color),
    text: text,
  );

  factory _LegendItem.dot({required Color color, required String text}) =>
      _LegendItem._(
        swatch: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
        ),
        text: text,
      );

  factory _LegendItem.ring({required Color color, required String text}) =>
      _LegendItem._(
        swatch: Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.55),
              width: 1.2,
            ),
          ),
        ),
        text: text,
      );

  factory _LegendItem.muted({required String text, required bool isDark}) =>
      _LegendItem._(
        swatch: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: isDark ? YLColors.zinc700 : YLColors.zinc300,
            shape: BoxShape.circle,
          ),
        ),
        text: text,
      );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 12, height: 12, child: Center(child: swatch)),
        const SizedBox(width: 5),
        Text(text),
      ],
    );
  }
}
