import '../../domain/store/store_plan.dart';

String planPeriodApiKey(PlanPeriod period) {
  switch (period) {
    case PlanPeriod.monthly:
      return 'month_price';
    case PlanPeriod.quarterly:
      return 'quarter_price';
    case PlanPeriod.halfYearly:
      return 'half_year_price';
    case PlanPeriod.yearly:
      return 'year_price';
    case PlanPeriod.twoYearly:
      return 'two_year_price';
    case PlanPeriod.threeYearly:
      return 'three_year_price';
    case PlanPeriod.onetime:
      return 'onetime_price';
  }
}

PlanPeriod? planPeriodFromApiKey(String apiKey) {
  switch (apiKey) {
    case 'month_price':
      return PlanPeriod.monthly;
    case 'quarter_price':
      return PlanPeriod.quarterly;
    case 'half_year_price':
      return PlanPeriod.halfYearly;
    case 'year_price':
      return PlanPeriod.yearly;
    case 'two_year_price':
      return PlanPeriod.twoYearly;
    case 'three_year_price':
      return PlanPeriod.threeYearly;
    case 'onetime_price':
      return PlanPeriod.onetime;
  }
  return null;
}

String planPeriodLabelFromApiKey(String apiKey, {required bool isEn}) {
  final period = planPeriodFromApiKey(apiKey);
  return period?.label(isEn) ?? apiKey;
}
