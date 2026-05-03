import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/account/account_overview.dart';
import '../../../domain/store/purchase_state.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/telemetry.dart';
import '../../../theme.dart';
import '../../mine/providers/account_providers.dart';
import '../../store/store_page.dart';
import '../../store/purchase_notifier.dart';

enum RenewalReminderBucket { t7, t3, t0, expired }

class RenewalReminderState {
  const RenewalReminderState({
    required this.bucket,
    required this.daysRemaining,
    required this.planName,
    required this.expireAt,
  });

  final RenewalReminderBucket bucket;
  final int daysRemaining;
  final String planName;
  final DateTime? expireAt;

  String get bucketName => switch (bucket) {
    RenewalReminderBucket.t7 => 't7',
    RenewalReminderBucket.t3 => 't3',
    RenewalReminderBucket.t0 => 't0',
    RenewalReminderBucket.expired => 'expired',
  };
}

RenewalReminderState? renewalReminderFor(
  AccountOverview? overview, {
  DateTime? now,
}) {
  if (overview == null) return null;
  final days =
      overview.daysRemaining ??
      _daysUntil(overview.expireAt, now ?? DateTime.now());
  if (days == null || days > 7) return null;

  final bucket = days < 0
      ? RenewalReminderBucket.expired
      : days == 0
      ? RenewalReminderBucket.t0
      : days <= 3
      ? RenewalReminderBucket.t3
      : RenewalReminderBucket.t7;

  return RenewalReminderState(
    bucket: bucket,
    daysRemaining: days,
    planName: overview.planName,
    expireAt: overview.expireAt,
  );
}

int? _daysUntil(DateTime? expireAt, DateTime now) {
  if (expireAt == null) return null;
  final today = DateTime(now.year, now.month, now.day);
  final expireDay = DateTime(expireAt.year, expireAt.month, expireAt.day);
  return expireDay.difference(today).inDays;
}

class RenewalReminderBanner extends ConsumerStatefulWidget {
  const RenewalReminderBanner({super.key});

  @override
  ConsumerState<RenewalReminderBanner> createState() =>
      _RenewalReminderBannerState();
}

class _RenewalReminderBannerState extends ConsumerState<RenewalReminderBanner> {
  String? _shownBucket;
  bool _renewalFlowStarted = false;
  ProviderSubscription<PurchaseState>? _purchaseSub;

  @override
  void initState() {
    super.initState();
    _purchaseSub = ref.listenManual<PurchaseState>(purchaseProvider, (_, next) {
      if (!_renewalFlowStarted || next is! PurchaseSuccess) return;
      _renewalFlowStarted = false;
      Telemetry.event(
        TelemetryEvents.renewalPaySuccess,
        props: {'plan_id': next.order.planId, 'period': next.order.period},
      );
    });
  }

  @override
  void dispose() {
    _purchaseSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref
        .watch(accountOverviewProvider)
        .whenOrNull(data: (value) => value);
    final reminder = renewalReminderFor(overview);
    if (reminder == null) return const SizedBox.shrink();

    if (_shownBucket != reminder.bucketName) {
      _shownBucket = reminder.bucketName;
      Telemetry.event(
        TelemetryEvents.renewalBannerShow,
        props: {
          'bucket': reminder.bucketName,
          'days_remaining': reminder.daysRemaining,
        },
      );
    }

    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEn = s.isEn;
    final expired = reminder.bucket == RenewalReminderBucket.expired;
    final color = expired ? YLColors.error : const Color(0xFFF59E0B);
    final bg = color.withValues(alpha: isDark ? 0.12 : 0.08);
    final border = color.withValues(alpha: isDark ? 0.32 : 0.22);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            expired ? Icons.warning_amber_rounded : Icons.event_repeat_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title(reminder, isEn),
                  style: YLText.body.copyWith(
                    color: isDark ? Colors.white : YLColors.zinc900,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(reminder, isEn),
                  style: YLText.caption.copyWith(
                    color: isDark ? YLColors.zinc400 : YLColors.zinc600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: FilledButton(
              onPressed: () => _openStore(context, reminder),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YLRadius.md),
                ),
              ),
              child: Text(
                isEn ? 'Renew' : '续费',
                style: YLText.caption.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openStore(BuildContext context, RenewalReminderState reminder) {
    _renewalFlowStarted = true;
    Telemetry.event(
      TelemetryEvents.renewalClick,
      props: {
        'bucket': reminder.bucketName,
        'days_remaining': reminder.daysRemaining,
      },
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StorePage()),
    );
  }

  String _title(RenewalReminderState reminder, bool isEn) {
    if (reminder.bucket == RenewalReminderBucket.expired) {
      return isEn ? 'Subscription expired' : '订阅已到期';
    }
    if (reminder.daysRemaining == 0) {
      return isEn ? 'Subscription expires today' : '订阅今天到期';
    }
    return isEn
        ? 'Subscription expires in ${reminder.daysRemaining} days'
        : '订阅将在 ${reminder.daysRemaining} 天后到期';
  }

  String _subtitle(RenewalReminderState reminder, bool isEn) {
    final date = reminder.expireAt == null
        ? ''
        : '${reminder.expireAt!.year}-${reminder.expireAt!.month.toString().padLeft(2, '0')}-${reminder.expireAt!.day.toString().padLeft(2, '0')}';
    final suffix = date.isEmpty
        ? reminder.planName
        : '${reminder.planName} · $date';
    return isEn
        ? 'Renew now to avoid interruption · $suffix'
        : '续费后可避免连接中断 · $suffix';
  }
}
