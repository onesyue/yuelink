import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../core/storage/settings_service.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../providers/nodes_providers.dart';
import '../scene_mode/scene_mode.dart';
import '../scene_mode/scene_mode_provider.dart';
import 'smart_select_result.dart';
import 'smart_select_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class SmartSelectState {
  final bool isTesting;

  /// Number of nodes tested so far (for progress display).
  final int testedCount;

  /// Total nodes to test in the current run.
  final int totalCount;

  /// Completed result. Null if no run has finished yet.
  /// During a background refresh this holds the previous cached result until
  /// the first group of the new test finishes.
  final SmartSelectResult? result;

  /// Non-null when the last run failed with an error.
  final String? error;

  /// Non-null when [result] was loaded from (or was just saved to) the local
  /// cache. Carries timestamp and scene metadata for UI display.
  final SmartSelectCache? cache;

  const SmartSelectState({
    this.isTesting = false,
    this.testedCount = 0,
    this.totalCount = 0,
    this.result,
    this.error,
    this.cache,
  });

  SmartSelectState copyWith({
    bool? isTesting,
    int? testedCount,
    int? totalCount,
    SmartSelectResult? result,
    String? error,
    SmartSelectCache? cache,
  }) =>
      SmartSelectState(
        isTesting: isTesting ?? this.isTesting,
        testedCount: testedCount ?? this.testedCount,
        totalCount: totalCount ?? this.totalCount,
        result: result ?? this.result,
        error: error,
        cache: cache ?? this.cache,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class SmartSelectNotifier extends StateNotifier<SmartSelectState> {
  final Ref _ref;

  SmartSelectNotifier(this._ref) : super(const SmartSelectState());

  // ── Initialise on sheet open ──────────────────────────────────────────────

  /// Called by the sheet on open. Loads a cached result if available:
  /// - Same scene + fresh  (< 5 min): show immediately, do NOT auto-refresh.
  /// - Same scene + stale (≥ 5 min): show immediately, start background refresh.
  /// - Different scene or no cache:   start a fresh test.
  Future<void> initialize() async {
    if (state.isTesting) return;

    final cached = await _loadCache();
    final currentScene =
        _ref.read(sceneModeProvider).valueOrNull?.name ?? SceneMode.daily.name;

    if (cached != null && cached.sceneMode == currentScene) {
      // Show cached result immediately regardless of freshness.
      state = SmartSelectState(
        result: cached.toResult(),
        cache: cached,
      );
      if (!cached.isFresh) {
        // Stale: refresh in the background while the old result stays visible.
        runTest();
      }
    } else {
      // No cache or wrong scene: auto-start fresh test.
      if (state.result == null && state.error == null) runTest();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<SmartSelectCache?> _loadCache() async {
    try {
      final raw = await SettingsService.getSmartSelectCache();
      if (raw == null) return null;
      return SmartSelectCache.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(SmartSelectResult result) async {
    final sceneMode =
        _ref.read(sceneModeProvider).valueOrNull?.name ?? SceneMode.daily.name;
    final cache = SmartSelectCache(
      top: result.top,
      totalTested: result.totalTested,
      totalAvailable: result.totalAvailable,
      timestamp: DateTime.now(),
      sceneMode: sceneMode,
    );
    try {
      await SettingsService.setSmartSelectCache(cache.toJson());
    } catch (_) {
      // Non-fatal: worst case the user re-tests next time.
    }
  }

  // ── Main selector group ───────────────────────────────────────────────────

  String _findMainGroupName() {
    final groups = _ref.read(proxyGroupsProvider);
    if (groups.isEmpty) return '';
    try {
      return groups
          .firstWhere(
            (g) =>
                g.name == 'PROXIES' ||
                g.name == '节点选择' ||
                g.name == 'Proxy',
            orElse: () => groups.firstWhere(
              (g) => g.type == 'Selector',
              orElse: () => groups.first,
            ),
          )
          .name;
    } catch (_) {
      return groups.isNotEmpty ? groups.first.name : '';
    }
  }

  // ── Run a full delay-test pass ────────────────────────────────────────────

  /// Runs a full delay-test pass and emits progressive results.
  ///
  /// Preserves [state.cache] during the run so the UI can still show the
  /// previous cached result while the background refresh is in progress.
  Future<void> runTest() async {
    if (state.isTesting) return;

    // Keep previous cache visible during the refresh.
    final prevCache = state.cache;
    state = SmartSelectState(isTesting: true, cache: prevCache);

    try {
      if (!CoreManager.instance.isRunning && !CoreManager.instance.isMockMode) {
        state = SmartSelectState(error: S.current.chainNeedConnect);
        return;
      }

      final groups = _ref.read(proxyGroupsProvider);
      final nodeTypes = _ref.read(nodeTypeMapProvider);
      final mainGroupName = _findMainGroupName();

      if (mainGroupName.isEmpty || groups.isEmpty) {
        state = const SmartSelectState(error: '未找到代理节点，请先连接');
        return;
      }

      final candidates = SmartSelectService.collectCandidates(
        groups: groups,
        nodeTypes: nodeTypes,
        mainGroupName: mainGroupName,
      );

      if (candidates.isEmpty) {
        state = const SmartSelectState(error: '没有可测试的节点，请检查订阅');
        return;
      }

      state = SmartSelectState(
        isTesting: true,
        totalCount: candidates.length,
        testedCount: 0,
        // Keep previous cached result in view while the new test runs.
        result: prevCache?.toResult(),
        cache: prevCache,
      );

      // ── Concurrent group testing ──────────────────────────────────────────
      // Group candidates by primaryGroup. Each group is tested via a single
      // mihomo /group/{name}/delay call (internally concurrent per group).
      // All groups run in parallel via Future.wait.
      // Worst-case: max(group_timeout) ≈ 7s instead of 40 × 5s = 200s.
      final byGroup = <String, List<SmartSelectCandidate>>{};
      for (final c in candidates) {
        (byGroup[c.primaryGroup] ??= []).add(c);
      }

      final delayActions = _ref.read(delayTestProvider);
      final sceneConfig = _ref.read(sceneModeConfigProvider);
      var testedSoFar = 0;

      await Future.wait(
        byGroup.entries.map((entry) async {
          final groupName = entry.key;
          final nodeNames = entry.value.map((c) => c.name).toList();
          try {
            await delayActions
                .testGroup(groupName, nodeNames)
                .timeout(const Duration(seconds: 7));
          } on Exception catch (_) {
            // Per-group timeout or API error — nodes remain at -1.
          }
          if (!mounted) return;

          testedSoFar += nodeNames.length;

          // Emit a partial result after each group so the UI can show
          // preliminary rankings as region groups complete one by one.
          // testedCount > 0 signals the sheet that this is a live partial,
          // not the initial cached result.
          final delays = _ref.read(delayResultsProvider);
          final partial = SmartSelectService.buildResult(
            candidates: candidates,
            delays: delays,
            nodeTypes: nodeTypes,
            sceneConfig: sceneConfig,
          );
          if (mounted) {
            state = SmartSelectState(
              isTesting: true,
              totalCount: candidates.length,
              testedCount: testedSoFar,
              result: partial,
              cache: prevCache, // keep old cache metadata until we save new one
            );
          }
        }).toList(),
      );

      if (!mounted) return;

      // Final ranking with all results collected.
      final delays = _ref.read(delayResultsProvider);
      final result = SmartSelectService.buildResult(
        candidates: candidates,
        delays: delays,
        nodeTypes: nodeTypes,
        sceneConfig: sceneConfig,
      );

      // Persist before updating state so isFresh is true immediately.
      await _saveCache(result);

      if (!mounted) return;

      // Build the fresh cache object to show the correct age label.
      final sceneMode =
          _ref.read(sceneModeProvider).valueOrNull?.name ?? SceneMode.daily.name;
      final newCache = SmartSelectCache(
        top: result.top,
        totalTested: result.totalTested,
        totalAvailable: result.totalAvailable,
        timestamp: DateTime.now(),
        sceneMode: sceneMode,
      );
      state = SmartSelectState(result: result, cache: newCache);
    } catch (e) {
      if (mounted) state = SmartSelectState(error: '测速失败: $e');
    }
  }

  // ── Apply ─────────────────────────────────────────────────────────────────

  /// Apply a recommended node (calls changeProxy up to 2 times).
  Future<void> applyNode(ScoredNode node) async {
    try {
      final notifier = _ref.read(proxyGroupsProvider.notifier);

      // Step 1: switch node's direct parent group to the node
      final ok = await notifier.changeProxy(
        node.primaryGroup,
        node.primarySelection,
      );
      if (!ok) {
        AppNotifier.error('切换失败');
        return;
      }

      // Step 2: if node lives in a sub-group, switch the main group to that sub-group
      if (node.secondaryGroup != null && node.secondarySelection != null) {
        await notifier.changeProxy(
          node.secondaryGroup!,
          node.secondarySelection!,
        );
      }

      AppNotifier.success('已切换到 ${node.name}');
    } catch (e) {
      AppNotifier.error('切换失败: $e');
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Reset to initial state (clears previous results and cache reference).
  void reset() => state = const SmartSelectState();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final smartSelectProvider =
    StateNotifierProvider<SmartSelectNotifier, SmartSelectState>(
  (ref) => SmartSelectNotifier(ref),
);
