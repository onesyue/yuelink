import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/account/account_overview.dart';
import 'package:yuelink/modules/dashboard/widgets/renewal_reminder_banner.dart';

AccountOverview _overview({int? daysRemaining, DateTime? expireAt}) {
  return AccountOverview(
    email: 'user@example.com',
    planName: '月付套餐',
    transferUsedBytes: 0,
    transferTotalBytes: 1024,
    transferRemainingBytes: 1024,
    daysRemaining: daysRemaining,
    expireAt: expireAt,
    renewalUrl: 'https://yuetong.app/#/plan',
  );
}

void main() {
  group('renewalReminderFor', () {
    test('hides when subscription has more than seven days remaining', () {
      expect(renewalReminderFor(_overview(daysRemaining: 8)), isNull);
    });

    test('buckets seven, three, same-day and expired windows', () {
      expect(
        renewalReminderFor(_overview(daysRemaining: 7))!.bucket,
        RenewalReminderBucket.t7,
      );
      expect(
        renewalReminderFor(_overview(daysRemaining: 3))!.bucket,
        RenewalReminderBucket.t3,
      );
      expect(
        renewalReminderFor(_overview(daysRemaining: 0))!.bucket,
        RenewalReminderBucket.t0,
      );
      expect(
        renewalReminderFor(_overview(daysRemaining: -1))!.bucket,
        RenewalReminderBucket.expired,
      );
    });

    test('derives days from expireAt when API does not send daysRemaining', () {
      final now = DateTime(2026, 5, 3, 23, 40);
      final reminder = renewalReminderFor(
        _overview(expireAt: DateTime(2026, 5, 6, 1, 20)),
        now: now,
      );

      expect(reminder, isNotNull);
      expect(reminder!.daysRemaining, 3);
      expect(reminder.bucket, RenewalReminderBucket.t3);
    });
  });
}
