import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'constants.dart';
import 'l10n/app_strings.dart';
import 'pages/dashboard_page.dart';
import 'pages/nodes_page.dart';
import 'pages/profile_page.dart';
import 'pages/settings_page.dart';
import 'domain/models/proxy.dart';
import 'providers/core_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/proxy_provider.dart';
import 'shared/app_notifier.dart';
import 'core/kernel/core_manager.dart';
import 'services/profile_service.dart';
import 'core/storage/settings_service.dart';
import 'theme.dart';

/// Global navigator key for deep-link navigation outside widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

/// Jump-to-profile-page notifier (deep link triggers this).
final deepLinkUrlProvider = StateProvider<String?>((ref) => null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Crash logging ────────────────────────────────────────────────────────
  _setupCrashLogging();

  // Restore persisted settings
  final savedTheme = await SettingsService.getThemeMode();
  final savedProfileId = await SettingsService.getActiveProfileId();
  final savedRoutingMode = await SettingsService.getRoutingMode();
  final savedConnectionMode = await SettingsService.getConnectionMode();
  final savedLogLevel = await SettingsService.getLogLevel();
  final savedAutoConnect = await SettingsService.getAutoConnect();
  final savedSystemProxy = await SettingsService.getSystemProxyOnConnect();
  final savedLanguage = await SettingsService.getLanguage();
  final savedTestUrl = await SettingsService.getTestUrl();
  final savedCloseBehavior = await SettingsService.getCloseBehavior();
  final savedToggleHotkey = await SettingsService.getToggleHotkey();

  // Apply global strings language before runApp (for tray etc.)
  S.setLanguage(savedLanguage);

  // Configure launch at startup (macOS / Windows only)
  if (Platform.isMacOS || Platform.isWindows) {
    try {
      launchAtStartup.setup(
        appName: AppConstants.appName,
        appPath: Platform.resolvedExecutable,
      );
    } catch (_) {}
  }

  // Initialize window manager (macOS, Windows, Linux)
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(800, 560),
      center: true,
      title: AppConstants.appName,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    // Linux: enforce a slightly tighter minimum to avoid layout breakage
    if (Platform.isLinux) {
      await windowManager.setMinimumSize(const Size(900, 600));
    }
  }

  // Initialize core manager
  CoreManager.instance;

  // ── Global hotkeys (desktop) ─────────────────────────────────────────────
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await hotKeyManager.unregisterAll();
  }

  runApp(ProviderScope(
    overrides: [
      themeProvider.overrideWith((ref) => savedTheme),
      languageProvider.overrideWith((ref) => savedLanguage),
      activeProfileIdProvider
          .overrideWith((ref) => ActiveProfileNotifier(savedProfileId)),
      routingModeProvider.overrideWith((ref) => savedRoutingMode),
      connectionModeProvider.overrideWith((ref) => savedConnectionMode),
      logLevelProvider.overrideWith((ref) => savedLogLevel),
      autoConnectProvider.overrideWith((ref) => savedAutoConnect),
      systemProxyOnConnectProvider.overrideWith((ref) => savedSystemProxy),
      testUrlProvider.overrideWith((ref) => savedTestUrl),
      closeBehaviorProvider.overrideWith((ref) => savedCloseBehavior),
      toggleHotkeyProvider.overrideWith((ref) => savedToggleHotkey),
    ],
    child: const YueLinkApp(),
  ));
}

class YueLinkApp extends ConsumerStatefulWidget {
  const YueLinkApp({super.key});

  @override
  ConsumerState<YueLinkApp> createState() => _YueLinkAppState();
}

class _YueLinkAppState extends ConsumerState<YueLinkApp>
    with TrayListener, WindowListener {
  bool _trayInitialized = false;
  final _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
    if (Platform.isMacOS || Platform.isWindows) {
      _initTray();
    }
    // Auto-connect and expiry check after first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeAutoConnect();
      _checkSubscriptionExpiry();
      _initDeepLinks();
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        _registerHotkeys();
      }
    });
  }

  @override
  void dispose() {
    if (_trayInitialized) trayManager.removeListener(this);
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      hotKeyManager.unregisterAll();
    }
    super.dispose();
  }

  // ── Deep links ────────────────────────────────────────────────────────────

  void _initDeepLinks() {
    // Handle links that launched the app cold
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });
    // Handle links while app is already running
    _appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  /// Parses clash://install-config?url=... or mihomo://install-config?url=...
  void _handleDeepLink(Uri uri) {
    if (!mounted) return;
    final rawUrl = uri.queryParameters['url'];
    if (rawUrl == null || rawUrl.isEmpty) return;
    // Notify the profile page to pre-fill the add dialog
    ref.read(deepLinkUrlProvider.notifier).state = rawUrl;
    // If window is hidden (desktop), bring it to front
    if (Platform.isMacOS || Platform.isWindows) {
      windowManager.show();
      windowManager.focus();
    }
  }

  // ── Global hotkeys ────────────────────────────────────────────────────────

  Future<void> _registerHotkeys() async {
    // Linux: global hotkeys unreliable under Wayland — skip silently
    if (Platform.isLinux) {
      debugPrint('[Hotkey] Skipping global hotkey on Linux (Wayland not supported)');
      return;
    }
    try {
      final stored = ref.read(toggleHotkeyProvider);
      final toggleKey = parseStoredHotkey(stored);
      await hotKeyManager.register(toggleKey, keyDownHandler: (_) {
        _handleTrayToggle();
      });
    } catch (_) {
      // Hotkey registration can fail if another app holds the shortcut
    }
  }

  Future<void> _reregisterHotkeys(String newHotkeyStr) async {
    if (Platform.isLinux) return;
    try {
      await hotKeyManager.unregisterAll();
      final toggleKey = parseStoredHotkey(newHotkeyStr);
      await hotKeyManager.register(toggleKey, keyDownHandler: (_) {
        _handleTrayToggle();
      });
    } catch (_) {}
  }

  // ── Window manager callbacks ─────────────────────────────────────

  @override
  void onWindowClose() async {
    // Linux has no system tray — always quit on close
    if (Platform.isLinux) {
      await _handleQuit();
      return;
    }
    final behavior = ref.read(closeBehaviorProvider);
    if (behavior == 'exit') {
      await _handleQuit();
    } else {
      await windowManager.hide();
    }
  }

  // ── Tray ─────────────────────────────────────────────────────────

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon(
        Platform.isWindows
            // Use .ico for Windows — contains 16/32/48px sizes which the
            // Windows tray API requires. A plain .png falls back to a white
            // placeholder at the 16×16 tray size.
            ? 'assets/app_icon.ico'
            : 'assets/tray_icon_macos.png',
      );
      await _updateTrayMenu(isRunning: false);
      trayManager.addListener(this);
      _trayInitialized = true;
    } catch (_) {}
  }

  Future<void> _updateTrayMenu({
    required bool isRunning,
    List<ProxyGroup>? groups,
  }) async {
    if (!_trayInitialized) return;
    final s = S.current;

    // Build proxy quick-switch submenu (Selector groups only, max 3 groups × 10 nodes)
    final proxySubMenus = <MenuItem>[];
    if (isRunning && groups != null) {
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
          nodeItems.add(MenuItem(
            key: 'proxy_${gi}_$ni',
            label: node == group.now ? '✓ $node' : '  $node',
          ));
        }
        if (nodeItems.isNotEmpty) {
          proxySubMenus.add(MenuItem.submenu(
            label: group.name,
            submenu: Menu(items: nodeItems),
          ));
        }
      }
    }

    try {
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(
            key: 'toggle',
            label: isRunning ? s.trayDisconnect : s.trayConnect),
        MenuItem(key: 'show', label: s.trayShowWindow),
        if (proxySubMenus.isNotEmpty) ...[
          MenuItem.separator(),
          MenuItem.submenu(
            label: s.trayProxies,
            submenu: Menu(items: proxySubMenus),
          ),
        ],
        MenuItem.separator(),
        MenuItem(key: 'quit', label: s.trayQuit),
      ]));
    } catch (_) {}
  }

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
    if (Platform.isWindows) {
      // Windows: left-click toggles window visibility
      _toggleWindowVisibility();
    } else {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key ?? '';
    if (key.startsWith('proxy_')) {
      final resolved = _resolveProxyKey(key);
      if (resolved != null) {
        ref
            .read(proxyGroupsProvider.notifier)
            .changeProxy(resolved.$1, resolved.$2);
      }
      return;
    }
    switch (key) {
      case 'toggle':
        _handleTrayToggle();
      case 'show':
        _toggleWindowVisibility();
      case 'quit':
        _handleQuit();
    }
  }

  Future<void> _toggleWindowVisibility() async {
    try {
      final isVisible = await windowManager.isVisible();
      if (isVisible) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (_) {}
  }

  Future<void> _handleTrayToggle() async {
    final status = ref.read(coreStatusProvider);
    final actions = ref.read(coreActionsProvider);
    final isMock = ref.read(isMockModeProvider);

    if (status == CoreStatus.running) {
      await actions.stop();
    } else if (status == CoreStatus.stopped) {
      if (isMock) {
        await actions.start('');
      } else {
        final activeId = ref.read(activeProfileIdProvider);
        if (activeId == null) return;
        final config = await ProfileService.loadConfig(activeId);
        if (config == null) return;
        await actions.start(config);
      }
    }
  }

  Future<void> _handleQuit() async {
    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.running) {
      await ref.read(coreActionsProvider).stop();
    }
    if (Platform.isMacOS || Platform.isWindows) {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } else {
      exit(0);
    }
  }

  Future<void> _maybeAutoConnect() async {
    final autoConnect = ref.read(autoConnectProvider);
    if (!autoConnect) {
      debugPrint('[AutoConnect] disabled by user setting');
      return;
    }

    final isMock = ref.read(isMockModeProvider);
    if (isMock) {
      debugPrint('[AutoConnect] mock mode → starting');
      await ref.read(coreActionsProvider).start('');
      return;
    }

    final activeId = ref.read(activeProfileIdProvider);
    if (activeId == null) {
      debugPrint('[AutoConnect] no active profile selected');
      return;
    }

    final config = await ProfileService.loadConfig(activeId);
    if (config == null) {
      debugPrint('[AutoConnect] config file not found for profile: $activeId');
      return;
    }

    debugPrint('[AutoConnect] starting with profile: $activeId (${config.length} bytes)');
    final ok = await ref.read(coreActionsProvider).start(config);
    debugPrint('[AutoConnect] result: $ok');
  }

  void _checkSubscriptionExpiry() {
    final profiles = ref.read(profilesProvider);
    profiles.whenData((list) {
      final s = S.current;
      for (final p in list) {
        final sub = p.subInfo;
        if (sub == null) continue;
        if (sub.isExpired) {
          AppNotifier.error(s.subExpired(p.name));
        } else if (sub.daysRemaining != null && sub.daysRemaining! <= 7) {
          AppNotifier.warning(s.subExpiringSoon(p.name, sub.daysRemaining!));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final language = ref.watch(languageProvider);

    // Keep S.current in sync with language provider
    ref.listen(languageProvider, (_, lang) {
      S.setLanguage(lang);
      _updateTrayMenu(
        isRunning: ref.read(coreStatusProvider) == CoreStatus.running,
        groups: ref.read(proxyGroupsProvider),
      );
    });

    // Sync tray menu with connection state; notify on unexpected disconnect
    ref.listen(coreStatusProvider, (prev, next) {
      _updateTrayMenu(
        isRunning: next == CoreStatus.running,
        groups: ref.read(proxyGroupsProvider),
      );
      if (prev == CoreStatus.running && next == CoreStatus.stopped) {
        AppNotifier.warning(S.current.disconnectedUnexpected);
        if (_trayInitialized) {
          trayManager
              .setToolTip('YueLink · ${S.current.statusDisconnected}')
              .ignore();
        }
      } else if (next == CoreStatus.running && _trayInitialized) {
        trayManager.setToolTip('YueLink').ignore();
      }
    });

    // Sync tray proxy submenu when proxy groups change
    ref.listen(proxyGroupsProvider, (_, groups) {
      _updateTrayMenu(
        isRunning: ref.read(coreStatusProvider) == CoreStatus.running,
        groups: groups,
      );
    });

    // Re-check subscription expiry after profiles are updated
    ref.listen(profilesProvider, (prev, next) {
      if (next is AsyncData) _checkSubscriptionExpiry();
    });

    // Re-register hotkey when user changes it in Settings
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      ref.listen(toggleHotkeyProvider, (prev, next) {
        if (prev != null && prev != next) _reregisterHotkeys(next);
      });
    }

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,

      // i18n
      locale: Locale(language),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      themeMode: themeMode,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const MainShell(),
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key = const ValueKey('mainShell')});

  /// Tab indices for programmatic navigation.
  static const tabDashboard = 0;
  static const tabProxies   = 1;
  static const tabProfiles  = 2;
  static const tabSettings  = 3;

  static void switchToTab(BuildContext context, int index) {
    context.findAncestorStateOfType<_MainShellState>()?.switchTab(index);
  }

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  void switchTab(int index) {
    setState(() => _currentIndex = index);
  }

  static const _pages = [
    DashboardPage(),
    NodesPage(),
    ProfilePage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final profiles = ref.read(profilesProvider);
      profiles.whenData((list) {
        if (list.isEmpty && mounted) {
          setState(() => _currentIndex = MainShell.tabProfiles);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 640;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            // ── Sidebar ────────────────────────────────────────
            RepaintBoundary(
              child: _Sidebar(
                currentIndex: _currentIndex,
                onSelect: (i) => setState(() => _currentIndex = i),
              ),
            ),

            // ── Sidebar / content divider ──────────────────────
            Container(
              width: 0.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),

            // ── Content ────────────────────────────────────────
            Expanded(
              child: RepaintBoundary(
                child: IndexedStack(
                  index: _currentIndex,
                  children: _pages,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Mobile bottom navigation ─────────────────────────────────
    final s = S.of(context);
    final mobileItems = [
      (const Icon(Icons.home_outlined, size: 20),
       const Icon(Icons.home_filled, size: 20), s.navHome),
      (const Icon(Icons.public_outlined, size: 20),
       const Icon(Icons.public, size: 20), s.navProxies),
      (const Icon(Icons.folder_outlined, size: 20),
       const Icon(Icons.folder, size: 20), s.navProfile),
      (const Icon(Icons.settings_outlined, size: 20),
       const Icon(Icons.settings, size: 20), s.navSettings),
    ];

    return Scaffold(
      body: RepaintBoundary(
        child: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) =>
            setState(() => _currentIndex = i),
        destinations: mobileItems
            .map((item) => NavigationDestination(
                  icon: item.$1,
                  selectedIcon: item.$2,
                  label: item.$3,
                ))
            .toList(),
        height: 60,
        labelBehavior:
            NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
    );
  }
}

// ── Sidebar ────────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _Sidebar({required this.currentIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final navItems = [
      (Icons.home_outlined, Icons.home_filled, s.navHome),
      (Icons.public_outlined, Icons.public, s.navProxies),
      (Icons.folder_outlined, Icons.folder, s.navProfile),
    ];

    return Container(
      width: 230,
      color: isDark ? YLColors.zinc900 : YLColors.zinc50, // Sidebar one shade lighter than zinc100 bg
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Brand ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: YLColors.primary,
                    borderRadius: BorderRadius.circular(YLRadius.xl),
                  ),
                  child: const Icon(Icons.link_rounded, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('YueLink',
                        style: YLText.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                    Text('Proxy Client',
                        style: YLText.caption.copyWith(
                          color: YLColors.zinc400,
                        )),
                  ],
                ),
              ],
            ),
          ),

          // ── Navigation items ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (int i = 0; i < navItems.length; i++)
                  _SidebarItem(
                    icon: currentIndex == i ? navItems[i].$2 : navItems[i].$1,
                    label: navItems[i].$3,
                    isActive: currentIndex == i,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ),

          const Spacer(),

          // ── Settings at bottom ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            child: _SidebarItem(
              icon: currentIndex == MainShell.tabSettings
                  ? Icons.settings
                  : Icons.settings_outlined,
              label: s.navSettings,
              isActive: currentIndex == MainShell.tabSettings,
              onTap: () => onSelect(MainShell.tabSettings),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeColor = isDark ? YLColors.zinc800 : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isActive ? activeColor : Colors.transparent,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        shadowColor: Colors.black.withValues(alpha: 0.05),
        elevation: isActive && !isDark ? 1 : 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(YLRadius.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: isActive
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(YLRadius.lg),
                    border: Border.all(color: borderColor, width: 0.5),
                  )
                : null,
            child: Row(
              children: [
                Icon(icon,
                    size: 16,
                    color: isActive
                        ? (isDark ? Colors.white : YLColors.zinc900)
                        : YLColors.zinc500),
                const SizedBox(width: 10),
                Text(label,
                    style: YLText.body.copyWith(
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive
                          ? (isDark ? Colors.white : YLColors.zinc900)
                          : YLColors.zinc500,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Crash logging ─────────────────────────────────────────────────────────────

void _setupCrashLogging() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _writeCrashLog(details.exceptionAsString(), details.stack.toString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _writeCrashLog(error.toString(), stack.toString());
    return false; // let the platform handle it too
  };
}

Future<void> _writeCrashLog(String error, String stack) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final logFile = File('${dir.path}/crash.log');
    final timestamp = DateTime.now().toIso8601String();
    final entry = '[$timestamp]\n$error\n$stack\n\n';
    await logFile.writeAsString(entry, mode: FileMode.append);
  } catch (_) {}
}
