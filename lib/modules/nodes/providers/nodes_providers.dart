import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';

import '../../../core/ffi/core_controller.dart';
import '../../../core/storage/settings_service.dart';
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

/// Derived: the "main" proxy group (PROXIES/GLOBAL/节点选择/Proxy) + its
/// currently selected node. HeroCard watches this instead of the full
/// proxyGroupsProvider, so it only rebuilds when the active selection changes.
final activeProxyInfoProvider = Provider<({String nodeName, String groupName})?>((ref) {
  final groups = ref.watch(proxyGroupsProvider);
  if (groups.isEmpty) return null;
  try {
    final g = groups.firstWhere(
      (g) => g.name == 'PROXIES' || g.name == 'GLOBAL' || g.name == '节点选择' || g.name == 'Proxy',
      orElse: () => groups.firstWhere((g) => g.type == 'Selector', orElse: () => groups.first),
    );
    return (nodeName: g.now, groupName: g.name);
  } catch (_) {
    return null;
  }
});

/// Maps proxy node names to their protocol type (ss, vmess, trojan, etc.).
/// Populated from the /proxies API response during ProxyGroupsNotifier.refresh().
final nodeTypeMapProvider = StateProvider<Map<String, String>>((ref) => {});

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
    NotifierProvider<ProxyGroupsNotifier, List<ProxyGroup>>(
  ProxyGroupsNotifier.new,
);

/// The mihomo GLOBAL proxy group (used in global routing mode).
/// null until the first refresh completes.
final globalGroupProvider = StateProvider<ProxyGroup?>((ref) => null);

class ProxyGroupsNotifier extends Notifier<List<ProxyGroup>> {
  @override
  List<ProxyGroup> build() => [];

  ProxyRepository get _repo => ref.read(proxyRepositoryProvider);

  /// Refresh proxy data from the running mihomo instance.
  ///
  /// Uses REST API in real mode, direct FFI in mock mode.
  Future<void> refresh() async {
    final manager = CoreManager.instance;

    Map<String, dynamic> data;
    if (manager.isMockMode) {
      // Parse real subscription YAML instead of using hardcoded mock data
      data = await _parseMockProxiesFromProfile();
      if (data.isEmpty) {
        // Fallback to CoreMock data if no profile available
        data = CoreController.instance.getProxies();
      }
    } else {
      try {
        data = await _repo.getProxies();
      } catch (_) {
        return; // API not available
      }
    }

    final proxiesMap = data['proxies'] as Map<String, dynamic>? ?? {};

    // Build groups map and extract per-node types
    final groupsMap = <String, ProxyGroup>{};
    final nodeTypes = <String, String>{};
    for (final entry in proxiesMap.entries) {
      final info = entry.value as Map<String, dynamic>;
      final type = info['type'] as String? ?? '';
      if (info.containsKey('all')) {
        groupsMap[entry.key] = ProxyGroup(
          name: entry.key,
          type: type,
          all: (info['all'] as List?)?.cast<String>() ?? [],
          now: info['now'] as String? ?? '',
        );
      } else if (type.isNotEmpty) {
        // Individual proxy node (not a group)
        nodeTypes[entry.key] = type;
      }
    }
    ref.read(nodeTypeMapProvider.notifier).state = nodeTypes;

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
      ref.read(globalGroupProvider.notifier).state = globalGroup;
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

  /// Parse proxy groups and nodes from the active profile's YAML config.
  /// Returns data in the same format as the mihomo REST API /proxies response.
  Future<Map<String, dynamic>> _parseMockProxiesFromProfile() async {
    try {
      final activeId = ref.read(activeProfileIdProvider);
      if (activeId == null) return {};
      final config = await ref.read(profileRepositoryProvider).loadConfig(activeId);
      if (config == null || config.isEmpty) return {};

      final yaml = loadYaml(config);
      if (yaml is! YamlMap) return {};

      final proxiesMap = <String, dynamic>{};

      // Parse individual proxies to get their types
      final rawProxies = yaml['proxies'];
      final proxyNames = <String>[];
      if (rawProxies is YamlList) {
        for (final p in rawProxies) {
          if (p is! YamlMap) continue;
          final name = p['name']?.toString() ?? '';
          final type = p['type']?.toString() ?? '';
          if (name.isEmpty) continue;
          proxyNames.add(name);
          proxiesMap[name] = {'type': type, 'name': name};
        }
      }

      // Parse proxy-groups
      final rawGroups = yaml['proxy-groups'];
      final groupNames = <String>[];
      if (rawGroups is YamlList) {
        for (final g in rawGroups) {
          if (g is! YamlMap) continue;
          final name = g['name']?.toString() ?? '';
          final type = g['type']?.toString() ?? '';
          if (name.isEmpty) continue;
          if (name == 'DIRECT' || name == 'REJECT') continue;

          final allRaw = g['proxies'];
          final all = <String>[];
          if (allRaw is YamlList) {
            for (final n in allRaw) {
              if (n != null) all.add(n.toString());
            }
          }

          // For 'use' field (proxy-provider references), expand provider nodes
          final useRaw = g['use'];
          if (useRaw is YamlList) {
            // Can't resolve proxy-provider nodes without mihomo API,
            // just note them as placeholder
            for (final providerName in useRaw) {
              all.add('[$providerName]');
            }
          }

          final now = all.isNotEmpty ? all.first : '';
          groupNames.add(name);
          proxiesMap[name] = {
            'type': _capitalizeGroupType(type),
            'name': name,
            'now': now,
            'all': all,
          };
        }
      }

      // Build GLOBAL group from all top-level groups
      if (groupNames.isNotEmpty) {
        proxiesMap['GLOBAL'] = {
          'type': 'Selector',
          'name': 'GLOBAL',
          'now': groupNames.first,
          'all': [...groupNames, 'DIRECT'],
        };
      }

      debugPrint('[MockProxy] parsed ${proxyNames.length} proxies, '
          '${groupNames.length} groups from profile');
      return {'proxies': proxiesMap};
    } catch (e) {
      debugPrint('[MockProxy] parse error: $e');
      return {};
    }
  }

  static String _capitalizeGroupType(String type) {
    switch (type.toLowerCase()) {
      case 'select':
        return 'Selector';
      case 'url-test':
        return 'URLTest';
      case 'fallback':
        return 'Fallback';
      case 'load-balance':
        return 'LoadBalance';
      case 'relay':
        return 'Relay';
      default:
        return type;
    }
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

final expandedGroupNamesProvider = StateProvider<Set<String>>((ref) => {});

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

    // Accumulate results in a single map — write state once at the end.
    final results = Map<String, int>.from(ref.read(delayResultsProvider));

    if (manager.isMockMode) {
      delay = await Future(() {
        return CoreController.instance.testDelay(proxyName);
      });
    } else {
      delay = await _repo.testDelayWithBatch(
        proxyName,
        url: testUrl,
        onResult: (name, d) {
          results[name] = d;
          ref.read(delayResultsProvider.notifier).state =
              Map<String, int>.from(results);
        },
      );
    }

    results[proxyName] = delay;
    ref.read(delayResultsProvider.notifier).state = results;
    SettingsService.setDelayResults(results);

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
        SettingsService.setDelayResults(current);
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
