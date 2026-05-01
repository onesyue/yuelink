import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/checkin/sign_calendar_entity.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../yue_auth/providers/yue_auth_providers.dart';
import '../providers/checkin_provider.dart';
import '../../../theme.dart';

/// 补签卡确认弹窗。在用户从日历卡片点「⭐ 用 X 积分补昨天」时弹出。
/// 显示价格 + 当前积分 + 二次确认按钮。积分和价格由 caller 从 calendar
/// 数据传入（`SignCalendarMonth.gamblingPoints` / `signCardCost`）。
class ResignDialog extends ConsumerStatefulWidget {
  final int currentPoints;
  final int cost;
  final void Function(ResignResult)? onResult;

  const ResignDialog({
    super.key,
    required this.currentPoints,
    required this.cost,
    this.onResult,
  });

  static Future<ResignResult?> show(
    BuildContext context, {
    required int currentPoints,
    int cost = 25,
  }) async {
    return await showDialog<ResignResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ResignDialog(currentPoints: currentPoints, cost: cost),
    );
  }

  @override
  ConsumerState<ResignDialog> createState() => _ResignDialogState();
}

class _ResignDialogState extends ConsumerState<ResignDialog> {
  bool _loading = false;

  Future<void> _confirm() async {
    if (_loading) return;
    setState(() => _loading = true);

    final token = ref.read(authProvider).token;
    if (token == null || token.isEmpty) {
      AppNotifier.warning(S.current.calendarPleaseLogin);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // 走 provider 拿 mihomo-proxy-aware 实例（与 checkin / fetchHistory 一致），
    // 直接 new 在中国境内会被 GFW 拦死 yue.yuebao.website 导致永远 loading。
    final repo = ref.read(checkinRepositoryProvider);
    final result = await repo.resign(token);
    if (!mounted) return;

    if (result.success) {
      AppNotifier.info(result.message);
    } else {
      AppNotifier.warning(result.message);
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canAfford = widget.currentPoints >= widget.cost;

    return AlertDialog(
      title: Text(s.resignTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.resignDesc(cost: '${widget.cost}'), style: YLText.body),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(YLRadius.md),
            ),
            child: Row(
              children: [
                Text(s.resignCurrentPoints, style: YLText.caption),
                Text(
                  '${widget.currentPoints}',
                  style: YLText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: canAfford ? null : const Color(0xFFEF4444),
                  ),
                ),
                const Spacer(),
                Text(s.resignNeedPoints(cost: '${widget.cost}'),
                    style: YLText.caption),
              ],
            ),
          ),
          if (!canAfford) ...[
            const SizedBox(height: 8),
            Text(s.resignInsufficient, style: YLText.caption),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(s.resignCancel),
        ),
        FilledButton(
          onPressed: _loading || !canAfford ? null : _confirm,
          child: _loading
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(s.resignConfirm),
        ),
      ],
    );
  }
}
