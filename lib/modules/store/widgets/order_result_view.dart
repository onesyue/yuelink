import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../i18n/app_strings.dart';
import '../../../domain/store/purchase_state.dart';
import '../../../theme.dart';
import '../purchase_notifier.dart';

/// Bottom sheet shown after checkout redirect — polls order status and
/// lets user check result or re-open the payment URL.
class OrderResultView extends ConsumerStatefulWidget {
  const OrderResultView({super.key, required this.initialState});

  final PurchaseState initialState;

  @override
  ConsumerState<OrderResultView> createState() => _OrderResultViewState();
}

class _OrderResultViewState extends ConsumerState<OrderResultView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Auto-poll when user returns from the browser after payment.
  /// The notifier's internal [_polling] flag is the authoritative guard;
  /// this check skips the call early to avoid even entering the notifier
  /// when a poll is visibly already running.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final ps = ref.read(purchaseProvider);
    if (ps is PurchasePolling) return; // Fix 2: poll already running
    if (ps is PurchaseAwaitingPayment) {
      ref.read(purchaseProvider.notifier).pollOrderResult(ps.tradeNo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.of(context);
    final isEn = s.isEn;
    final state = ref.watch(purchaseProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(YLRadius.xxl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: YLSpacing.lg,
            vertical: YLSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle ───────────────────────────────────────────
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: YLSpacing.lg),
                decoration: BoxDecoration(
                  color: isDark ? YLColors.zinc700 : YLColors.zinc200,
                  borderRadius: BorderRadius.circular(YLRadius.pill),
                ),
              ),

              _buildBody(context, state, isDark, isEn, s),

              const SizedBox(height: YLSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    PurchaseState state,
    bool isDark,
    bool isEn,
    S s,
  ) {
    if (state is PurchaseSuccess) {
      return _SuccessView(
        order: state,
        isDark: isDark,
        isEn: isEn,
        onDone: () {
          ref.read(purchaseProvider.notifier).reset();
          Navigator.pop(context);
        },
      );
    }

    if (state is PurchasePolling) {
      return _PollingView(state: state, isEn: isEn);
    }

    if (state is PurchaseFailed) {
      return _FailedView(
        state: state,
        isDark: isDark,
        isEn: isEn,
        onRetry: () {
          ref.read(purchaseProvider.notifier).reset();
          Navigator.pop(context);
        },
      );
    }

    // PurchaseAwaitingPayment — show payment link + poll button
    if (state is PurchaseAwaitingPayment) {
      return _AwaitingView(
        state: state,
        isDark: isDark,
        isEn: isEn,
        onPollNow: () =>
            ref.read(purchaseProvider.notifier).pollOrderResult(state.tradeNo),
        onCancel: () async {
          await ref.read(purchaseProvider.notifier).cancelCurrentOrder();
          if (context.mounted) Navigator.pop(context);
        },
      );
    }

    // Fallback loading
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: CircularProgressIndicator(),
    );
  }
}

// ── Success ───────────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.order,
    required this.isDark,
    required this.isEn,
    required this.onDone,
  });

  final PurchaseSuccess order;
  final bool isDark;
  final bool isEn;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 52,
          color: YLColors.connected,
        ),
        const SizedBox(height: YLSpacing.md),
        Text(
          isEn ? 'Payment Successful' : '购买成功',
          style: YLText.titleMedium.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          isEn ? 'Your subscription has been activated.' : '订阅已开通，同步后即可使用。',
          style: YLText.body.copyWith(color: YLColors.zinc500),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: YLSpacing.lg),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? Colors.white : YLColors.primary,
              foregroundColor: isDark ? YLColors.primary : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YLRadius.md),
              ),
            ),
            child: Text(
              isEn ? 'Done' : '完成',
              style: YLText.label.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Polling ───────────────────────────────────────────────────────────────────

class _PollingView extends StatelessWidget {
  const _PollingView({required this.state, required this.isEn});
  final PurchasePolling state;
  final bool isEn;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: YLSpacing.lg),
        const CircularProgressIndicator(),
        const SizedBox(height: YLSpacing.md),
        Text(
          isEn
              ? 'Checking payment status... (${state.attempt})'
              : '查询支付结果中... (${state.attempt})',
          style: YLText.body.copyWith(color: YLColors.zinc500),
        ),
        const SizedBox(height: YLSpacing.lg),
      ],
    );
  }
}

// ── Awaiting payment ──────────────────────────────────────────────────────────

class _AwaitingView extends StatelessWidget {
  const _AwaitingView({
    required this.state,
    required this.isDark,
    required this.isEn,
    required this.onPollNow,
    required this.onCancel,
  });

  final PurchaseAwaitingPayment state;
  final bool isDark;
  final bool isEn;
  final VoidCallback onPollNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.timer_rounded, size: 56, color: YLColors.zinc400),
        const SizedBox(height: YLSpacing.md),
        Text(
          isEn ? 'Awaiting Payment' : '等待支付',
          style: YLText.titleMedium.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          isEn
              ? 'Complete payment in browser, then tap Check Result.'
              : '请在浏览器中完成支付，支付后点击查询结果。',
          style: YLText.body.copyWith(color: YLColors.zinc500),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),

        // Trade No.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: YLSpacing.md),
          child: GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: state.tradeNo));
            },
            child: Text(
              'No. ${state.tradeNo}',
              style: YLText.caption.copyWith(
                color: YLColors.zinc400,
                decoration: TextDecoration.underline,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),

        const SizedBox(height: YLSpacing.sm),

        // Re-open payment URL
        if (state.paymentUrl.isNotEmpty)
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: () async {
                final uri = Uri.tryParse(state.paymentUrl);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? Colors.white : YLColors.primary,
                foregroundColor: isDark ? YLColors.primary : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YLRadius.md),
                ),
              ),
              child: Text(
                isEn ? 'Open Payment Page' : '重新打开支付页',
                style: YLText.label.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

        const SizedBox(height: 8),

        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton(
            onPressed: onPollNow,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YLRadius.md),
              ),
            ),
            child: Text(isEn ? 'Check Result' : '查询支付结果', style: YLText.label),
          ),
        ),

        const SizedBox(height: 8),

        TextButton(
          onPressed: onCancel,
          child: Text(
            isEn ? 'Cancel Order' : '取消订单',
            style: YLText.body.copyWith(color: YLColors.zinc400),
          ),
        ),
      ],
    );
  }
}

// ── Failed ────────────────────────────────────────────────────────────────────

class _FailedView extends StatelessWidget {
  const _FailedView({
    required this.state,
    required this.isDark,
    required this.isEn,
    required this.onRetry,
  });

  final PurchaseFailed state;
  final bool isDark;
  final bool isEn;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final detail = _failureDetail(state.kind, isEn);
    return Column(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 52,
          color: YLColors.error,
        ),
        const SizedBox(height: YLSpacing.md),
        Text(
          detail.title,
          style: YLText.titleMedium.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          state.message,
          style: YLText.body.copyWith(color: YLColors.zinc500),
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          detail.hint,
          style: YLText.caption.copyWith(
            color: isDark ? YLColors.zinc400 : YLColors.zinc500,
            height: 1.35,
          ),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        if (state.tradeNo != null) ...[
          const SizedBox(height: YLSpacing.md),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: state.tradeNo!));
            },
            child: Text(
              'No. ${state.tradeNo}',
              style: YLText.caption.copyWith(
                color: YLColors.zinc400,
                decoration: TextDecoration.underline,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const SizedBox(height: YLSpacing.lg),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? Colors.white : YLColors.primary,
              foregroundColor: isDark ? YLColors.primary : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YLRadius.md),
              ),
            ),
            child: Text(
              detail.actionLabel,
              style: YLText.label.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _FailureDetail {
  const _FailureDetail({
    required this.title,
    required this.hint,
    required this.actionLabel,
  });

  final String title;
  final String hint;
  final String actionLabel;
}

_FailureDetail _failureDetail(PurchaseFailureKind kind, bool isEn) {
  switch (kind) {
    case PurchaseFailureKind.loginRequired:
      return _FailureDetail(
        title: isEn ? 'Login Required' : '需要登录',
        hint: isEn
            ? 'Sign in again, then return to the store to continue checkout.'
            : '请重新登录后回到套餐中心继续购买。',
        actionLabel: isEn ? 'Back to Store' : '返回套餐中心',
      );
    case PurchaseFailureKind.paymentUrlMissing:
      return _FailureDetail(
        title: isEn ? 'Payment Link Missing' : '支付链接缺失',
        hint: isEn
            ? 'The server accepted the order but did not return a payable URL. Start a fresh order.'
            : '服务端创建了订单但未返回可支付链接，请重新发起订单。',
        actionLabel: isEn ? 'Create New Order' : '重新发起订单',
      );
    case PurchaseFailureKind.paymentPageOpenFailed:
      return _FailureDetail(
        title: isEn ? 'Cannot Open Payment' : '无法打开支付页',
        hint: isEn
            ? 'Check your browser permission or copy the order number for support.'
            : '请检查浏览器权限；如仍失败，可复制订单号联系支持。',
        actionLabel: isEn ? 'Try Again' : '重试',
      );
    case PurchaseFailureKind.orderCancelled:
      return _FailureDetail(
        title: isEn ? 'Order Cancelled' : '订单已取消',
        hint: isEn
            ? 'This order is closed. Pick a plan again if you still want to subscribe.'
            : '该订单已关闭，如需订阅请重新选择套餐。',
        actionLabel: isEn ? 'Back to Store' : '返回套餐中心',
      );
    case PurchaseFailureKind.network:
      return _FailureDetail(
        title: isEn ? 'Network Error' : '网络异常',
        hint: isEn
            ? 'The payment server could not be reached. Retry after your network is stable.'
            : '当前无法连接支付服务，请在网络稳定后重试。',
        actionLabel: isEn ? 'Back to Store' : '返回套餐中心',
      );
    case PurchaseFailureKind.unauthorized:
      return _FailureDetail(
        title: isEn ? 'Session Expired' : '登录已过期',
        hint: isEn
            ? 'Your account session expired. Sign in again before checkout.'
            : '账号登录状态已过期，请重新登录后再购买。',
        actionLabel: isEn ? 'Back to Store' : '返回套餐中心',
      );
    case PurchaseFailureKind.paymentDeclined:
    case PurchaseFailureKind.api:
      return _FailureDetail(
        title: isEn ? 'Payment Rejected' : '支付被拒绝',
        hint: isEn
            ? 'The payment provider rejected this checkout. A new order usually clears it.'
            : '支付通道拒绝了本次请求，通常重新发起订单即可恢复。',
        actionLabel: isEn ? 'Create New Order' : '重新发起订单',
      );
    case PurchaseFailureKind.state:
    case PurchaseFailureKind.unknown:
      return _FailureDetail(
        title: isEn ? 'Order Failed' : '订单失败',
        hint: isEn
            ? 'The checkout state is inconsistent. Return to the store and try again.'
            : '当前支付状态不完整，请返回套餐中心后重试。',
        actionLabel: isEn ? 'Back to Store' : '返回套餐中心',
      );
  }
}
