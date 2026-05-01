import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/store/purchase_state.dart';
import '../../../domain/store/store_order.dart';
import '../../../infrastructure/store/plan_period_mapping.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/friendly_error.dart';
import '../../../theme.dart';
import '../purchase_notifier.dart';
import '../store_providers.dart';
import 'order_result_view.dart';
import 'payment_method_selector.dart';

class OrderDetailSheet extends ConsumerStatefulWidget {
  const OrderDetailSheet({
    super.key,
    required this.order,
    required this.isDark,
    required this.isEn,
  });

  final StoreOrder order;
  final bool isDark;
  final bool isEn;

  @override
  ConsumerState<OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends ConsumerState<OrderDetailSheet> {
  bool _cancelling = false;
  bool _paying = false;
  int? _selectedMethodId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final methods = ref.read(paymentMethodsProvider).value;
      if (methods != null && methods.isNotEmpty) {
        setState(() => _selectedMethodId = methods.first.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isDark = widget.isDark;
    final isEn = widget.isEn;
    final dateStr = _formatDateTime(order.createdDate);

    ref.listen(purchaseProvider, (_, next) {
      if (next is PurchaseAwaitingPayment || next is PurchaseSuccess) {
        if (mounted) Navigator.pop(context);
        _showResultView(context, next);
      }
      if (next is PurchaseFailed) {
        if (mounted) setState(() => _paying = false);
        AppNotifier.error(next.message);
      }
    });

    ref.listen(paymentMethodsProvider, (_, next) {
      final methods = next.value;
      if (methods != null && methods.isNotEmpty && _selectedMethodId == null) {
        if (mounted) setState(() => _selectedMethodId = methods.first.id);
      }
    });

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(YLRadius.xl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: YLSpacing.lg,
            vertical: YLSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: YLSpacing.md),
                  decoration: BoxDecoration(
                    color: isDark ? YLColors.zinc700 : YLColors.zinc200,
                    borderRadius: BorderRadius.circular(YLRadius.pill),
                  ),
                ),
              ),
              Text(
                isEn ? 'Order Detail' : '订单详情',
                style: YLText.titleMedium.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: YLSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(YLSpacing.sm),
                decoration: BoxDecoration(
                  color: isDark ? YLColors.zinc800 : YLColors.zinc50,
                  borderRadius: BorderRadius.circular(YLRadius.lg),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: isEn ? 'Plan' : '套餐',
                      value: order.planName ?? '-',
                      isDark: isDark,
                    ),
                    _Divider(isDark: isDark),
                    _DetailRow(
                      label: isEn ? 'Period' : '周期',
                      value: _periodLabel(order.period, isEn),
                      isDark: isDark,
                    ),
                    _Divider(isDark: isDark),
                    _DetailRow(
                      label: isEn ? 'Amount' : '金额',
                      value: order.formattedAmount,
                      isDark: isDark,
                      valueStyle: YLText.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : YLColors.zinc900,
                      ),
                    ),
                    _Divider(isDark: isDark),
                    _DetailRow(
                      label: isEn ? 'Status' : '状态',
                      value: _statusLabel(order.status, isEn),
                      isDark: isDark,
                      valueStyle: YLText.body.copyWith(
                        fontSize: 14,
                        color: _statusColor(order.status),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (order.couponCode != null) ...[
                      _Divider(isDark: isDark),
                      _DetailRow(
                        label: isEn ? 'Coupon' : '优惠码',
                        value: order.couponCode!,
                        isDark: isDark,
                      ),
                    ],
                    _Divider(isDark: isDark),
                    _DetailRow(
                      label: isEn ? 'Date' : '下单时间',
                      value: dateStr,
                      isDark: isDark,
                    ),
                    _Divider(isDark: isDark),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: order.tradeNo));
                        AppNotifier.info(isEn ? 'Copied' : '已复制到剪贴板');
                      },
                      child: _DetailRow(
                        label: isEn ? 'Order No.' : '订单号',
                        value: order.tradeNo,
                        isDark: isDark,
                        valueStyle: YLText.caption.copyWith(
                          color: YLColors.zinc400,
                          decoration: TextDecoration.underline,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        oneline: false,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: YLSpacing.md),
              if (order.status == OrderStatus.pending) ...[
                PaymentMethodSelector(
                  selectedId: _selectedMethodId,
                  onChanged: (id) => setState(() => _selectedMethodId = id),
                  orderAmountFen: order.totalAmount,
                ),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    onPressed: (_paying || _cancelling) ? null : _payNow,
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : YLColors.primary,
                      foregroundColor: isDark ? YLColors.primary : Colors.white,
                      disabledBackgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.3)
                          : YLColors.zinc300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YLRadius.md),
                      ),
                    ),
                    child: _paying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            isEn ? 'Pay Now' : '立即支付',
                            style: YLText.label.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton(
                    onPressed: (_cancelling || _paying) ? null : _cancelOrder,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: YLColors.error,
                      side: const BorderSide(color: YLColors.error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YLRadius.md),
                      ),
                    ),
                    child: _cancelling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            isEn ? 'Cancel Order' : '取消订单',
                            style: YLText.label,
                          ),
                  ),
                ),
              ],
              const SizedBox(height: YLSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _payNow() async {
    setState(() => _paying = true);
    ref
        .read(purchaseProvider.notifier)
        .payExistingOrder(
          tradeNo: widget.order.tradeNo,
          methodId: _selectedMethodId,
        );
  }

  Future<void> _cancelOrder() async {
    setState(() => _cancelling = true);
    try {
      await ref
          .read(purchaseProvider.notifier)
          .cancelOrderFromHistory(widget.order.tradeNo);
      if (mounted) {
        Navigator.pop(context);
        AppNotifier.success(widget.isEn ? 'Order cancelled' : '订单已取消');
      }
    } catch (e) {
      if (mounted) AppNotifier.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _showResultView(BuildContext context, PurchaseState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => OrderResultView(initialState: state),
    );
  }

  Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.completed:
      case OrderStatus.discounted:
        return YLColors.connected;
      case OrderStatus.pending:
      case OrderStatus.processing:
        return YLColors.connecting;
      case OrderStatus.cancelled:
        return YLColors.zinc400;
    }
  }

  String _statusLabel(OrderStatus s, bool isEn) {
    switch (s) {
      case OrderStatus.pending:
        return isEn ? 'Pending' : '待支付';
      case OrderStatus.processing:
        return isEn ? 'Processing' : '处理中';
      case OrderStatus.cancelled:
        return isEn ? 'Cancelled' : '已取消';
      case OrderStatus.completed:
      case OrderStatus.discounted:
        return isEn ? 'Completed' : '已完成';
    }
  }

  String _periodLabel(String apiKey, bool isEn) {
    return planPeriodLabelFromApiKey(apiKey, isEn: isEn);
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.isDark,
    this.valueStyle,
    this.oneline = true,
  });

  final String label;
  final String value;
  final bool isDark;
  final TextStyle? valueStyle;
  final bool oneline;

  @override
  Widget build(BuildContext context) {
    final valStyle =
        valueStyle ??
        YLText.rowTitle.copyWith(
          color: isDark ? YLColors.zinc200 : YLColors.zinc800,
        );

    if (oneline) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: YLText.rowSubtitle.copyWith(color: YLColors.zinc500),
            ),
            const SizedBox(width: YLSpacing.md),
            Flexible(
              child: Text(
                value,
                style: valStyle,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: YLText.rowSubtitle.copyWith(color: YLColors.zinc500),
          ),
          const SizedBox(height: 2),
          SelectableText(value, style: valStyle),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.06),
    );
  }
}
