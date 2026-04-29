import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';

import '../core/kernel/core_manager.dart';
import '../core/providers/core_provider.dart';
import '../domain/models/proxy.dart';
import '../i18n/app_strings.dart';
import '../modules/dashboard/mode_actions.dart';
import '../modules/nodes/favorites/node_favorites_providers.dart';
import '../modules/nodes/providers/nodes_providers.dart';
import '../modules/yue_auth/providers/yue_auth_providers.dart';
import '../shared/app_notifier.dart';
import '../shared/event_log.dart';

/// Owns the system-tray icon, context menu, and menu-click dispatch for
/// desktop builds. Previously inlined in `_YueLinkAppState` (lib/main.dart,
/// ~360 lines).
///
/// The controller intentionally stays independent of the root widget by
/// receiving everything it needs as constructor callbacks:
///   - `ref`                         — Riverpod access for provider reads
///   - `showMainWindow()`            — focus/raise the main window
///   - `loadSelectedProfileConfig()` — return YAML for the active profile,
///                                     or null when none is available
///   - `onQuit()`                    — trigger the app's unified quit path
///                                     (stays in main.dart because it
///                                     touches window + process lifecycle)
///
/// The controller implements [TrayListener] itself and registers with
/// [trayManager] inside [init] / [dispose]; `_YueLinkAppState` no longer
/// needs the mixin.
/// Format the tray tooltip / menu-header line. Pure function so the
/// rule set is testable without spinning up a real tray binding.
///
/// v1.0.22 P2-2: extends the previous "YueLink · 已连接 · {node}"
/// shape with the current routing mode (rule/global/direct) and
/// the desktop connection mode (TUN / 系统代理). Surfaces the same
/// state the user can see on the dashboard pills + the tray menu's
/// 模式 submenu, so a glance at the system tray icon's hover text
/// is enough to identify the active configuration without opening
/// the main window.
///
/// Mobile callers pass `isDesktop: false` — connection mode is
/// implicit (always VPN/TUN) and the `TUN/系统代理` label is
/// omitted. Routing mode is still surfaced.
String formatTrayStatusLine({
  required bool isLoggedIn,
  required CoreStatus status,
  required String? currentNode,
  required String routingMode,
  required String connectionMode,
  required bool isDesktop,
}) {
  if (!isLoggedIn) return 'YueLink · 未登录';
  if (status == CoreStatus.starting) return 'YueLink · 连接中...';
  if (status != CoreStatus.running) return 'YueLink · 未连接';

  final routing = switch (routingMode) {
    'rule' => '规则',
    'global' => '全局',
    'direct' => '直连',
    _ => routingMode,
  };
  final connection =
      isDesktop ? (connectionMode == 'tun' ? 'TUN' : '系统代理') : null;
  final node = (currentNode != null && currentNode.isNotEmpty)
      ? _truncateForTray(currentNode, 16)
      : null;

  return [
    'YueLink',
    '已连接',
    routing,
    ?connection,
    ?node,
  ].join(' · ');
}

String _truncateForTray(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

class AppTrayController with TrayListener {
  AppTrayController({
    required this.ref,
    required this.showMainWindow,
    required this.loadSelectedProfileConfig,
    required this.onQuit,
  });

  final WidgetRef ref;
  final Future<void> Function() showMainWindow;
  final Future<String?> Function() loadSelectedProfileConfig;
  final Future<void> Function() onQuit;

  bool _trayInitialized = false;
  String? _currentIconPath;

  bool get isInitialized => _trayInitialized;

  Future<void> init() async {
    try {
      if (Platform.isWindows) {
        // Windows: keep the colored brand .ico, set once at init and
        // never swapped — same behaviour as v1.0.25. The system tray
        // accepts colored artwork directly; a monochrome template
        // variant disappears on the light theme.
        await trayManager.setIcon('assets/app_icon_tray.ico');
      } else {
        // macOS: pick the right colour variant for the initial state.
        await _applyMacIcon(CoreStatus.stopped);
      }
      _trayInitialized = true;
      await updateMenu(status: CoreStatus.stopped, groups: const []);
      trayManager.addListener(this);
    } catch (e) {
      debugPrint('[Tray] init failed: $e');
    }
  }

  /// macOS-only: swap the brand mark between black (stopped) and white
  /// (running). The user wants the icon to *change colour* on connect
  /// ("未连接深色 / 已连接浅色"), so we deliberately do NOT use
  /// NSImage's `isTemplate` mode (template mode would let the system
  /// tint the alpha to match the menu-bar appearance instead of
  /// honouring the connection state).
  Future<void> _applyMacIcon(CoreStatus status) async {
    final iconPath = status == CoreStatus.running
        ? 'assets/tray_icon_macos_white.png'
        : 'assets/tray_icon_macos.png';
    if (iconPath == _currentIconPath) return;
    await trayManager.setIcon(iconPath);
    _currentIconPath = iconPath;
  }

  void dispose() {
    if (_trayInitialized) {
      trayManager.removeListener(this);
    }
  }

  Future<void> updateMenu({
    required CoreStatus status,
    List<ProxyGroup>? groups,
  }) async {
    if (!_trayInitialized) return;
    // macOS only: swap the menu-bar icon to match the new connection
    // state. Windows stays on the colored .ico set at init() — see
    // there for the rationale.
    if (Platform.isMacOS) {
      unawaited(_applyMacIcon(status));
    }
    final s = S.current;
    final isRunning = status == CoreStatus.running;
    final isConnecting = status == CoreStatus.starting;
    final auth = ref.read(authProvider);
    final isLoggedIn = auth.isLoggedIn;

    // ── Status line ──
    // v1.0.22 P2-2: now includes routing + connection mode so a
    // glance at the tray tooltip identifies the full active
    // configuration without opening the main window.
    final statusLine = formatTrayStatusLine(
      isLoggedIn: isLoggedIn,
      status: status,
      currentNode: isRunning ? _getCurrentNodeName(groups) : null,
      routingMode: ref.read(routingModeProvider),
      connectionMode: ref.read(connectionModeProvider),
      isDesktop: Platform.isMacOS || Platform.isWindows || Platform.isLinux,
    );

    // Update tooltip
    trayManager.setToolTip(statusLine).ignore();

    // ── Build menu items ──
    final items = <MenuItem>[];

    // 1. Status header (disabled label)
    items.add(MenuItem(key: '_status', label: statusLine));
    items.add(MenuItem.separator());

    // 2. Connect / Disconnect
    if (isConnecting) {
      items.add(MenuItem(key: '_connecting', label: '连接中，请稍候...'));
    } else if (isRunning) {
      items.add(MenuItem(key: 'disconnect', label: s.trayDisconnect));
      items.add(MenuItem(key: 'best_node', label: '连接最佳节点'));
    } else {
      items.add(MenuItem(key: 'connect', label: s.trayConnect));
      items.add(MenuItem(key: 'best_node', label: '连接最佳节点'));
    }
    items.add(MenuItem.separator());

    // 3. Recent nodes (max 5)
    final recentNodes = ref.read(recentNodesProvider);
    if (recentNodes.isNotEmpty) {
      final recentItems = <MenuItem>[];
      for (var i = 0; i < recentNodes.length; i++) {
        final node = recentNodes[i];
        recentItems.add(
          MenuItem(key: 'recent_$i', label: _truncate(node.name, 20)),
        );
      }
      items.add(
        MenuItem.submenu(
          label: '最近节点',
          submenu: Menu(items: recentItems),
        ),
      );
    }

    // 4. Proxy groups quick switch (when running)
    if (isRunning && groups != null && groups.isNotEmpty) {
      final proxySubMenus = <MenuItem>[];
      final selectors = groups
          .where((g) => g.type.toLowerCase() == 'selector')
          .take(3)
          .toList();
      for (var gi = 0; gi < selectors.length; gi++) {
        final group = selectors[gi];
        final nodeItems = <MenuItem>[];
        final nodes = group.all.take(10).toList();
        for (var ni = 0; ni < nodes.length; ni++) {
          final node = nodes[ni];
          nodeItems.add(
            MenuItem(
              key: 'proxy_${gi}_$ni',
              label: node == group.now ? '✓ $node' : '  $node',
            ),
          );
        }
        if (nodeItems.isNotEmpty) {
          proxySubMenus.add(
            MenuItem.submenu(
              label: group.name,
              submenu: Menu(items: nodeItems),
            ),
          );
        }
      }
      if (proxySubMenus.isNotEmpty) {
        items.add(
          MenuItem.submenu(
            label: s.trayProxies,
            submenu: Menu(items: proxySubMenus),
          ),
        );
      }
    }

    // 4b. Mode quick-switch (v1.0.21 hotfix P2-6).
    // Was missing entirely in v1.0.20 — users asked for tray-level
    // routing (rule/global/direct) and transport (systemProxy/TUN)
    // switches so they don't have to open the main window for what
    // should be a one-click change. Logic goes through ModeActions
    // so the HeroCard pill and this menu can never drift apart.
    final currentRoutingMode = ref.read(routingModeProvider);
    final routingItems = <MenuItem>[
      MenuItem(
        key: 'mode_route_rule',
        label:
            '${currentRoutingMode == 'rule' ? '✓ ' : '  '}${s.routeModeRule}',
      ),
      MenuItem(
        key: 'mode_route_global',
        label:
            '${currentRoutingMode == 'global' ? '✓ ' : '  '}${s.routeModeGlobal}',
      ),
      MenuItem(
        key: 'mode_route_direct',
        label:
            '${currentRoutingMode == 'direct' ? '✓ ' : '  '}${s.routeModeDirect}',
      ),
    ];
    // Transport (systemProxy/TUN) — desktop only; mobile is always VPN/TUN
    // regardless of this setting so the menu would be misleading there.
    final transportItems = <MenuItem>[];
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final currentConnMode = ref.read(connectionModeProvider);
      transportItems.addAll([
        MenuItem.separator(),
        MenuItem(
          key: 'mode_conn_systemProxy',
          label: '${currentConnMode == 'systemProxy' ? '✓ ' : '  '}系统代理',
        ),
        MenuItem(
          key: 'mode_conn_tun',
          label: '${currentConnMode == 'tun' ? '✓ ' : '  '}TUN',
        ),
      ]);
    }
    items.add(
      MenuItem.submenu(
        label: '模式',
        submenu: Menu(items: [...routingItems, ...transportItems]),
      ),
    );

    // 5. Basic status info (when running)
    if (isRunning) {
      items.add(MenuItem.separator());
      final mode = ref.read(connectionModeProvider);
      final modeName = mode == 'tun' ? 'TUN' : '系统代理';
      final profile = auth.userProfile;
      final statusItems = <MenuItem>[
        MenuItem(key: '_mode', label: '模式：$modeName'),
      ];
      if (profile != null && profile.transferEnable != null) {
        final used = (profile.uploadUsed ?? 0) + (profile.downloadUsed ?? 0);
        final total = profile.transferEnable!;
        final usedGb = (used / 1073741824).toStringAsFixed(1);
        final totalGb = (total / 1073741824).toStringAsFixed(0);
        statusItems.add(
          MenuItem(key: '_traffic', label: '流量：$usedGb GB / $totalGb GB'),
        );
      }
      items.add(
        MenuItem.submenu(
          label: '基础状态',
          submenu: Menu(items: statusItems),
        ),
      );
    }

    items.add(MenuItem.separator());

    // 6. Actions
    items.add(MenuItem(key: 'show', label: s.trayShowWindow));
    items.add(MenuItem(key: 'sync', label: '更新订阅'));
    items.add(MenuItem.separator());
    items.add(MenuItem(key: 'quit', label: s.trayQuit));

    try {
      await trayManager.setContextMenu(Menu(items: items));
    } catch (e) {
      debugPrint('[Tray] menu update: $e');
    }
  }

  /// Get the currently selected node name from the first selector group.
  String? _getCurrentNodeName(List<ProxyGroup>? groups) {
    if (groups == null || groups.isEmpty) return null;
    final selector = groups
        .where((g) => g.type.toLowerCase() == 'selector')
        .firstOrNull;
    return selector?.now;
  }

  /// Truncate a string for tray display.
  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  // Resolves a proxy_gi_ni key to (groupName, nodeName) using current groups.
  (String, String)? _resolveProxyKey(String key) {
    final parts = key.split('_');
    if (parts.length != 3) return null;
    final gi = int.tryParse(parts[1]);
    final ni = int.tryParse(parts[2]);
    if (gi == null || ni == null) return null;
    final groups = ref
        .read(proxyGroupsProvider)
        .where((g) => g.type.toLowerCase() == 'selector')
        .take(3)
        .toList();
    if (gi >= groups.length) return null;
    final group = groups[gi];
    final nodes = group.all.take(10).toList();
    if (ni >= nodes.length) return null;
    return (group.name, nodes[ni]);
  }

  @override
  void onTrayIconMouseDown() {
    if (Platform.isMacOS) {
      // macOS: left-click shows menu (standard menu bar behavior)
      trayManager.popUpContextMenu();
    } else {
      // Windows: left-click toggles window
      showMainWindow();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key ?? '';
    // Write every tray click to event.log so if a user reports "Quit
    // doesn't exit" we can confirm from the log file whether the
    // callback actually fired (and with what key).
    debugPrint('[Tray] menu click: key="$key" label="${menuItem.label}"');
    try {
      EventLog.write('[Tray] click key=$key label=${menuItem.label}');
    } catch (_) {}

    // Unified quit path — onQuit awaits the system-proxy clear (critical
    // on macOS, where fire-and-forget would have exit(0) race past the
    // networksetup subprocesses), and carries its own 3s hard-cap safety
    // timer so this can't hang. Previous fire-and-forget implementation
    // was dropping the clear entirely on fast machines.
    if (key == 'quit' || menuItem.label == S.current.trayQuit) {
      unawaited(onQuit());
      return;
    }

    // All other tray items continue async.
    _dispatchTrayMenuItemAsync(key);
  }

  Future<void> _dispatchTrayMenuItemAsync(String key) async {
    // Status header: the top "YueLink · 已连接 · <node>" line. Treat a click
    // on it as a shortcut to the main window so users don't have to scroll
    // down to the explicit "显示窗口" item.
    if (key == '_status') {
      await showMainWindow();
      return;
    }
    // Ignore other disabled status labels (mode / traffic submenu entries).
    if (key.startsWith('_')) return;

    if (key.startsWith('proxy_')) {
      final resolved = _resolveProxyKey(key);
      if (resolved != null) {
        ref
            .read(proxyGroupsProvider.notifier)
            .changeProxy(resolved.$1, resolved.$2);
      }
      return;
    }

    if (key.startsWith('recent_')) {
      final idx = int.tryParse(key.substring(7));
      if (idx != null) await _handleRecentNodeSwitch(idx);
      return;
    }

    // v1.0.21 hotfix P2-6: tray mode quick-switch. Key shape:
    //   mode_route_{rule|global|direct}
    //   mode_conn_{systemProxy|tun}
    // Dispatch to the shared ModeActions so behaviour matches the
    // HeroCard pill exactly.
    if (key.startsWith('mode_route_')) {
      final mode = key.substring('mode_route_'.length);
      await ModeActions.setRoutingMode(ref, mode);
      return;
    }
    if (key.startsWith('mode_conn_')) {
      final mode = key.substring('mode_conn_'.length);
      await ModeActions.setConnectionMode(ref, mode);
      return;
    }

    switch (key) {
      case 'connect':
        await _handleConnect();
      case 'disconnect':
        await _handleDisconnect();
      case 'best_node':
        await _handleBestNode();
      case 'show':
        await showMainWindow();
      case 'sync':
        await _handleSyncSubscription();
    }
  }

  Future<void> _handleConnect() async {
    final status = ref.read(coreStatusProvider);
    if (status != CoreStatus.stopped) return; // debounce
    final actions = ref.read(coreActionsProvider);
    final isMock = ref.read(isMockModeProvider);

    if (isMock) {
      await actions.start('');
      return;
    }
    final config = await loadSelectedProfileConfig();
    if (config == null) {
      // Either no active profile or loading it failed — nudge the user to
      // open the main window so they can pick / re-import a profile.
      await showMainWindow();
      return;
    }
    await actions.start(config);
  }

  Future<void> _handleDisconnect() async {
    final status = ref.read(coreStatusProvider);
    if (status != CoreStatus.running) return; // debounce
    await ref.read(coreActionsProvider).stop();
  }

  /// Public: invoked by the global hotkey handler in main.dart.
  Future<void> handleToggle() async {
    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.running) {
      await _handleDisconnect();
    } else if (status == CoreStatus.stopped) {
      await _handleConnect();
    }
  }

  Future<void> _handleBestNode() async {
    // Open main window so the user can see the result; smart select
    // requires the full UI context and running core.
    await showMainWindow();
  }

  Future<void> _handleRecentNodeSwitch(int index) async {
    final recentNodes = ref.read(recentNodesProvider);
    if (index >= recentNodes.length) return;
    final node = recentNodes[index];

    // If running, switch node in the group
    if (ref.read(coreStatusProvider) == CoreStatus.running) {
      try {
        await CoreManager.instance.api.changeProxy(node.group, node.name);
        ref.read(proxyGroupsProvider.notifier).refresh();
        AppNotifier.success('已切换到 ${node.name}');
      } catch (e) {
        debugPrint('[Tray] switch recent node: $e');
      }
    } else {
      // Not running — start with current profile then the node will be used
      await _handleConnect();
    }
  }

  Future<void> _handleSyncSubscription() async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      await showMainWindow();
      return;
    }
    try {
      await ref.read(authProvider.notifier).syncSubscription();
      AppNotifier.success('订阅更新成功');
    } catch (e) {
      AppNotifier.error('订阅更新失败');
    }
  }
}
