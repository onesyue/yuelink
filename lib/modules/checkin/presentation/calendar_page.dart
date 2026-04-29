import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/checkin/sign_calendar_entity.dart';
import '../../../infrastructure/checkin/checkin_repository.dart';
import '../../yue_auth/providers/yue_auth_providers.dart';
import '../../../theme.dart';
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
        _error = '请先登录';
      });
      return;
    }

    final monthStr =
        '${_viewMonth.year.toString().padLeft(4, '0')}-${_viewMonth.month.toString().padLeft(2, '0')}';
    final data = await CheckinRepository().fetchHistory(token, month: monthStr);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      _error = data == null ? '加载失败，下拉重试' : null;
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
    // 取积分：从已有 user_account / xboard 状态——这里简化，直接传 0 让用户感知"未知"
    // resign 后端会做最终积分校验，dialog 仅作 UX 提示。
    final result = await ResignDialog.show(context, currentPoints: data.streak * 0);
    if (!mounted) return;
    if (result?.success == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? YLColors.zinc950 : YLColors.zinc100;
    final surface = isDark ? YLColors.zinc900 : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('签到日历'),
        backgroundColor: bg,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // 月份切换
            _MonthHeader(
              viewMonth: _viewMonth,
              onPrev: _gotoPrev,
              onNext: _gotoNext,
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(YLRadius.lg),
                border: Border.all(color: border, width: 0.5),
              ),
              padding: const EdgeInsets.all(12),
              child: _buildBody(isDark),
            ),
            const SizedBox(height: 12),
            _buildSummary(isDark, surface, border),
            const SizedBox(height: 16),
            _buildActions(),
            const SizedBox(height: 12),
            _buildLegend(isDark),
          ],
        ),
      ),
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
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_data == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('暂无数据')),
      );
    }
    return SignCalendarWidget(data: _data!, isDark: isDark);
  }

  Widget _buildSummary(bool isDark, Color surface, Color border) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final signedDays = data.days.length;

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
              label: '连续签到',
              value: '${data.streak}',
              suffix: '天',
              color: const Color(0xFFEF4444),
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: border,
          ),
          Expanded(
            child: _StatTile(
              label: '本月已签',
              value: '$signedDays',
              suffix: '/${data.daysInMonth}',
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: border,
          ),
          Expanded(
            child: _StatTile(
              label: '加成',
              value: '×${data.multiplier.toStringAsFixed(1)}'
                  .replaceAll(RegExp(r'\.0$'), ''),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();

    final canResign = !data.todaySigned;

    return Row(
      children: [
        if (canResign) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _onResign,
              icon: const Icon(Icons.replay_outlined, size: 18),
              label: const Text('用 25 积分补昨天'),
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
            label: Text(canResign ? '关闭' : '已签到'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegend(bool isDark) {
    final color = isDark ? YLColors.zinc400 : YLColors.zinc500;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: const [
        _LegendItem(emoji: '✅', text: '已签'),
        _LegendItem(emoji: '⭐', text: '补签'),
        _LegendItem(emoji: '⛔', text: '断签'),
        _LegendItem(emoji: '🔴', text: '今天未签'),
        _LegendItem(emoji: '⏳', text: '未来'),
      ].map((e) => DefaultTextStyle(
            style: YLText.caption.copyWith(color: color),
            child: e,
          )).toList(),
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
    final now = DateTime.now();
    final isCurrent =
        viewMonth.year == now.year && viewMonth.month == now.month;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: '上个月',
        ),
        Text(
          '${viewMonth.year} 年 ${viewMonth.month} 月',
          style: YLText.titleLarge.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        IconButton(
          onPressed: isCurrent ? null : onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: '下个月',
        ),
      ],
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
        Text(
          label,
          style: YLText.caption.copyWith(color: YLColors.zinc500),
        ),
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

class _LegendItem extends StatelessWidget {
  final String emoji;
  final String text;
  const _LegendItem({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }
}
