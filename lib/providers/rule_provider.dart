import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ffi/core_mock.dart';
import '../domain/models/rule.dart';
import '../core/kernel/core_manager.dart';

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
    if (manager.isMockMode) {
      data = CoreMock.instance.getRules();
    } else {
      try {
        data = await manager.api.getRules();
      } catch (_) {
        return;
      }
    }

    final rules = (data['rules'] as List?)
            ?.map((e) => RuleInfo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    state = rules;
  }
}
