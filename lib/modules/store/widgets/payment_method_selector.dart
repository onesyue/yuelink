import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme.dart';
import '../../../domain/store/payment_method.dart';
import '../store_providers.dart';

/// Horizontal scrollable payment method selector.
///
/// Loads methods from [paymentMethodsProvider]. If the list is empty (old
/// XBoard or 404) the widget renders nothing — checkout proceeds without
/// specifying a method and the server picks the default.
class PaymentMethodSelector extends ConsumerWidget {
  const PaymentMethodSelector({
    super.key,
    required this.selectedId,
    required this.onChanged,
    required this.orderAmountFen,
  });

  final int? selectedId;
  final ValueChanged<int?> onChanged;

  /// Amount in fen — used to compute handling fee preview.
  final int orderAmountFen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methodsAsync = ref.watch(paymentMethodsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.of(context);
    final isEn = s.isEn;

    return methodsAsync.when(
      loading: () => const SizedBox(height: 48, child: _MethodShimmer()),
      error: (_, __) => _MethodErrorRow(
        isEn: isEn,
        isDark: isDark,
        onRetry: () => ref.invalidate(paymentMethodsProvider),
      ),
      data: (methods) {
        if (methods.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEn ? 'Payment Method' : '支付方式',
              style: YLText.caption.copyWith(color: YLColors.zinc500),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: methods.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final m = methods[i];
                  final selected = m.id == selectedId;
                  final feeLabel = m.handlingFeeLabel(orderAmountFen);
                  return _MethodChip(
                    method: m,
                    selected: selected,
                    feeLabel: feeLabel,
                    isDark: isDark,
                    onTap: () => onChanged(m.id),
                  );
                },
              ),
            ),
            const SizedBox(height: YLSpacing.md),
          ],
        );
      },
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.method,
    required this.selected,
    required this.isDark,
    required this.onTap,
    this.feeLabel,
  });

  final PaymentMethod method;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  final String? feeLabel;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? (isDark ? Colors.white : YLColors.primary)
        : (isDark ? YLColors.zinc800 : YLColors.zinc100);
    final fg = selected
        ? (isDark ? YLColors.primary : Colors.white)
        : (isDark ? YLColors.zinc300 : YLColors.zinc700);
    final border = selected
        ? Colors.transparent
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.08));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(YLRadius.md),
          border: Border.all(color: border, width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              method.name,
              style: YLText.label.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (feeLabel != null)
              Text(
                feeLabel!,
                style: YLText.caption.copyWith(
                  color: selected
                      ? fg.withValues(alpha: 0.7)
                      : YLColors.zinc400,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MethodErrorRow extends StatelessWidget {
  const _MethodErrorRow({
    required this.isEn,
    required this.isDark,
    required this.onRetry,
  });

  final bool isEn;
  final bool isDark;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: YLSpacing.md),
      child: GestureDetector(
        onTap: onRetry,
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                size: 14, color: YLColors.zinc400),
            const SizedBox(width: 6),
            Text(
              isEn
                  ? 'Failed to load payment methods, tap to retry'
                  : '支付方式加载失败，点击重试',
              style: YLText.caption.copyWith(color: YLColors.zinc400),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodShimmer extends StatelessWidget {
  const _MethodShimmer();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: List.generate(
        3,
        (_) => Container(
          width: 80,
          height: 40,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: isDark ? YLColors.zinc800 : YLColors.zinc100,
            borderRadius: BorderRadius.circular(YLRadius.md),
          ),
        ),
      ),
    );
  }
}
