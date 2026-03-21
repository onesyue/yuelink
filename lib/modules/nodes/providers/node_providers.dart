import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'nodes_providers.dart';

/// Delay for a single node. Returns null if untested.
/// Uses `.select()` so only the specific node's delay triggers a rebuild,
/// not every delay map mutation (critical during group delay tests).
final nodeDelayProvider = Provider.family<int?, String>((ref, nodeName) {
  return ref.watch(delayResultsProvider.select((map) => map[nodeName]));
});

/// Currently selected node name for a group.
/// Uses `.select()` to only rebuild when this specific group's `now` changes.
final groupSelectedNodeProvider = Provider.family<String, String>((ref, groupName) {
  return ref.watch(proxyGroupsProvider.select((groups) {
    if (groups.isEmpty) return '';
    try {
      return groups.firstWhere((g) => g.name == groupName).now;
    } catch (_) {
      return '';
    }
  }));
});

/// Whether a specific node is currently being delay-tested.
/// Uses `.select()` so only changes to this node's testing state trigger rebuild.
final nodeIsTestingProvider = Provider.family<bool, String>((ref, nodeName) {
  return ref.watch(delayTestingProvider.select((set) => set.contains(nodeName)));
});

/// Protocol type for a single node (e.g. "ss", "vmess", "trojan").
/// Uses `.select()` so only changes to this node's type trigger rebuild.
final nodeTypeProvider = Provider.family<String?, String>((ref, nodeName) {
  return ref.watch(nodeTypeMapProvider.select((map) => map[nodeName]));
});
