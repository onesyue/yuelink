import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'nodes_providers.dart';

/// Delay for a single node. Returns null if untested.
final nodeDelayProvider = Provider.family<int?, String>((ref, nodeName) {
  return ref.watch(delayResultsProvider)[nodeName];
});

/// Currently selected node name for a group.
final groupSelectedNodeProvider = Provider.family<String, String>((ref, groupName) {
  final groups = ref.watch(proxyGroupsProvider);
  if (groups.isEmpty) return '';
  try {
    return groups.firstWhere((g) => g.name == groupName).now;
  } catch (_) {
    return '';
  }
});

/// Whether a specific node is currently being delay-tested.
final nodeIsTestingProvider = Provider.family<bool, String>((ref, nodeName) {
  return ref.watch(delayTestingProvider).contains(nodeName);
});

/// Protocol type for a single node (e.g. "ss", "vmess", "trojan").
final nodeTypeProvider = Provider.family<String?, String>((ref, nodeName) {
  return ref.watch(nodeTypeMapProvider)[nodeName];
});
