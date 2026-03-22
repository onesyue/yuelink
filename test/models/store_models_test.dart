import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/store/store_plan.dart';
import 'package:yuelink/domain/store/store_order.dart';

void main() {
  group('StorePlan', () {
    test('fromJson parses all fields', () {
      final plan = StorePlan.fromJson({
        'id': 1,
        'name': '基础套餐',
        'content': '<p>Feature list</p>',
        'transfer_enable': 100,
        'speed_limit': 500,
        'device_limit': 3,
        'show': true,
        'sell': true,
        'sort': 10,
        'month_price': 1800,
        'quarter_price': 4800,
        'half_year_price': 9000,
        'year_price': 16800,
        'two_year_price': null,
        'three_year_price': null,
        'onetime_price': null,
        'reset_price': 500,
      });

      expect(plan.id, 1);
      expect(plan.name, '基础套餐');
      expect(plan.content, '<p>Feature list</p>');
      expect(plan.transferEnable, 100);
      expect(plan.speedLimit, 500);
      expect(plan.deviceLimit, 3);
      expect(plan.monthPrice, 1800);
      expect(plan.quarterPrice, 4800);
      expect(plan.yearPrice, 16800);
      expect(plan.twoYearPrice, isNull);
    });

    test('handles XBoard tinyint(1) bool casting', () {
      // PHP returns true/false for tinyint(1) fields
      final plan = StorePlan.fromJson({
        'id': true, // tinyint bool
        'name': 'test',
        'show': 1,
        'sell': false,
        'sort': 0.0, // double
        'month_price': true, // tinyint → 1
      });

      expect(plan.id, 1);
      expect(plan.show, true);
      expect(plan.sell, false);
      expect(plan.sort, 0);
      expect(plan.monthPrice, 1);
    });

    test('availablePeriods filters by non-null prices', () {
      final plan = StorePlan.fromJson({
        'id': 1,
        'name': 'test',
        'month_price': 1800,
        'year_price': 16800,
      });

      final periods = plan.availablePeriods;
      expect(periods, contains(PlanPeriod.monthly));
      expect(periods, contains(PlanPeriod.yearly));
      expect(periods, isNot(contains(PlanPeriod.quarterly)));
      expect(periods, isNot(contains(PlanPeriod.onetime)));
    });

    test('formattedPrice formats yuan correctly', () {
      final plan = StorePlan(id: 1, name: 'test', monthPrice: 1800, yearPrice: 0);

      expect(plan.formattedPrice(PlanPeriod.monthly), '¥18');
      expect(plan.formattedPrice(PlanPeriod.yearly), '免费');
      expect(plan.formattedPrice(PlanPeriod.quarterly), '-');
    });

    test('formattedPrice handles decimal yuan', () {
      final plan = StorePlan(id: 1, name: 'test', monthPrice: 1850);

      expect(plan.formattedPrice(PlanPeriod.monthly), '¥18.50');
    });

    test('trafficLabel displays GB or unlimited', () {
      expect(
        StorePlan(id: 1, name: 'a', transferEnable: 100).trafficLabel,
        '100 GB',
      );
      expect(
        StorePlan(id: 1, name: 'b', transferEnable: null).trafficLabel,
        '不限',
      );
      expect(
        StorePlan(id: 1, name: 'c', transferEnable: 0).trafficLabel,
        '不限',
      );
    });

    test('speedLabel displays Mbps/Gbps or unlimited', () {
      expect(
        StorePlan(id: 1, name: 'a', speedLimit: 500).speedLabel,
        '500 Mbps',
      );
      expect(
        StorePlan(id: 1, name: 'b', speedLimit: 1000).speedLabel,
        '1.0 Gbps',
      );
      expect(
        StorePlan(id: 1, name: 'c').speedLabel,
        '不限',
      );
    });
  });

  group('StoreOrder', () {
    test('fromJson parses all fields', () {
      final order = StoreOrder.fromJson({
        'trade_no': 'TN202603200001',
        'plan_id': 1,
        'plan': {'name': '基础套餐'},
        'period': 'month_price',
        'total_amount': 1800,
        'status': 0,
        'created_at': 1711000000,
        'updated_at': 1711000100,
        'coupon_code': 'SAVE10',
      });

      expect(order.tradeNo, 'TN202603200001');
      expect(order.planId, 1);
      expect(order.planName, '基础套餐');
      expect(order.period, 'month_price');
      expect(order.totalAmount, 1800);
      expect(order.status, OrderStatus.pending);
      expect(order.couponCode, 'SAVE10');
    });

    test('handles tinyint bool casting for status', () {
      final order = StoreOrder.fromJson({
        'trade_no': 'TN1',
        'plan_id': true,
        'period': 'month_price',
        'total_amount': 0.0,
        'status': true, // tinyint(1) → 1 → processing
        'created_at': 1711000000,
        'updated_at': 1711000000,
      });

      expect(order.planId, 1);
      expect(order.totalAmount, 0);
      expect(order.status, OrderStatus.processing);
    });

    test('formattedAmount formats correctly', () {
      expect(
        StoreOrder(tradeNo: '', planId: 0, period: '', totalAmount: 1800,
            status: OrderStatus.pending, createdAt: 0, updatedAt: 0)
            .formattedAmount,
        '¥18',
      );
      expect(
        StoreOrder(tradeNo: '', planId: 0, period: '', totalAmount: 0,
            status: OrderStatus.pending, createdAt: 0, updatedAt: 0)
            .formattedAmount,
        '免费',
      );
      expect(
        StoreOrder(tradeNo: '', planId: 0, period: '', totalAmount: 1850,
            status: OrderStatus.pending, createdAt: 0, updatedAt: 0)
            .formattedAmount,
        '¥18.50',
      );
    });

    test('planName extracts from nested plan object', () {
      final order = StoreOrder.fromJson({
        'trade_no': 'T1',
        'plan': {'name': 'Premium'},
        'period': 'year_price',
        'total_amount': 16800,
        'status': 3,
        'created_at': 0,
        'updated_at': 0,
      });
      expect(order.planName, 'Premium');
    });

    test('planName falls back to plan_name field', () {
      final order = StoreOrder.fromJson({
        'trade_no': 'T1',
        'plan_name': 'Basic',
        'period': 'month_price',
        'total_amount': 1800,
        'status': 0,
        'created_at': 0,
        'updated_at': 0,
      });
      expect(order.planName, 'Basic');
    });
  });

  group('OrderStatus', () {
    test('fromInt maps all values', () {
      expect(OrderStatus.fromInt(0), OrderStatus.pending);
      expect(OrderStatus.fromInt(1), OrderStatus.processing);
      expect(OrderStatus.fromInt(2), OrderStatus.cancelled);
      expect(OrderStatus.fromInt(3), OrderStatus.completed);
      expect(OrderStatus.fromInt(4), OrderStatus.discounted);
      expect(OrderStatus.fromInt(null), OrderStatus.pending);
      expect(OrderStatus.fromInt(99), OrderStatus.pending);
    });

    test('isSuccess includes processing, completed, discounted', () {
      expect(OrderStatus.processing.isSuccess, isTrue);
      expect(OrderStatus.completed.isSuccess, isTrue);
      expect(OrderStatus.discounted.isSuccess, isTrue);
      expect(OrderStatus.pending.isSuccess, isFalse);
      expect(OrderStatus.cancelled.isSuccess, isFalse);
    });

    test('isTerminal includes cancelled, completed, discounted', () {
      expect(OrderStatus.cancelled.isTerminal, isTrue);
      expect(OrderStatus.completed.isTerminal, isTrue);
      expect(OrderStatus.discounted.isTerminal, isTrue);
      expect(OrderStatus.pending.isTerminal, isFalse);
      expect(OrderStatus.processing.isTerminal, isFalse);
    });
  });

  group('CheckoutResult', () {
    test('free order has no payment URL', () {
      final result = CheckoutResult.fromJson({'type': -1, 'data': true});
      expect(result.isFree, isTrue);
      expect(result.paymentUrl, '');
      expect(result.isUrl, isFalse);
    });

    test('redirect URL order', () {
      final result = CheckoutResult.fromJson({
        'type': 1,
        'data': 'https://pay.example.com/order/123',
      });
      expect(result.isFree, isFalse);
      expect(result.paymentUrl, 'https://pay.example.com/order/123');
      expect(result.isUrl, isTrue);
    });

    test('QR code URL order', () {
      final result = CheckoutResult.fromJson({
        'type': 0,
        'data': 'https://qr.example.com/pay.png',
      });
      expect(result.type, 0);
      expect(result.isUrl, isTrue);
    });
  });

  group('PlanPeriod', () {
    test('apiKey returns correct values', () {
      expect(PlanPeriod.monthly.apiKey, 'month_price');
      expect(PlanPeriod.quarterly.apiKey, 'quarter_price');
      expect(PlanPeriod.halfYearly.apiKey, 'half_year_price');
      expect(PlanPeriod.yearly.apiKey, 'year_price');
      expect(PlanPeriod.onetime.apiKey, 'onetime_price');
    });

    test('label returns localized strings', () {
      expect(PlanPeriod.monthly.label(true), '1 Month');
      expect(PlanPeriod.monthly.label(false), '月付');
      expect(PlanPeriod.yearly.label(true), '1 Year');
      expect(PlanPeriod.yearly.label(false), '年付');
    });

    test('shortLabel returns Chinese abbreviations', () {
      expect(PlanPeriod.monthly.shortLabel, '月');
      expect(PlanPeriod.yearly.shortLabel, '年');
      expect(PlanPeriod.onetime.shortLabel, '买断');
    });
  });
}
