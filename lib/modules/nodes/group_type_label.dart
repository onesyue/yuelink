import 'package:flutter/widgets.dart';

/// Returns a localized label for proxy group types.
///
/// Uses the current locale from [context] to decide between Chinese and English.
String groupTypeLabel(BuildContext context, String type) {
  final isEn = Localizations.localeOf(context).languageCode == 'en';
  switch (type) {
    case 'Selector':
      return isEn ? 'Select' : '手动选择';
    case 'URLTest':
      return isEn ? 'Auto' : '自动选择';
    case 'Fallback':
      return isEn ? 'Fallback' : '故障转移';
    case 'LoadBalance':
      return isEn ? 'Balance' : '负载均衡';
    default:
      return type;
  }
}
