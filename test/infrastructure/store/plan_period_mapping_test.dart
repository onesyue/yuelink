import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/store/store_plan.dart';
import 'package:yuelink/infrastructure/store/plan_period_mapping.dart';

void main() {
  group('planPeriodApiKey', () {
    test('maps domain periods to XBoard api keys', () {
      expect(planPeriodApiKey(PlanPeriod.monthly), 'month_price');
      expect(planPeriodApiKey(PlanPeriod.quarterly), 'quarter_price');
      expect(planPeriodApiKey(PlanPeriod.halfYearly), 'half_year_price');
      expect(planPeriodApiKey(PlanPeriod.yearly), 'year_price');
      expect(planPeriodApiKey(PlanPeriod.onetime), 'onetime_price');
    });

    test('round-trips api keys back to periods', () {
      expect(planPeriodFromApiKey('month_price'), PlanPeriod.monthly);
      expect(planPeriodFromApiKey('year_price'), PlanPeriod.yearly);
      expect(planPeriodFromApiKey('unknown_key'), isNull);
    });
  });
}
