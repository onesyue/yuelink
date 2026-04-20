import 'package:flutter_test/flutter_test.dart';

import 'package:yuelink/shared/formatters/subscription_parser.dart';

void main() {
  group('SubscriptionInfo.fromHeaders', () {
    test('parses full subscription-userinfo header', () {
      final info = SubscriptionInfo.fromHeaders({
        'subscription-userinfo':
            'upload=1073741824; download=2147483648; total=10737418240; expire=1893456000',
      });
      expect(info.upload, 1073741824);
      expect(info.download, 2147483648);
      expect(info.total, 10737418240);
      expect(info.expire, isNotNull);
    });

    test('returns null fields for missing header', () {
      final info = SubscriptionInfo.fromHeaders({});
      expect(info.upload, isNull);
      expect(info.download, isNull);
      expect(info.total, isNull);
      expect(info.expire, isNull);
    });

    test('parses profile-update-interval', () {
      final info = SubscriptionInfo.fromHeaders({
        'subscription-userinfo': 'upload=0; download=0; total=1000',
        'profile-update-interval': '24',
      });
      expect(info.updateInterval, 24);
    });

    test('calculates remaining correctly', () {
      const info = SubscriptionInfo(
        upload: 100,
        download: 200,
        total: 1000,
      );
      expect(info.remaining, 700);
    });

    test('usagePercent returns null when total is null', () {
      const info = SubscriptionInfo(upload: 100, download: 200);
      expect(info.usagePercent, isNull);
    });

    test('usagePercent calculates correctly', () {
      const info = SubscriptionInfo(upload: 250, download: 250, total: 1000);
      expect(info.usagePercent, closeTo(0.5, 0.001));
    });

    test('isExpired returns false for future date', () {
      final info = SubscriptionInfo(
          expire: DateTime.now().add(const Duration(days: 30)));
      expect(info.isExpired, isFalse);
    });

    test('isExpired returns true for past date', () {
      final info = SubscriptionInfo(
          expire: DateTime.now().subtract(const Duration(days: 1)));
      expect(info.isExpired, isTrue);
    });

    test('daysRemaining is positive for future expiry', () {
      final info = SubscriptionInfo(
          expire: DateTime.now().add(const Duration(days: 10)));
      expect(info.daysRemaining, greaterThan(0));
    });
  });

  group('formatBytes', () {
    test('formats bytes', () {
      expect(formatBytes(512), '512 B');
    });

    test('formats kilobytes', () {
      expect(formatBytes(2048), '2.0 KB');
    });

    test('formats megabytes', () {
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });

    test('formats gigabytes', () {
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });
  });

  group('SubscriptionInfo JSON round-trip', () {
    test('toJson and fromJson preserve values', () {
      final original = SubscriptionInfo(
        upload: 1000,
        download: 2000,
        total: 10000,
        expire: DateTime.fromMillisecondsSinceEpoch(1893456000 * 1000),
        updateInterval: 24,
      );
      final json = original.toJson();
      final restored = SubscriptionInfo.fromJson(json);
      expect(restored.upload, original.upload);
      expect(restored.download, original.download);
      expect(restored.total, original.total);
      expect(restored.updateInterval, original.updateInterval);
    });
  });
}
