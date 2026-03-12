import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';

import '../../../core/ffi/core_controller.dart';
import '../../../domain/models/proxy.dart';
import '../../../providers/profile_provider.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../infrastructure/repositories/profile_repository.dart';
import '../../../infrastructure/repositories/proxy_repository.dart';

// ------------------------------------------------------------------
// Node sort / view mode
// ------------------------------------------------------------------

enum NodeSortMode { defaultOrder, latencyAsc, latencyDesc, nameAsc }

final nodeSortModeProvider =
    StateProvider<NodeSortMode>((ref) => NodeSortMode.defaultOrder);

enum NodeViewMode { card, list }

final nodeViewModeProvider =
    StateProvider<NodeViewMode>((ref) => NodeViewMode.card);

/// Real-time node search query — empty string means no filter.
final nodeSearchQueryProvider = StateProvider<String>((ref) => '');

// ------------------------------------------------------------------
// Offline proxy groups (parsed from active profile YAML)
// ------------------------------------------------------------------

final offlineProxyGroupsProvider = FutureProvider<List<ProxyGroup>>((ref) async {
  final activeId = ref.watch(activeProfileIdProvider);
  if (activeId == null) return [];
  final config =
      await ref.read(profileRepositoryProvider).loadConfig(activeId);
  if (config == null || config.isEmpty) return [];
  try {
    final yaml = loadYaml(config);
    if (yaml is! YamlMap) return [];
    final rawGroups = yaml['proxy-groups'];
    if (rawGroups == null) return [];
    final groups = <ProxyGroup>[];
    for (final item in rawGroups) {
      if (item is! YamlMap) continue;
      final name = item['name']?.toString() ?? '';
      final type = item['type']?.toString() ?? '';
      if (name.isEmpty) continue;
      if (name == 'GLOBAL' || name == 'DIRECT' || name == 'REJECT') continue;
      final allRaw = item['proxies'];
      final all = <String>[];
      if (allRaw is YamlList) {
        for (final n in allRaw) {
          if (n != null) all.add(n.toString());
        }
      }
      groups.add(ProxyGroup(name: name, type: type, all: all, now: ''));
    }
    return groups;
  } catch (_) {
    return [];
  }
});

// ------------------------------------------------------------------
// Proxy groups & nodes
// ------------------------------------------------------------------

final proxyGroupsProvider =
    StateNotifierProvider<ProxyGroupsNotifier, List<ProxyGroup>>(
  (ref) => ProxyGroupsNotifier(ref),
);

/// The mihomo GLOBAL proxy group (used in global routing mode).
/// null until the first refresh completes.
final globalGroupProvider = StateProvider<ProxyGroup?>((ref) => null);

class ProxyGroupsNotifier extends StateNotifier<List<ProxyGroup>> {
  ProxyGroupsNotifier(this._ref) : super([]);
  final Ref _ref;

  ProxyRepository get _repo => _ref.read(proxyRepositoryProvider);

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
        data = await _repo.getProxies();
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

    // Extract and store the GLOBAL group (for global routing mode display).
    final globalInfo = proxiesMap['GLOBAL'] as Map<String, dynamic>?;
    if (globalInfo != null) {
      // Filter GLOBAL's `all` list to only real user groups (exclude DIRECT/REJECT/built-ins)
      final allNames = (globalInfo['all'] as List?)?.cast<String>() ?? [];
      final filteredAll = allNames
          .where((n) => groupsMap.containsKey(n))
          .toList();
      final globalGroup = ProxyGroup(
        name: 'GLOBAL',
        type: globalInfo['type'] as String? ?? 'Selector',
        all: filteredAll.isNotEmpty ? filteredAll : allNames,
        now: globalInfo['now'] as String? ?? '',
      );
      _ref.read(globalGroupProvider.notifier).state = globalGroup;
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
      ok = await _repo.changeProxy(groupName, proxyName);
    }

    if (ok) await refresh();
    return ok;
  }
}

// ------------------------------------------------------------------
// Delay testing
// ------------------------------------------------------------------

/// Custom URL used for latency testing. Defaults to the standard gstatic URL.
final testUrlProvider = StateProvider<String>(
    (ref) => 'https://www.gstatic.com/generate_204');

final delayResultsProvider = StateProvider<Map<String, int>>((ref) => {});
final delayTestingProvider = StateProvider<Set<String>>((ref) => {});

final delayTestProvider =
    Provider<DelayTestActions>((ref) => DelayTestActions(ref));

class DelayTestActions {
  final Ref ref;
  DelayTestActions(this.ref);

  ProxyRepository get _repo => ref.read(proxyRepositoryProvider);

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
      delay = await _repo.testDelayWithBatch(
        proxyName,
        url: testUrl,
        onResult: (name, d) {
          final current =
              Map<String, int>.from(ref.read(delayResultsProvider));
          current[name] = d;
          ref.read(delayResultsProvider.notifier).state = current;
        },
      );
    }

    // Update results directly (batcher may also fire, but this ensures
    // immediate update for the single-node case)
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
        final results =
            await _repo.testGroupDelay(groupName, url: testUrl);
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
