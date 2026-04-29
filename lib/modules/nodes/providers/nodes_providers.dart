import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:yaml/yaml.dart';

import '../../../core/providers/core_provider.dart';
import '../../../domain/models/proxy.dart';
import '../../profiles/providers/profiles_providers.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../infrastructure/repositories/profile_repository.dart';
import '../../../infrastructure/repositories/proxy_repository.dart';

// Re-export latency-testing surface so existing call sites keep working
// after the split: every widget that imports `nodes_providers.dart` for
// delayResultsProvider / delayTestProvider / DelayTestActions / etc.
// continues to compile unchanged.
export 'delay_test_providers.dart';

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
  /// Background-retry timer for the empty-on-startup case. Subscriptions
  /// with proxy-providers / rule-providers that fetch from the network
  /// can take 30–60 s to fully materialise the proxy graph after mihomo
  /// starts. Without retry, the dashboard would show "处理中..." until
  /// the user manually pulled-to-refresh on the Nodes page.
  Timer? _emptyRetry;

  /// Cleared once we've ever seen a non-empty groups state in this
  /// session. After that, downstream listeners (heartbeat, manual refresh)
  /// are sufficient — no need to keep re-polling.
  bool _seenNonEmpty = false;

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
        _seenNonEmpty = false;
        refresh();
      }
      // Cancel any pending retry when leaving the running state.
      if (next != CoreStatus.running) {
        _emptyRetry?.cancel();
        _emptyRetry = null;
      }
    });
    ref.onDispose(() {
      _emptyRetry?.cancel();
      _emptyRetry = null;
    });
    // Edge case the listener can't catch: if `build()` runs *after* the
    // status has already transitioned to running (cold-start auto-
    // connect, resume-into-running, or any path where the dashboard
    // first watches proxyGroupsProvider only once the HeroCard rebuilds
    // with isRunning == true), `ref.listen` will not retroactively
    // replay the prev→next transition. Without this kick the dashboard
    // shows '处理中' forever and the Nodes page sits on a
    // CupertinoActivityIndicator — exact symptom from the v1.0.23-pre
    // Android + Windows reports (2026-04-28). Microtask defer because
    // calling refresh() inside build() throws — Notifier state is not
    // yet returned.
    if (ref.read(coreStatusProvider) == CoreStatus.running) {
      Future.microtask(refresh);
    }
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
    // Skip the state assignment when nothing actually changed. Riverpod
    // short-circuits on `==`, but `List<ProxyGroup>` equality is identity
    // by default — different list instances with the same content would
    // still trigger every watcher. Now that `ProxyGroup` is fully
    // immutable with structural `==`, `listEquals` gives us a real
    // value comparison: when mihomo's `/proxies` polls return the same
    // payload (the common case) we skip the entire downstream rebuild
    // chain (nodes_page → SliverList → all GroupCards).
    if (listEquals(state, groups)) {
      _maybeScheduleEmptyRetry(groups);
      return;
    }
    state = groups;
    _maybeScheduleEmptyRetry(groups);
  }

  /// If we just refreshed and got an empty graph but the core is running,
  /// schedule a one-shot retry. Repeat with a fixed 3-s gap up to 10
  /// attempts (~30 s) — by then either the proxy-providers have fetched
  /// or the user's network is genuinely broken and a `[]` graph is
  /// correct. Once we've ever seen a non-empty graph in this session,
  /// disarm: heartbeat + manual refresh handle steady-state updates.
  void _maybeScheduleEmptyRetry(List<ProxyGroup> latest) {
    if (latest.isNotEmpty) {
      _seenNonEmpty = true;
      _emptyRetry?.cancel();
      _emptyRetry = null;
      return;
    }
    if (_seenNonEmpty) return;
    if (ref.read(coreStatusProvider) != CoreStatus.running) return;
    if (CoreManager.instance.isMockMode) return;
    if (_emptyRetry != null) return; // one timer at a time
    _emptyRetry = Timer(const Duration(seconds: 3), () {
      _emptyRetry = null;
      // Re-check status — user may have stopped between schedule and fire.
      if (ref.read(coreStatusProvider) != CoreStatus.running) return;
      refresh();
    });
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
  ///
  /// Returns false (never throws) so the calling tile's spinner can always
  /// reset — earlier versions let `TimeoutException` from a hung PUT bubble
  /// up, leaving `_isSwitching = true` permanently.
  ///
  /// On PUT success we **optimistically** update local `state.now` instead
  /// of waiting for the next `/proxies` GET to confirm. mihomo applies the
  /// switch synchronously when it returns 204 — traffic is already on the
  /// new node before we even hit `await`. Waiting on `refresh()` had two
  /// nasty failure modes (real-world report, 2026-04-29):
  ///   1. `getProxies()` fails or times out → `try { } catch (_) { return; }`
  ///      in [refresh] silently swallows it → state stays at old `now` →
  ///      UI sticks on the previous selection forever even though traffic
  ///      already flipped. User-visible: "切换不生效，卡在台湾".
  ///   2. PUT body decode + GET round-trip = 100–500 ms wall-clock. The
  ///      spinner spins that whole window for no reason.
  /// Background `refresh()` reconciles any drift (URLTest groups whose
  /// `now` mihomo decides itself, etc.) within ~200 ms.
  Future<bool> changeProxy(String groupName, String proxyName) async {
    final manager = CoreManager.instance;

    bool ok;
    try {
      if (manager.isMockMode) {
        ok = await manager.core.changeProxy(groupName, proxyName);
      } else {
        ok = await _repo.changeProxy(groupName, proxyName);
      }
    } catch (e) {
      debugPrint('[ProxyGroups] changeProxy threw: $e');
      return false;
    }

    if (ok) {
      _applyOptimisticSelection(groupName, proxyName);
      // Fire-and-forget — must not block the caller's spinner reset.
      unawaited(refresh());
    }
    return ok;
  }

  /// Patch the `now` field of [groupName] in local state without touching
  /// any other group. Used by [changeProxy] right after PUT 204 so the
  /// check-mark / selection badge follow the user's tap immediately.
  void _applyOptimisticSelection(String groupName, String proxyName) {
    if (state.isEmpty) return;
    var changed = false;
    final updated = <ProxyGroup>[];
    for (final g in state) {
      if (g.name == groupName && g.now != proxyName) {
        updated.add(ProxyGroup(
          name: g.name,
          type: g.type,
          all: g.all,
          now: proxyName,
        ));
        changed = true;
      } else {
        updated.add(g);
      }
    }
    if (changed) state = updated;
  }
}


/// Persisted "which groups are expanded" UI state. Lives next to
/// proxyGroupsProvider rather than the latency-testing surface because
/// it has nothing to do with delay tests — `_GroupCardState` reads it
/// to restore expansion across rebuilds.
final expandedGroupNamesProvider = StateProvider<Set<String>>((ref) => {});
