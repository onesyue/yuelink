import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/datasources/xboard_api.dart';
import '../../l10n/app_strings.dart';
import '../../shared/app_notifier.dart';
import '../../theme.dart';
import '../../domain/store/store_order.dart';
import '../../domain/store/store_plan.dart';
import 'store_providers.dart';
import 'widgets/order_result_view.dart';
import 'widgets/payment_method_selector.dart';

/// Full-page order history for YueLink.
class OrderHistoryPage extends ConsumerStatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  ConsumerState<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends ConsumerState<OrderHistoryPage>
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(orderHistoryProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.of(context);
    final isEn = s.isEn;
    final ordersAsync = ref.watch(orderHistoryProvider);

    return Scaffold(
      backgroundColor: isDark ? YLColors.bgDark : YLColors.bgLight,
      appBar: AppBar(
        backgroundColor: isDark ? YLColors.bgDark : YLColors.bgLight,
        elevation: 0,
        leading: Navigator.canPop(context) ? const BackButton() : null,
        automaticallyImplyLeading: false,
        title: Text(
          isEn ? 'Order History' : '订单记录',
          style: YLText.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: YLColors.zinc500,
            onPressed: () =>
                ref.read(orderHistoryProvider.notifier).refresh(),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err is XBoardApiException ? err.message : err.toString(),
          onRetry: () =>
              ref.read(orderHistoryProvider.notifier).refresh(),
          isEn: isEn,
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return _EmptyView(isEn: isEn);
          }
          final notifier = ref.read(orderHistoryProvider.notifier);
          return RefreshIndicator(
            onRefresh: notifier.refresh,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: YLSpacing.md, vertical: YLSpacing.sm),
              itemCount: orders.length + 1, // +1 for load-more footer
              itemBuilder: (context, i) {
                if (i == orders.length) {
                  return _LoadMoreFooter(
                    notifier: notifier,
                    isEn: isEn,
                  );
                }
                final order = orders[i];
                return Padding(
                  padding:
                      const EdgeInsets.only(bottom: YLSpacing.sm),
                  child: _OrderItem(
                    order: order,
                    isDark: isDark,
                    isEn: isEn,
                    onTap: () => _showDetail(context, order, isDark, isEn),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showDetail(
      BuildContext context, StoreOrder order, bool isDark, bool isEn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderDetailSheet(
          order: order, isDark: isDark, isEn: isEn),
    );
  }
}

// ── Order list item ───────────────────────────────────────────────────────────

class _OrderItem extends StatelessWidget {
  const _OrderItem({
    required this.order,
    required this.isDark,
    required this.isEn,
    required this.onTap,
  });

  final StoreOrder order;
  final bool isDark;
  final bool isEn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(order.status);
    final dateStr = _formatDate(order.createdDate);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(YLSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc800 : Colors.white,
          borderRadius: BorderRadius.circular(YLRadius.lg),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
            width: 0.5,
          ),
          boxShadow: YLShadow.card(context),
        ),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),

            // Plan + period
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.planName ?? (isEn ? 'Plan' : '套餐'),
                    style: YLText.body
                        .copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_periodLabel(order.period, isEn)} · $dateStr',
                    style: YLText.caption
                        .copyWith(color: YLColors.zinc500),
                  ),
                ],
              ),
            ),

            // Amount + status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  order.formattedAmount,
                  style: YLText.body
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusLabel(order.status, isEn),
                  style: YLText.caption.copyWith(color: statusColor),
                ),
              ],
            ),

            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 16, color: YLColors.zinc400),
          ],
        ),
      ),
    );
  }

  Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.completed:
      case OrderStatus.discounted:
        return YLColors.connected;
      case OrderStatus.pending:
        return YLColors.connecting;
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
    for (final p in PlanPeriod.values) {
      if (p.apiKey == apiKey) return p.label(isEn);
    }
    return apiKey;
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ── Load more footer ──────────────────────────────────────────────────────────

class _LoadMoreFooter extends StatefulWidget {
  const _LoadMoreFooter({required this.notifier, required this.isEn});
  final OrderHistoryNotifier notifier;
  final bool isEn;

  @override
  State<_LoadMoreFooter> createState() => _LoadMoreFooterState();
}

class _LoadMoreFooterState extends State<_LoadMoreFooter> {
  bool _loading = false;
  // Non-null when the last loadMore() call threw an exception.
  // Reset to null on the next attempt so the user can retry cleanly.
  String? _errorMsg;

  Future<void> _doLoadMore() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      await widget.notifier.loadMore();
    } catch (_) {
      // loadMore() rethrows on network / server error.
      // Show a friendly message; _hasMore is unchanged so the user can retry.
      if (mounted) {
        setState(() => _errorMsg =
            widget.isEn ? 'Failed to load, tap to retry' : '加载失败，点击重试');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.notifier.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: YLSpacing.lg),
        child: Center(
          child: Text(
            widget.isEn ? 'All orders loaded' : '已加载全部订单',
            style: YLText.caption.copyWith(color: YLColors.zinc400),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: YLSpacing.md),
      child: Center(
        child: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: _doLoadMore,
                child: Text(
                  _errorMsg ??
                      (widget.isEn ? 'Load More' : '加载更多'),
                  style: YLText.caption.copyWith(
                    color: _errorMsg != null
                        ? YLColors.error
                        : YLColors.zinc400,
                  ),
                ),
              ),
      ),
    );
  }
}

// ── Order detail sheet ────────────────────────────────────────────────────────

class _OrderDetailSheet extends ConsumerStatefulWidget {
  const _OrderDetailSheet({
    required this.order,
    required this.isDark,
    required this.isEn,
  });
  final StoreOrder order;
  final bool isDark;
  final bool isEn;

  @override
  ConsumerState<_OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends ConsumerState<_OrderDetailSheet> {
  bool _cancelling = false;
  bool _paying = false;
  int? _selectedMethodId;

  @override
  void initState() {
    super.initState();
    // Pre-select first payment method when available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final methods = ref.read(paymentMethodsProvider).valueOrNull;
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

    // Navigate to result view when checkout is initiated from this sheet
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

    // Auto-select first method when payment methods load
    ref.listen(paymentMethodsProvider, (_, next) {
      final methods = next.valueOrNull;
      if (methods != null && methods.isNotEmpty && _selectedMethodId == null) {
        if (mounted) setState(() => _selectedMethodId = methods.first.id);
      }
    });

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
              horizontal: YLSpacing.lg, vertical: YLSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
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
                style:
                    YLText.titleMedium.copyWith(fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: YLSpacing.lg),

              // Detail card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(YLSpacing.md),
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
                    // Trade No. (copyable)
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: order.tradeNo));
                        AppNotifier.info(
                            isEn ? 'Copied' : '已复制到剪贴板');
                      },
                      child: _DetailRow(
                        label: isEn ? 'Order No.' : '订单号',
                        value: order.tradeNo,
                        isDark: isDark,
                        valueStyle: YLText.caption.copyWith(
                          color: YLColors.zinc400,
                          decoration: TextDecoration.underline,
                        ),
                        oneline: false,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: YLSpacing.lg),

              // Pending order actions: payment method + Pay Now + Cancel
              if (order.status == OrderStatus.pending) ...[
                PaymentMethodSelector(
                  selectedId: _selectedMethodId,
                  onChanged: (id) => setState(() => _selectedMethodId = id),
                  orderAmountFen: order.totalAmount,
                ),

                // Pay Now (primary)
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: (_paying || _cancelling) ? null : _payNow,
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : YLColors.primary,
                      foregroundColor:
                          isDark ? YLColors.primary : Colors.white,
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
                            style:
                                YLText.label.copyWith(fontWeight: FontWeight.w600),
                          ),
                  ),
                ),

                const SizedBox(height: 8),

                // Cancel Order (secondary)
                SizedBox(
                  width: double.infinity,
                  height: 42,
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
    ref.read(purchaseProvider.notifier).payExistingOrder(
      tradeNo: widget.order.tradeNo,
      methodId: _selectedMethodId,
    );
    // State will be updated via ref.listen — _paying cleared on PurchaseFailed
    // or on navigation away for success/awaiting states.
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

  Future<void> _cancelOrder() async {
    setState(() => _cancelling = true);
    try {
      final repo = ref.read(storeRepositoryProvider);
      await repo?.cancelOrder(widget.order.tradeNo);
      if (mounted) {
        Navigator.pop(context);
        AppNotifier.success(widget.isEn ? 'Order cancelled' : '订单已取消');
        ref.read(orderHistoryProvider.notifier).refresh();
      }
    } on XBoardApiException catch (e) {
      if (mounted) AppNotifier.error(e.message);
    } catch (_) {
      if (mounted) {
        AppNotifier.error(
          widget.isEn ? 'Failed to cancel, please try again' : '取消订单失败，请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
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
    for (final p in PlanPeriod.values) {
      if (p.apiKey == apiKey) return p.label(isEn);
    }
    return apiKey;
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Shared detail row ─────────────────────────────────────────────────────────

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
    final valStyle = valueStyle ??
        YLText.body.copyWith(
            color: isDark ? YLColors.zinc200 : YLColors.zinc800);

    if (oneline) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: YLText.body.copyWith(color: YLColors.zinc500)),
            Flexible(
              child: Text(value, style: valStyle, textAlign: TextAlign.end),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: YLText.body.copyWith(color: YLColors.zinc500)),
          const SizedBox(height: 2),
          Text(value, style: valStyle),
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

// ── Empty / Error states ──────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.isEn});
  final bool isEn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 48, color: YLColors.zinc300),
          const SizedBox(height: YLSpacing.md),
          Text(
            isEn ? 'No orders yet' : '暂无订单记录',
            style: YLText.body.copyWith(color: YLColors.zinc500),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.isEn,
  });
  final String message;
  final VoidCallback onRetry;
  final bool isEn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: YLColors.zinc300),
          const SizedBox(height: YLSpacing.md),
          Text(
            isEn ? 'Failed to load orders' : '订单加载失败',
            style: YLText.body.copyWith(color: YLColors.zinc500),
          ),
          const SizedBox(height: YLSpacing.sm),
          Text(
            message,
            style: YLText.caption.copyWith(color: YLColors.zinc400),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: YLSpacing.lg),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text(isEn ? 'Retry' : '重试'),
          ),
        ],
      ),
    );
  }
}
