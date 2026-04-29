import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/checkin/sign_calendar_entity.dart';
import '../../../infrastructure/checkin/checkin_repository.dart';
import '../../../shared/app_notifier.dart';
import '../../yue_auth/providers/yue_auth_providers.dart';
import '../../../theme.dart';

const int kSignCardCost = 25;

/// 补签卡确认弹窗。在用户从日历卡片点「⭐ 用 25 积分补昨天」时弹出。
/// 显示价格 + 当前积分（若可获取）+ 二次确认按钮。
class ResignDialog extends ConsumerStatefulWidget {
  final int currentPoints;
  final void Function(ResignResult)? onResult;

  const ResignDialog({
    super.key,
    required this.currentPoints,
    this.onResult,
  });

  static Future<ResignResult?> show(
    BuildContext context, {
    required int currentPoints,
  }) async {
    return await showDialog<ResignResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ResignDialog(currentPoints: currentPoints),
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
      AppNotifier.warning('请先登录');
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final repo = CheckinRepository();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canAfford = widget.currentPoints >= kSignCardCost;

    return AlertDialog(
      title: const Text('补签卡'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('用 25 积分补回昨天的签到，连签不归零。', style: YLText.body),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Text('当前积分：', style: YLText.caption),
                Text(
                  '${widget.currentPoints}',
                  style: YLText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: canAfford ? null : const Color(0xFFEF4444),
                  ),
                ),
                const Spacer(),
                const Text('需要：25 积分', style: YLText.caption),
              ],
            ),
          ),
          if (!canAfford) ...[
            const SizedBox(height: 8),
            const Text(
              '积分不足，可以参加群里竞猜或每日签到攒积分',
              style: YLText.caption,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading || !canAfford ? null : _confirm,
          child: _loading
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('补签'),
        ),
      ],
    );
  }
}
