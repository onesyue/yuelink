import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:yaml/yaml.dart';

import '../../../core/providers/core_provider.dart';
import '../../../core/storage/settings_service.dart';
import '../../../domain/models/proxy.dart';
import '../../profiles/providers/profiles_providers.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../infrastructure/repositories/profile_repository.dart';
import '../../../infrastructure/repositories/proxy_repository.dart';
import '../../../shared/node_telemetry.dart';
import '../../../shared/telemetry.dart';

// ------------------------------------------------------------------
// Node sort / view mode
// ------------------------------------------------------------------

enum NodeSortMode {
  defaultOrder,
  latencyAsc,
  latencyDesc,
  nameAsc,
  smartRecommend
}

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
final activeProxyInfoProvider =
    Provider<({String nodeName, String groupName})?>((ref) {
  final groups = ref.watch(proxyGroupsProvider);
  if (groups.isEmpty) return null;
  try {
    final g = groups.firstWhere(
      (g) =>
          g.name == 'PROXIES' ||
          g.name == 'GLOBAL' ||
          g.name == '节点选择' ||
          g.name == 'Proxy',
      orElse: () => groups.firstWhere((g) => g.type == 'Selector',
          orElse: () => groups.first),
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

final offlineProxyGroupsProvider =
    FutureProvider<List<ProxyGroup>>((ref) async {
  final activeId = ref.watch(activeProfileIdProvider);
  if (activeId == null) return [];
  final config = await ref.read(profileRepositoryProvider).loadConfig(activeId);
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
  } catch (e) {
    // Offline mode silently returning [] here means the user sees an
    // empty node list with no idea why — typically the active profile's
    // YAML is malformed or truncated. Log so support can map "no groups
    // shown" to a parse error instead of guessing.
    debugPrint('[OfflineProxyGroups] YAML parse failed: $e');
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

@visibleForTesting
bool shouldFetchLiveProxyGroups({
  required CoreStatus status,
  required bool isMockMode,
}) {
  if (isMockMode) return true;
  return status == CoreStatus.running;
}

class ProxyGroupsNotifier extends Notifier<List<ProxyGroup>> {
  @override
  List<ProxyGroup> build() {
    // Auto-refresh on core startup. `core_lifecycle_manager.start()`
    // used to call `refresh()` directly after flipping status to
    // running — that was the last `core -> modules` reverse dependency
    // core_lifecycle_manager had. Listening here keeps the lifecycle
    // side free of modules/ imports; direction is modules → core.
    //
    // Manual refresh call sites (nodes_page pull-to-refresh, sync &
    // reconnect, chain proxy, resume check) continue to work
    // unchanged — this listener only covers the initial fetch.
    ref.listen<CoreStatus>(coreStatusProvider, (prev, next) {
      if (prev != null &&
          prev != CoreStatus.running &&
          next == CoreStatus.running) {
        refresh();
      }
    });
    return [];
  }

  ProxyRepository get _repo => ref.read(proxyRepositoryProvider);

  /// Refresh proxy data from the running mihomo instance.
  ///
  /// Uses REST API in real mode, direct FFI in mock mode.
  Future<void> refresh() async {
    final manager = CoreManager.instance;
    final status = ref.read(coreStatusProvider);

    Map<String, dynamic> data;
    if (manager.isMockMode) {
      // Parse real subscription YAML instead of using hardcoded mock data
      data = await _parseMockProxiesFromProfile();
      if (data.isEmpty) {
        // Fallback to canned mock data if no profile available
        data = await manager.core.getProxies();
      }
    } else {
      if (!shouldFetchLiveProxyGroups(
        status: status,
        isMockMode: manager.isMockMode,
      )) {
        return;
      }
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
    // Group types that should be treated as proxy groups even if `all` is null
    const groupTypes = {
      'Selector',
      'URLTest',
      'Fallback',
      'LoadBalance',
      'Relay'
    };
    for (final entry in proxiesMap.entries) {
      final info = entry.value as Map<String, dynamic>;
      final type = info['type'] as String? ?? '';
      final isGroup = info.containsKey('all') || groupTypes.contains(type);
      if (isGroup) {
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
      final filteredAll =
          allNames.where((n) => groupsMap.containsKey(n)).toList();
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
      final config =
          await ref.read(profileRepositoryProvider).loadConfig(activeId);
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
      ok = await manager.core.changeProxy(groupName, proxyName);
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
final testUrlProvider =
    StateProvider<String>((ref) => 'https://www.gstatic.com/generate_204');

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
  ///
  /// The unmark step is wrapped in `try/finally` so the node doesn't stay
  /// stuck showing "testing…" in the UI when the await below throws
  /// (network error, core restart, timeout). Previously the unmark was
  /// unreachable on the error path and the user had to refresh the page
  /// to clear the stale state.
  Future<int> testDelay(String proxyName) async {
    final testing = Set<String>.from(ref.read(delayTestingProvider));
    testing.add(proxyName);
    ref.read(delayTestingProvider.notifier).state = testing;

    try {
      final manager = CoreManager.instance;
      final testUrl = ref.read(testUrlProvider);
      int delay;

      // Accumulate results in a single map — write state once at the end.
      final results = Map<String, int>.from(ref.read(delayResultsProvider));

      if (manager.isMockMode) {
        delay = await manager.core.testDelay(proxyName);
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

      // Opt-in telemetry — anonymous fingerprint + latency only.
      NodeTelemetry.recordUrlTestByName(name: proxyName, delayMs: delay);

      return delay;
    } finally {
      final doneSet = Set<String>.from(ref.read(delayTestingProvider));
      doneSet.remove(proxyName);
      ref.read(delayTestingProvider.notifier).state = doneSet;
    }
  }

  /// Test all proxies in a group.
  ///
  /// In real mode, uses the REST API group delay test (parallel).
  /// In mock mode, falls back to sequential testing.
  ///
  /// Auto-recovery: when the HTTP call succeeds but the result map shows
  /// every node as timed-out (mihomo's DNS / fake-IP / connection pool
  /// carrying stale state from a previous session), we silently flush
  /// client-side connections + fake-IP cache and retry up to twice
  /// before surfacing the failure.
  ///
  /// Bug this fixes: after "disconnect → reconnect → test speed" the
  /// whole group used to flash red because mihomo's internal state from
  /// the previous session was not fully reset by stop→start. Users had
  /// to either wait, reopen the app, or hit the manual "restart core"
  /// button in connection_repair_page.
  Future<void> testGroup(String groupName, List<String> proxyNames) async {
    final manager = CoreManager.instance;

    if (!manager.isMockMode) {
      final testing = Set<String>.from(ref.read(delayTestingProvider));
      testing.addAll(proxyNames);
      ref.read(delayTestingProvider.notifier).state = testing;

      final testUrl = ref.read(testUrlProvider);
      try {
        var results = await _repo.testGroupDelay(groupName, url: testUrl);

        if (_isAllTimeout(results, proxyNames)) {
          Telemetry.event(
            TelemetryEvents.delayTestAllTimeout,
            props: {'group': groupName, 'count': proxyNames.length},
          );
          // Silent recovery: up to 2 rounds of (close connections +
          // flush fake-IP cache + wait + retry). 1.5 s per round gives
          // mihomo enough time to rebuild its DNS resolver and
          // proxy-chain pools; 800 ms wasn't enough for first-test-
          // after-reconnect on slow networks.
          for (var attempt = 1; attempt <= 2; attempt++) {
            try {
              await manager.api.closeAllConnections();
            } catch (_) {}
            try {
              await manager.api.flushFakeIpCache();
            } catch (_) {}
            await Future.delayed(const Duration(milliseconds: 1500));
            final retried =
                await _repo.testGroupDelay(groupName, url: testUrl);
            if (!_isAllTimeout(retried, proxyNames)) {
              Telemetry.event(TelemetryEvents.delayTestAutoRecovered);
              results = retried;
              break;
            }
          }
        }

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

        // Opt-in telemetry — one event per tested node.
        for (final entry in current.entries) {
          if (proxyNames.contains(entry.key)) {
            NodeTelemetry.recordUrlTestByName(
              name: entry.key,
              delayMs: entry.value,
            );
          }
        }
      } catch (e) {
        // Group test failure surfaces to the user as every node showing
        // a timeout dot — without a log line, the actual cause (HTTP
        // 4xx/5xx from mihomo, network drop, auth token rejection) is
        // invisible. Log once with context before marking nodes failed.
        debugPrint(
            '[DelayTest] group "$groupName" (${proxyNames.length} nodes) '
            'failed: $e');
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

  // Treat a group-test result as "all timed out" when at least 3 of the
  // requested nodes came back with delay <= 0. The floor of 3 avoids
  // false positives on truly tiny groups (a 2-proxy DIRECT/REJECT setup
  // where 0 is legitimate) while still catching the real failure mode
  // where every proxy in a group reports 0. Dropped from 5 so that
  // user-curated groups (e.g. 3-4 hand-picked nodes) also get the
  // auto-recovery path after a reconnect.
  bool _isAllTimeout(Map<String, dynamic> results, List<String> proxyNames) {
    if (proxyNames.length < 3) return false;
    var checked = 0;
    var timedOut = 0;
    for (final name in proxyNames) {
      final v = results[name];
      int? delay;
      if (v is int) {
        delay = v;
      } else if (v is Map) {
        delay = (v['delay'] as num?)?.toInt();
      }
      if (delay == null) continue;
      checked++;
      if (delay <= 0) timedOut++;
    }
    if (checked < 3) return false;
    return timedOut / checked >= 0.9;
  }
}
