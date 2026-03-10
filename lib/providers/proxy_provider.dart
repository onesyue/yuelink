import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/core_controller.dart';
import '../models/proxy.dart';
import '../services/core_manager.dart';

/// Custom URL used for latency testing. Defaults to the standard gstatic URL.
final testUrlProvider = StateProvider<String>(
    (ref) => 'https://www.gstatic.com/generate_204');

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

    // Build groups map first
    final groupsMap = <String, ProxyGroup>{};
    for (final entry in proxiesMap.entries) {
      final info = entry.value as Map<String, dynamic>;
      if (info.containsKey('all')) {
        groupsMap[entry.key] = ProxyGroup(
          name: entry.key,
          type: info['type'] as String? ?? '',
          all: (info['all'] as List?)?.cast<String>() ?? [],
          now: info['now'] as String? ?? '',
        );
      }
    }

    // Use GLOBAL group's order to sort; exclude GLOBAL itself
    final globalAll = (proxiesMap['GLOBAL']?['all'] as List?)?.cast<String>();
    final groups = <ProxyGroup>[];
    if (globalAll != null) {
      for (final name in globalAll) {
        final g = groupsMap.remove(name);
        if (g != null) groups.add(g);
      }
    }
    // Append any remaining groups not in GLOBAL
    groups.addAll(groupsMap.values.where((g) => g.name != 'GLOBAL'));
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
    final testing = Set<String>.from(ref.read(delayTestingProvider));
    testing.add(proxyName);
    ref.read(delayTestingProvider.notifier).state = testing;

    final manager = CoreManager.instance;
    final testUrl = ref.read(testUrlProvider);
    int delay;

    if (manager.isMockMode) {
      delay = await Future(() {
        return CoreController.instance.testDelay(proxyName);
      });
    } else {
      delay = await manager.api.testDelay(proxyName, url: testUrl);
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
  ///
  /// In real mode, uses the REST API group delay test (parallel).
  /// In mock mode, falls back to sequential testing.
  Future<void> testGroup(String groupName, List<String> proxyNames) async {
    final manager = CoreManager.instance;

    if (!manager.isMockMode) {
      final testing = Set<String>.from(ref.read(delayTestingProvider));
      testing.addAll(proxyNames);
      ref.read(delayTestingProvider.notifier).state = testing;

      final testUrl = ref.read(testUrlProvider);
      try {
        final results = await manager.api.testGroupDelay(groupName, url: testUrl);
        // Results: {proxyName: {delay: int}, ...} or {proxyName: int}
        final current = Map<String, int>.from(ref.read(delayResultsProvider));
        for (final entry in results.entries) {
          final value = entry.value;
          if (value is int) {
            current[entry.key] = value;
          } else if (value is Map) {
            current[entry.key] = (value['delay'] as num?)?.toInt() ?? -1;
          }
        }
        ref.read(delayResultsProvider.notifier).state = current;
      } catch (_) {
        // API error, mark all as failed
        final current = Map<String, int>.from(ref.read(delayResultsProvider));
        for (final name in proxyNames) {
          current[name] = -1;
        }
        ref.read(delayResultsProvider.notifier).state = current;
      }

      // Unmark all
      final doneSet = Set<String>.from(ref.read(delayTestingProvider));
      doneSet.removeAll(proxyNames);
      ref.read(delayTestingProvider.notifier).state = doneSet;
    } else {
      // Mock: test sequentially
      for (final name in proxyNames) {
        await testDelay(name);
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}
