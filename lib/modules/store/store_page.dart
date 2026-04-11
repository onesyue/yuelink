import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_strings.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../theme.dart';
import 'order_history_page.dart';
import 'store_providers.dart';
import 'widgets/plan_card.dart';

/// Native store / plan center for YueLink.
///
/// Shows current plan summary and all available plans for purchase/renewal.
class StorePage extends ConsumerWidget {
  const StorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.of(context);
    final isEn = s.isEn;

    // Guest mode: show login prompt instead of store
    final authState = ref.watch(authProvider);
    if (authState.isGuest) {
      return Scaffold(
        backgroundColor: isDark ? YLColors.bgDark : YLColors.bgLight,
        appBar: AppBar(
          backgroundColor: isDark ? YLColors.bgDark : YLColors.bgLight,
          elevation: 0,
          leading: Navigator.canPop(context) ? const BackButton() : null,
          automaticallyImplyLeading: false,
          title: Text(isEn ? 'Plans' : '订阅套餐',
              style: YLText.titleMedium.copyWith(fontWeight: FontWeight.w700)),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 48, color: YLColors.zinc400),
              const SizedBox(height: 16),
              Text(isEn ? 'Login to view plans' : '请先登录查看套餐',
                  style: YLText.body.copyWith(color: YLColors.zinc500)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.read(authProvider.notifier).logout(),
                child: Text(isEn ? 'Go to Login' : '前往登录'),
              ),
            ],
          ),
        ),
      );
    }

    final profile = ref.watch(userProfileProvider); // for isCurrentPlan badge
    final plansAsync = ref.watch(storePlansProvider);

    return Scaffold(
      backgroundColor: isDark ? YLColors.bgDark : YLColors.bgLight,
      appBar: AppBar(
        backgroundColor: isDark ? YLColors.bgDark : YLColors.bgLight,
        elevation: 0,
        leading: Navigator.canPop(context) ? const BackButton() : null,
        automaticallyImplyLeading: false,
        title: Text(
          isEn ? 'Plans' : '订阅套餐',
          style: YLText.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined, size: 20),
            color: YLColors.zinc500,
            tooltip: isEn ? 'Order History' : '订单记录',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OrderHistoryPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: YLColors.zinc500,
            onPressed: () =>
                ref.read(storePlansProvider.notifier).refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(storePlansProvider.notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                  horizontal: YLSpacing.md, vertical: YLSpacing.sm),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Plans section header ──────────────────────────
                  Text(
                    isEn ? 'Choose a Plan' : '选择套餐',
                    style: YLText.label.copyWith(
                        color: YLColors.zinc500,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: YLSpacing.sm),
                ]),
              ),
            ),

            // ── Plans list ────────────────────────────────────────
            plansAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => SliverFillRemaining(
                child: _ErrorView(
                  message: err.toString(),
                  onRetry: () =>
                      ref.read(storePlansProvider.notifier).refresh(),
                  isEn: isEn,
                ),
              ),
              data: (plans) {
                if (plans.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.storefront_outlined,
                              size: 48, color: YLColors.zinc300),
                          const SizedBox(height: YLSpacing.md),
                          Text(
                            isEn ? 'No plans available' : '暂无可购套餐',
                            style: YLText.body
                                .copyWith(color: YLColors.zinc500),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Pin the user's current plan to the top of the list
                final sortedPlans = [...plans];
                if (profile?.planId != null) {
                  sortedPlans.sort((a, b) {
                    final aIsCurrent = a.id == profile?.planId;
                    final bIsCurrent = b.id == profile?.planId;
                    if (aIsCurrent && !bIsCurrent) return -1;
                    if (!aIsCurrent && bIsCurrent) return 1;
                    return 0;
                  });
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: YLSpacing.md),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final plan = sortedPlans[i];
                        final isCurrentPlan =
                            profile?.planId == plan.id;

                        return Padding(
                          padding: const EdgeInsets.only(
                              bottom: YLSpacing.sm),
                          child: PlanCard(
                            plan: plan,
                            isCurrentPlan: isCurrentPlan,
                          ),
                        );
                      },
                      childCount: sortedPlans.length,
                    ),
                  ),
                );
              },
            ),

            const SliverPadding(
              padding: EdgeInsets.only(bottom: YLSpacing.xl),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline_rounded, size: 48, color: YLColors.zinc300),
        const SizedBox(height: YLSpacing.md),
        Text(
          isEn ? 'Failed to load plans' : '套餐加载失败',
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
    );
  }
}
