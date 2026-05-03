import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_strings.dart';
import '../../shared/widgets/yl_scaffold.dart';
import '../../theme.dart';
import '../../domain/store/store_error.dart';
import '../../domain/store/store_order.dart';
import '../../infrastructure/store/plan_period_mapping.dart';
import 'store_providers.dart';
import 'widgets/order_detail_sheet.dart';

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
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(orderHistoryProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.of(context);
    final isEn = s.isEn;
    final ordersAsync = ref.watch(orderHistoryProvider);

    return YLLargeTitleScaffold(
      title: isEn ? 'Order History' : '订单记录',
      maxContentWidth: kYLSecondaryContentWidth,
      onRefresh: () => ref.read(orderHistoryProvider.notifier).refresh(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, size: 22),
          tooltip: isEn ? 'Refresh' : '刷新',
          onPressed: () => ref.read(orderHistoryProvider.notifier).refresh(),
        ),
      ],
      slivers: [
        ordersAsync.when(
          loading: () => const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: _ErrorView(
              message: err is StoreError ? err.message : err.toString(),
              onRetry: () => ref.read(orderHistoryProvider.notifier).refresh(),
              isEn: isEn,
            ),
          ),
          data: (orders) {
            if (orders.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyView(isEn: isEn),
              );
            }
            final notifier = ref.read(orderHistoryProvider.notifier);
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                YLSpacing.lg,
                YLSpacing.sm,
                YLSpacing.lg,
                0,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  if (i == orders.length) {
                    return _LoadMoreFooter(notifier: notifier, isEn: isEn);
                  }
                  final order = orders[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: YLSpacing.sm),
                    child: _OrderItem(
                      order: order,
                      isDark: isDark,
                      isEn: isEn,
                      onTap: () => _showDetail(context, order, isDark, isEn),
                    ),
                  );
                }, childCount: orders.length + 1),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showDetail(
    BuildContext context,
    StoreOrder order,
    bool isDark,
    bool isEn,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          OrderDetailSheet(order: order, isDark: isDark, isEn: isEn),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YLRadius.lg),
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
                      style: YLText.rowTitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_periodLabel(order.period, isEn)} · $dateStr',
                      style: YLText.rowSubtitle.copyWith(
                        color: YLColors.zinc500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                    style: YLText.rowTitle.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  _OrderStatusBadge(
                    label: _statusLabel(order.status, isEn),
                    color: statusColor,
                  ),
                ],
              ),

              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: YLColors.zinc400,
              ),
            ],
          ),
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
    return planPeriodLabelFromApiKey(apiKey, isEn: isEn);
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _OrderStatusBadge extends StatelessWidget {
  const _OrderStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(YLRadius.pill),
      ),
      child: Text(
        label,
        style: YLText.badge.copyWith(color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
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
        setState(
          () => _errorMsg = widget.isEn
              ? 'Failed to load, tap to retry'
              : '加载失败，点击重试',
        );
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
                  _errorMsg ?? (widget.isEn ? 'Load More' : '加载更多'),
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
          const Icon(
            Icons.receipt_long_rounded,
            size: 48,
            color: YLColors.zinc300,
          ),
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
          const Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: YLColors.zinc300,
          ),
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
