import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/datasources/xboard_api.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';
import '../../../domain/store/coupon_result.dart';
import '../../../domain/store/store_plan.dart';
import '../store_providers.dart';
import 'order_result_view.dart';
import 'payment_method_selector.dart';

/// Confirmation sheet before placing an order.
/// Handles coupon input, payment method selection, and checkout initiation.
class PurchaseConfirmSheet extends ConsumerStatefulWidget {
  const PurchaseConfirmSheet({
    super.key,
    required this.plan,
    required this.period,
  });

  final StorePlan plan;
  final PlanPeriod period;

  @override
  ConsumerState<PurchaseConfirmSheet> createState() =>
      _PurchaseConfirmSheetState();
}

class _PurchaseConfirmSheetState extends ConsumerState<PurchaseConfirmSheet> {
  final _couponController = TextEditingController();

  CouponResult? _couponResult;
  bool _couponLoading = false;
  String? _couponError;
  bool _couponExpanded = false;

  int? _selectedMethodId;

  @override
  void initState() {
    super.initState();
    // Auto-select first payment method when available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final methods = ref.read(paymentMethodsProvider).valueOrNull;
      if (mounted && methods != null && methods.isNotEmpty) {
        setState(() => _selectedMethodId = methods.first.id);
      }
    });
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  int get _originalFen =>
      widget.plan.priceForPeriod(widget.period) ?? 0;

  int get _discountFen => _couponResult?.discountFor(_originalFen) ?? 0;

  int get _finalFen => (_originalFen - _discountFen).clamp(0, _originalFen);

  String _formatFen(int fen) {
    if (fen == 0) return '免费';
    final yuan = fen / 100.0;
    return '¥${yuan.toStringAsFixed(yuan == yuan.truncate() ? 0 : 2)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.of(context);
    final isEn = s.isEn;

    final purchaseState = ref.watch(purchaseProvider);
    final loadingState =
        purchaseState is PurchaseLoading ? purchaseState : null;
    // Also treat PurchasePolling as loading: free-plan fallback runs
    // pollOrderResult() inside purchase(), which sets PurchasePolling
    // while the confirm sheet is still visible. Without this, the submit
    // button re-enables and the duplicate-submit guard is bypassed.
    final isLoading = loadingState != null || purchaseState is PurchasePolling;

    // Navigate to result view when payment URL is ready.
    // Capture navigator before pop — after pop, this widget's context is invalid.
    ref.listen(purchaseProvider, (_, next) {
      if (next is PurchaseAwaitingPayment || next is PurchaseSuccess) {
        final nav = Navigator.of(context);
        nav.pop();
        // Use the navigator's overlay context (still valid after pop)
        if (nav.context.mounted) {
          _showResultView(nav.context, next);
        }
      }
      if (next is PurchaseFailed) {
        AppNotifier.error(next.message);
      }
    });

    // Auto-select first method when methods load
    ref.listen(paymentMethodsProvider, (_, next) {
      final methods = next.valueOrNull;
      if (methods != null && methods.isNotEmpty && _selectedMethodId == null) {
        setState(() => _selectedMethodId = methods.first.id);
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
              // ── Handle ──────────────────────────────────────────
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
                isEn ? 'Confirm Order' : '确认订单',
                style: YLText.titleMedium.copyWith(fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: YLSpacing.lg),

              // ── Order summary card ───────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(YLSpacing.md),
                decoration: BoxDecoration(
                  color: isDark ? YLColors.zinc800 : YLColors.zinc50,
                  borderRadius: BorderRadius.circular(YLRadius.lg),
                ),
                child: Column(
                  children: [
                    _Row(
                      label: isEn ? 'Plan' : '套餐',
                      value: widget.plan.name,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 10),
                    _Row(
                      label: isEn ? 'Period' : '周期',
                      value: widget.period.label(isEn),
                      isDark: isDark,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 0.5),
                    ),
                    // Show original price + discount lines if coupon applied
                    if (_couponResult != null) ...[
                      _Row(
                        label: isEn ? 'Original' : '原价',
                        value: _formatFen(_originalFen),
                        isDark: isDark,
                        valueStyle: YLText.body.copyWith(
                          color: YLColors.zinc400,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _Row(
                        label: isEn ? 'Discount' : '优惠',
                        value: '-${_formatFen(_discountFen)}',
                        isDark: isDark,
                        valueStyle: YLText.body
                            .copyWith(color: YLColors.connected),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _Row(
                      label: _couponResult != null
                          ? (isEn ? 'You Pay' : '实付')
                          : (isEn ? 'Total' : '合计'),
                      value: _formatFen(_finalFen),
                      isDark: isDark,
                      valueStyle: YLText.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : YLColors.zinc900,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: YLSpacing.md),

              // ── Coupon input ─────────────────────────────────────
              _CouponSection(
                controller: _couponController,
                couponResult: _couponResult,
                isLoading: _couponLoading,
                error: _couponError,
                expanded: _couponExpanded,
                isDark: isDark,
                isEn: isEn,
                onToggle: () => setState(() {
                  _couponExpanded = !_couponExpanded;
                  if (!_couponExpanded) {
                    _couponController.clear();
                    _couponResult = null;
                    _couponError = null;
                  }
                }),
                onValidate: _validateCoupon,
                onRemove: () => setState(() {
                  _couponController.clear();
                  _couponResult = null;
                  _couponError = null;
                }),
              ),

              const SizedBox(height: YLSpacing.sm),

              // ── Payment method selector ──────────────────────────
              PaymentMethodSelector(
                selectedId: _selectedMethodId,
                onChanged: (id) => setState(() => _selectedMethodId = id),
                orderAmountFen: _finalFen,
              ),

              // ── Loading message ──────────────────────────────────
              if (isLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        loadingState?.message ?? (isEn ? 'Checking...' : '查询中...'),
                        style:
                            YLText.caption.copyWith(color: YLColors.zinc500),
                      ),
                    ],
                  ),
                ),

              // ── Pay button ───────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: isLoading
                      ? null
                      : () => ref.read(purchaseProvider.notifier).purchase(
                            planId: widget.plan.id,
                            period: widget.period,
                            couponCode: _couponResult != null
                                ? _couponController.text.trim()
                                : null,
                            methodId: _selectedMethodId,
                          ),
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
                  child: Text(
                    isEn ? 'Pay Now' : '前往支付',
                    style: YLText.label.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ── Cancel button ────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          ref.read(purchaseProvider.notifier).reset();
                          Navigator.pop(context);
                        },
                  child: Text(
                    s.cancel,
                    style: YLText.body.copyWith(color: YLColors.zinc500),
                  ),
                ),
              ),

              const SizedBox(height: YLSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _validateCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _couponLoading = true;
      _couponError = null;
      _couponResult = null;
    });

    try {
      final repo = ref.read(storeRepositoryProvider);
      if (repo == null) throw Exception('未登录');
      final result = await repo.checkCoupon(code, widget.plan.id);
      if (mounted) {
        setState(() {
          _couponResult = result;
          _couponLoading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _couponError = _friendlyError(e);
          _couponLoading = false;
        });
      }
    }
  }

  String _friendlyError(Exception e) {
    if (e is XBoardApiException) return e.message;
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('HandshakeException') ||
        s.contains('HttpException')) {
      final isEn = S.of(context).isEn;
      return isEn ? 'Network error, please try again' : '网络异常，请重试';
    }
    if (s.contains('TimeoutException')) {
      final isEn = S.of(context).isEn;
      return isEn ? 'Request timed out, please try again' : '请求超时，请重试';
    }
    return s.startsWith('Exception: ') ? s.substring(11) : s;
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
}

// ── Coupon section ────────────────────────────────────────────────────────────

class _CouponSection extends StatelessWidget {
  const _CouponSection({
    required this.controller,
    required this.couponResult,
    required this.isLoading,
    required this.error,
    required this.expanded,
    required this.isDark,
    required this.isEn,
    required this.onToggle,
    required this.onValidate,
    required this.onRemove,
  });

  final TextEditingController controller;
  final CouponResult? couponResult;
  final bool isLoading;
  final String? error;
  final bool expanded;
  final bool isDark;
  final bool isEn;
  final VoidCallback onToggle;
  final VoidCallback onValidate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // Already applied — show summary chip
    if (couponResult != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: YLSpacing.sm),
        child: Row(
          children: [
            Icon(Icons.local_offer_rounded,
                size: 14, color: YLColors.connected),
            const SizedBox(width: 6),
            Text(
              isEn ? 'Coupon applied' : '优惠券已应用',
              style: YLText.caption.copyWith(color: YLColors.connected),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onRemove,
              child: Text(
                isEn ? 'Remove' : '移除',
                style: YLText.caption.copyWith(color: YLColors.zinc400),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle row
        GestureDetector(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.local_offer_outlined,
                  size: 14,
                  color: YLColors.zinc400,
                ),
                const SizedBox(width: 6),
                Text(
                  isEn ? 'Have a coupon?' : '有优惠码？',
                  style: YLText.caption.copyWith(color: YLColors.zinc400),
                ),
              ],
            ),
          ),
        ),

        // Input row (only when expanded)
        if (expanded) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: controller,
                    style: YLText.body,
                    decoration: InputDecoration(
                      hintText: isEn ? 'Enter coupon code' : '请输入优惠码',
                      hintStyle:
                          YLText.body.copyWith(color: YLColors.zinc400),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor:
                          isDark ? YLColors.zinc800 : YLColors.zinc100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(YLRadius.md),
                        borderSide: BorderSide.none,
                      ),
                      errorText: error,
                      errorStyle: YLText.caption
                          .copyWith(color: YLColors.error, height: 0),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => onValidate(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: isLoading ? null : onValidate,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isDark ? YLColors.zinc700 : YLColors.zinc200,
                    foregroundColor:
                        isDark ? YLColors.zinc200 : YLColors.zinc700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YLRadius.md),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          isEn ? 'Apply' : '验证',
                          style: YLText.caption
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: YLSpacing.sm),
        ],
      ],
    );
  }
}

// ── Summary row ───────────────────────────────────────────────────────────────

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.isDark,
    this.valueStyle,
  });

  final String label;
  final String value;
  final bool isDark;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: YLText.body.copyWith(color: YLColors.zinc500)),
        Text(
          value,
          style: valueStyle ??
              YLText.body.copyWith(
                  color: isDark ? YLColors.zinc200 : YLColors.zinc800),
        ),
      ],
    );
  }
}
