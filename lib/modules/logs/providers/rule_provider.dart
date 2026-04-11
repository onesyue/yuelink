import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../domain/models/rule.dart';

final rulesProvider =
    NotifierProvider<RulesNotifier, List<RuleInfo>>(
  RulesNotifier.new,
);

class RulesNotifier extends Notifier<List<RuleInfo>> {
  @override
  List<RuleInfo> build() => [];

  Future<void> refresh() async {
    final manager = CoreManager.instance;

    Map<String, dynamic> data;
    try {
      data = await manager.core.getRules();
    } catch (_) {
      return;
    }

    final rules = (data['rules'] as List?)
            ?.map((e) => RuleInfo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    state = rules;
  }
}
