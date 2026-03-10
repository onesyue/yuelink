import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/core_controller.dart';
import '../models/proxy.dart';
import '../services/core_manager.dart';

// ------------------------------------------------------------------
// Proxy groups & nodes
// ------------------------------------------------------------------

final proxyGroupsProvider =
    StateNotifierProvider<ProxyGroupsNotifier, List<ProxyGroup>>(
  (ref) => ProxyGroupsNotifier(),
);

class ProxyGroupsNotifier extends StateNotifier<List<ProxyGroup>> {
  ProxyGroupsNotifier() : super([]);

  /// Refresh proxy data from the running mihomo instance.
  ///
  /// Uses REST API in real mode, direct FFI in mock mode.
  Future<void> refresh() async {
    final manager = CoreManager.instance;

    Map<String, dynamic> data;
    if (manager.isMockMode) {
      data = CoreController.instance.getProxies();
    } else {
      try {
        data = await manager.api.getProxies();
      } catch (_) {
        return; // API not available
      }
    }

    final proxiesMap = data['proxies'] as Map<String, dynamic>? ?? {};

    final groups = <ProxyGroup>[];
    for (final entry in proxiesMap.entries) {
      final info = entry.value as Map<String, dynamic>;
      if (info.containsKey('all')) {
        groups.add(ProxyGroup(
          name: entry.key,
          type: info['type'] as String? ?? '',
          all: (info['all'] as List?)?.cast<String>() ?? [],
          now: info['now'] as String? ?? '',
        ));
      }
    }
    state = groups;
  }

  /// Change the selected proxy in a group.
  Future<bool> changeProxy(String groupName, String proxyName) async {
    final manager = CoreManager.instance;

    bool ok;
    if (manager.isMockMode) {
      ok = CoreController.instance.changeProxy(groupName, proxyName);
    } else {
      ok = await manager.api.changeProxy(groupName, proxyName);
    }

    if (ok) await refresh();
    return ok;
  }
}

// ------------------------------------------------------------------
// Delay testing
// ------------------------------------------------------------------

final delayResultsProvider = StateProvider<Map<String, int>>((ref) => {});
final delayTestingProvider = StateProvider<Set<String>>((ref) => {});

final delayTestProvider =
    Provider<DelayTestActions>((ref) => DelayTestActions(ref));

class DelayTestActions {
  final Ref ref;
  DelayTestActions(this.ref);

  /// Test delay for a single proxy node.
  Future<int> testDelay(String proxyName) async {
    // Mark as testing
    final testing = Set<String>.from(ref.read(delayTestingProvider));
    testing.add(proxyName);
    ref.read(delayTestingProvider.notifier).state = testing;

    final manager = CoreManager.instance;
    int delay;

    if (manager.isMockMode) {
      delay = await Future(() {
        return CoreController.instance.testDelay(proxyName);
      });
    } else {
      delay = await manager.api.testDelay(proxyName);
    }

    // Update results
    final current = Map<String, int>.from(ref.read(delayResultsProvider));
    current[proxyName] = delay;
    ref.read(delayResultsProvider.notifier).state = current;

    // Unmark testing
    final doneSet = Set<String>.from(ref.read(delayTestingProvider));
    doneSet.remove(proxyName);
    ref.read(delayTestingProvider.notifier).state = doneSet;

    return delay;
  }

  /// Test all proxies in a group.
  Future<void> testGroup(List<String> proxyNames) async {
    for (final name in proxyNames) {
      await testDelay(name);
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }
}
