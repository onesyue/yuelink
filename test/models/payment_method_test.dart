import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/store/payment_method.dart';

void main() {
  group('PaymentMethod', () {
    test('fromJson parses all fields', () {
      final method = PaymentMethod.fromJson({
        'id': 1,
        'name': '支付宝',
        'icon': 'alipay.png',
        'payment': 'alipay',
        'handling_fee_fixed': 50,
        'handling_fee_percent': null,
      });

      expect(method.id, 1);
      expect(method.name, '支付宝');
      expect(method.icon, 'alipay.png');
      expect(method.payment, 'alipay');
      expect(method.handlingFeeFixed, 50);
      expect(method.handlingFeePercent, isNull);
    });

    test('handlingFeeLabel returns fixed fee', () {
      const method = PaymentMethod(
        id: 1, name: 'test', handlingFeeFixed: 50,
      );
      expect(method.handlingFeeLabel(1800), '+¥0.50');
    });

    test('handlingFeeLabel returns percent fee', () {
      const method = PaymentMethod(
        id: 1, name: 'test', handlingFeePercent: 5,
      );
      // 5% of 1800 fen = 90 fen = ¥0.90
      expect(method.handlingFeeLabel(1800), '+¥0.90 (5%)');
    });

    test('handlingFeeLabel returns null when no fee', () {
      const method = PaymentMethod(id: 1, name: 'test');
      expect(method.handlingFeeLabel(1800), isNull);
    });

    test('handles tinyint bool casting', () {
      final method = PaymentMethod.fromJson({
        'id': 1,
        'name': 'test',
        'handling_fee_fixed': true, // tinyint(1) → 1
        'handling_fee_percent': false, // tinyint(1) → 0
      });

      expect(method.handlingFeeFixed, 1);
      expect(method.handlingFeePercent, 0);
    });
  });
}
