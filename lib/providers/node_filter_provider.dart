import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/node_filter_service.dart';

final nodeFilterRulesProvider =
    AsyncNotifierProvider<NodeFilterRulesNotifier, List<NodeFilterRule>>(
        NodeFilterRulesNotifier.new);

class NodeFilterRulesNotifier extends AsyncNotifier<List<NodeFilterRule>> {
  @override
  Future<List<NodeFilterRule>> build() =>
      NodeFilterService.instance.loadRules();

  Future<void> add(NodeFilterRule rule) async {
    final current = state.valueOrNull ?? <NodeFilterRule>[];
    final updated = <NodeFilterRule>[...current, rule];
    await NodeFilterService.instance.saveRules(updated);
    state = AsyncData(updated);
  }

  Future<void> remove(int index) async {
    final current = <NodeFilterRule>[...(state.valueOrNull ?? [])];
    if (index < 0 || index >= current.length) return;
    current.removeAt(index);
    await NodeFilterService.instance.saveRules(current);
    state = AsyncData(current);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = <NodeFilterRule>[...(state.valueOrNull ?? [])];
    if (newIndex > oldIndex) newIndex--;
    final item = current.removeAt(oldIndex);
    current.insert(newIndex, item);
    await NodeFilterService.instance.saveRules(current);
    state = AsyncData(current);
  }
}
