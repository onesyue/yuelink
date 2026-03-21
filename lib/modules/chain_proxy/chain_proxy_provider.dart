import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../constants.dart';
import '../../core/kernel/config_template.dart';
import '../../core/kernel/core_manager.dart';
import '../../core/storage/settings_service.dart';
import '../../shared/app_notifier.dart';
import '../../l10n/app_strings.dart';
import '../nodes/providers/node_providers.dart';
import '../nodes/providers/nodes_providers.dart';

// ------------------------------------------------------------------
// Chain proxy state
// ------------------------------------------------------------------

class ChainProxyState {
  final List<String> nodes; // ordered: [entry, ..., exit]
  final bool connected;
  final bool loading;
  final String? activeGroup; // which proxy group the chain applies to
  final String? previousNode; // selected node in activeGroup before connect

  const ChainProxyState({
    this.nodes = const [],
    this.connected = false,
    this.loading = false,
    this.activeGroup,
    this.previousNode,
  });

  static const _clear = Object();

  ChainProxyState copyWith({
    List<String>? nodes,
    bool? connected,
    bool? loading,
    String? activeGroup,
    Object? previousNode = _clear,
  }) =>
      ChainProxyState(
        nodes: nodes ?? this.nodes,
        connected: connected ?? this.connected,
        loading: loading ?? this.loading,
        activeGroup: activeGroup ?? this.activeGroup,
        previousNode:
            identical(previousNode, _clear) ? this.previousNode : previousNode as String?,
      );

  bool get canConnect => nodes.length >= 2 && !loading;
  String? get entryNode => nodes.isNotEmpty ? nodes.first : null;
  String? get exitNode => nodes.length >= 2 ? nodes.last : null;
}

// ------------------------------------------------------------------
// Provider
// ------------------------------------------------------------------

final chainProxyProvider =
    NotifierProvider<ChainProxyNotifier, ChainProxyState>(
        ChainProxyNotifier.new);

class ChainProxyNotifier extends Notifier<ChainProxyState> {
  @override
  ChainProxyState build() {
    _restoreFromSettings();
    return const ChainProxyState();
  }

  /// Add a proxy node to the chain. Rejects duplicates.
  void addNode(String name) {
    if (state.nodes.contains(name)) {
      AppNotifier.warning(S.current.chainNodeDuplicate);
      return;
    }
    state = state.copyWith(nodes: [...state.nodes, name]);
    _persist();
  }

  /// Remove a node at [index].
  void removeNode(int index) {
    if (index < 0 || index >= state.nodes.length) return;
    final updated = [...state.nodes]..removeAt(index);
    state = state.copyWith(nodes: updated, connected: false);
    _persist();
  }

  /// Reorder nodes (drag & drop).
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final updated = [...state.nodes];
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    state = state.copyWith(nodes: updated, connected: false);
    _persist();
  }

  /// Clear the entire chain.
  void clear() {
    if (state.connected) {
      disconnect();
    }
    state = const ChainProxyState();
    _persist();
  }

  /// Set which proxy group to apply the chain to.
  void setActiveGroup(String groupName) {
    state = state.copyWith(activeGroup: groupName);
    _persist();
  }

  /// Connect: inject dialer-proxy into config, reload mihomo.
  ///
  /// Flow:
  /// 1. Read current config from disk
  /// 2. Inject dialer-proxy chain
  /// 3. Write modified config
  /// 4. Call PUT /configs?force=true to reload
  /// 5. Select exit node in the active proxy group
  Future<void> connect() async {
    if (!state.canConnect) return;
    final manager = CoreManager.instance;
    if (!manager.isRunning) {
      AppNotifier.error(S.current.chainNeedConnect);
      return;
    }

    // Resolve activeGroup: use saved value or fall back to first selector group.
    final resolvedGroup = state.activeGroup ??
        ref
            .read(proxyGroupsProvider)
            .where((g) => g.type.toLowerCase() == 'selector')
            .firstOrNull
            ?.name;
    if (resolvedGroup == null || resolvedGroup.isEmpty) {
      AppNotifier.error(S.current.chainNoGroup);
      return;
    }

    // Snapshot the currently selected node before we overwrite it.
    final previousNode = ref.read(groupSelectedNodeProvider(resolvedGroup));

    state = state.copyWith(loading: true);
    try {
      // 1. Read current running config from disk
      final appDir = await getApplicationSupportDirectory();
      final configPath = '${appDir.path}/${AppConstants.configFileName}';
      final configFile = File(configPath);
      if (!configFile.existsSync()) {
        throw Exception('Config file not found');
      }
      var config = await configFile.readAsString();

      // 2. Inject chain (relay group scoped to resolvedGroup)
      config = ConfigTemplate.injectProxyChain(config, state.nodes, resolvedGroup);

      // 3. Push YAML content directly to mihomo (avoids disk write + path reload
      //    which can fail due to YAML round-trip corruption or path issues).
      //    Also write back to disk so the file stays in sync for next start.
      await manager.api.pushConfig(config);
      await configFile.writeAsString(config);

      // 5. Wait for mihomo to finish reloading, then select relay with retry.
      // force=true reload can take >300ms on large configs / slow devices.
      await Future.delayed(const Duration(milliseconds: 400));

      // 6. Select the exit node in the active group — retry up to 3× if mihomo isn't ready.
      // dialer-proxy is set on the node itself, so selecting it triggers the chain.
      final exitNodeName = state.nodes.last;
      bool selected = false;
      for (var attempt = 0; attempt < 3 && !selected; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(milliseconds: 300));
        try {
          await manager.api.changeProxy(resolvedGroup, exitNodeName);
          selected = true;
        } catch (e) {
          debugPrint('[ChainProxy] changeProxy attempt ${attempt + 1} failed: $e');
        }
      }
      if (!selected) throw Exception('changeProxy failed after retries');

      // 7. Refresh proxy groups
      ref.read(proxyGroupsProvider.notifier).refresh();

      state = state.copyWith(
          connected: true,
          loading: false,
          activeGroup: resolvedGroup,
          previousNode: previousNode);
      AppNotifier.success(S.current.chainConnected);
    } catch (e) {
      debugPrint('[ChainProxy] connect error: $e');
      state = state.copyWith(loading: false);
      AppNotifier.error('${S.current.chainConnectFailed}: $e');
    }
  }

  /// Disconnect: remove all dialer-proxy, reload config.
  Future<void> disconnect() async {
    final manager = CoreManager.instance;
    if (!manager.isRunning) {
      state = state.copyWith(connected: false);
      return;
    }

    state = state.copyWith(loading: true);
    try {
      final appDir = await getApplicationSupportDirectory();
      final configPath = '${appDir.path}/${AppConstants.configFileName}';
      final configFile = File(configPath);
      if (configFile.existsSync()) {
        var config = await configFile.readAsString();
        config = ConfigTemplate.removeProxyChain(config);
        await manager.api.pushConfig(config);
        await configFile.writeAsString(config);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Restore the node that was selected before the chain was connected
      final groupName = state.activeGroup;
      final prev = state.previousNode;
      if (groupName != null && prev != null && prev.isNotEmpty) {
        try {
          await manager.api.changeProxy(groupName, prev);
        } catch (_) {}
      }

      // Close all existing connections to force reconnect without chain
      try {
        await manager.api.closeAllConnections();
      } catch (_) {}

      ref.read(proxyGroupsProvider.notifier).refresh();

      state = state.copyWith(connected: false, loading: false, previousNode: null);
      AppNotifier.info(S.current.chainDisconnected);
    } catch (e) {
      debugPrint('[ChainProxy] disconnect error: $e');
      state = state.copyWith(connected: false, loading: false);
    }
  }

  // ── Persistence ──────────────────────────────────────────────────

  Future<void> _persist() async {
    await SettingsService.set('chainProxy', jsonEncode({
      'nodes': state.nodes,
      'group': state.activeGroup,
    }));
  }

  Future<void> _restoreFromSettings() async {
    try {
      final raw = await SettingsService.get<String>('chainProxy');
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final nodes = (json['nodes'] as List?)?.cast<String>() ?? [];
      final group = json['group'] as String?;
      if (nodes.isNotEmpty) {
        state = ChainProxyState(nodes: nodes, activeGroup: group);
      }
    } catch (e) {
      debugPrint('[ChainProxy] restore error: $e');
    }
  }
}
