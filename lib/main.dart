import 'dart:async';
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
import 'pages/settings_page.dart';
import 'domain/models/proxy.dart';
import 'modules/nodes/providers/nodes_providers.dart';
import 'modules/store/store_page.dart';
import 'modules/onboarding/onboarding_page.dart';
import 'modules/yue_auth/presentation/yue_auth_page.dart';
import 'modules/yue_auth/providers/yue_auth_providers.dart';
import 'domain/models/traffic.dart';
import 'domain/models/traffic_history.dart';
import 'modules/connections/providers/connections_providers.dart';
import 'modules/dashboard/providers/dashboard_providers.dart';
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

/// Initial tab index restored from SettingsService (Android process restore).
final initialTabIndexProvider = Provider<int>((ref) => 0);

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
  final savedDelayResults = await SettingsService.getDelayResults();
  final savedTabIndex = await SettingsService.getLastTabIndex();

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
      delayResultsProvider.overrideWith((ref) => savedDelayResults),
      expandedGroupNamesProvider.overrideWith((ref) => <String>{}),
      initialTabIndexProvider.overrideWithValue(savedTabIndex),
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
    with TrayListener, WindowListener, WidgetsBindingObserver {
  bool _trayInitialized = false;
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _appLinksSub;

  // Managed provider subscriptions — cleaned up in dispose()
  ProviderSubscription? _langSub;
  ProviderSubscription? _statusSub;
  ProviderSubscription? _groupsSub;
  ProviderSubscription? _profilesSub;
  ProviderSubscription? _hotkeySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
    if (Platform.isMacOS || Platform.isWindows) {
      _initTray();
    }
    // Auto-connect and expiry check after first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        _initListeners();
        await _maybeAutoConnect();
        _checkSubscriptionExpiry();
        _initDeepLinks();
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
          _registerHotkeys();
        }
      } catch (e) {
        debugPrint('[Init] post-frame init error (non-fatal): $e');
      }
    });
  }

  /// Register all provider listeners once, not on every build().
  /// Each listener is a ProviderSubscription stored as a field and
  /// closed in dispose() — preventing repeated registration.
  void _initListeners() {
    // Keep S.current in sync with language provider
    _langSub = ref.listenManual(languageProvider, (_, lang) {
      S.setLanguage(lang);
      _updateTrayMenu(
        isRunning: ref.read(coreStatusProvider) == CoreStatus.running,
        groups: ref.read(proxyGroupsProvider),
      );
    });

    // Sync tray menu with connection state; notify on unexpected disconnect
    _statusSub = ref.listenManual(coreStatusProvider, (prev, next) {
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
    _groupsSub = ref.listenManual(proxyGroupsProvider, (_, groups) {
      _updateTrayMenu(
        isRunning: ref.read(coreStatusProvider) == CoreStatus.running,
        groups: groups,
      );
    });

    // Re-check subscription expiry after profiles are updated
    _profilesSub = ref.listenManual(profilesProvider, (prev, next) {
      if (next is AsyncData) _checkSubscriptionExpiry();
    });

    // Re-register hotkey when user changes it in Settings
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      _hotkeySub = ref.listenManual(toggleHotkeyProvider, (prev, next) {
        if (prev != null && prev != next) _reregisterHotkeys(next);
      });
    }
  }

  @override
  void dispose() {
    _langSub?.close();
    _statusSub?.close();
    _groupsSub?.close();
    _profilesSub?.close();
    _hotkeySub?.close();
    WidgetsBinding.instance.removeObserver(this);
    _appLinksSub?.cancel();
    if (_trayInitialized) trayManager.removeListener(this);
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      hotKeyManager.unregisterAll();
    }
    super.dispose();
  }

  // ── App lifecycle ─────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  /// Validate core state immediately when app returns from background.
  /// Avoids waiting up to 10s for the heartbeat to detect a crashed core.
  ///
  /// If the core is still alive, invalidates stream providers to force
  /// WebSocket reconnection (the OS may have suspended the sockets during
  /// a long background period).
  Future<void> _onAppResumed() async {
    // 1. Refresh auth / user profile in background (catches token expiry)
    ref.read(authProvider.notifier).refreshUserInfo().ignore();

    final manager = CoreManager.instance;
    if (manager.isMockMode) return;

    final status = ref.read(coreStatusProvider);

    // 2. Recovery: Dart thinks stopped but Go core is actually still running.
    //    This happens on Android when the OS kills the Flutter engine in the
    //    background but the VPN service + Go core survive. On resume, the
    //    engine is recreated with default state (stopped), but the core is alive.
    if (status != CoreStatus.running) {
      try {
        final coreAlive = manager.isCoreActuallyRunning;
        final apiOk = coreAlive ? await manager.api.isAvailable() : false;
        if (coreAlive && apiOk) {
          debugPrint('[AppLifecycle] core alive but Dart state was $status — recovering');
          // Restore Dart state + ports to match reality
          await manager.markRunning();
          ref.read(coreStatusProvider.notifier).state = CoreStatus.running;
          // Kick off streams and data refresh
          ref.invalidate(trafficStreamProvider);
          ref.invalidate(memoryStreamProvider);
          ref.invalidate(connectionsStreamProvider);
          ref.invalidate(exitIpInfoProvider);
          ref.read(proxyGroupsProvider.notifier).refresh();
        }
      } catch (e) {
        debugPrint('[AppLifecycle] recovery check failed: $e');
      }
      return;
    }

    // 3. Normal case: Dart says running — verify core is still alive
    try {
      final running = manager.isRunning;
      final apiOk = await manager.api.isAvailable();
      if (!running || !apiOk) {
        debugPrint('[AppLifecycle] core dead after resume — resetting state');
        ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
        ref.read(trafficProvider.notifier).state = const Traffic();
        ref.read(trafficHistoryProvider.notifier).state = TrafficHistory();
        // Clear desktop system proxy to prevent dead-proxy network blackout
        if (Platform.isMacOS || Platform.isWindows) {
          CoreActions.clearSystemProxyStatic().catchError((_) {});
        }
        manager.stop().catchError((_) {});
      } else {
        // Core alive — force reconnect stale WebSocket streams.
        // After long background, OS may have closed TCP connections;
        // the retry loop in MihomoStream is paused while suspended.
        ref.invalidate(trafficStreamProvider);
        ref.invalidate(memoryStreamProvider);
        ref.invalidate(connectionsStreamProvider);
        // Refresh exit IP in case network changed during background
        ref.invalidate(exitIpInfoProvider);
        // Refresh proxy groups in case core reloaded config
        ref.read(proxyGroupsProvider.notifier).refresh();
      }
    } catch (e) {
      debugPrint('[AppLifecycle] resume check failed: $e');
    }
  }

  // ── Deep links ────────────────────────────────────────────────────────────

  void _initDeepLinks() {
    // Handle links that launched the app cold
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });
    // Handle links while app is already running — store to cancel in dispose()
    _appLinksSub = _appLinks.uriLinkStream.listen(_handleDeepLink);
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
      // Set _trayInitialized BEFORE _updateTrayMenu so the guard passes.
      _trayInitialized = true;
      await _updateTrayMenu(isRunning: false);
      trayManager.addListener(this);
    } catch (e) {
      debugPrint('[Tray] init failed: $e');
    }
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
    // All platforms: left-click toggles window visibility
    _toggleWindowVisibility();
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
    // Always clear system proxy on exit regardless of settings/state,
    // so quitting the app never leaves a dead proxy configured.
    if (Platform.isMacOS || Platform.isWindows) {
      await CoreActions.clearSystemProxyStatic().catchError((_) {});
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
    // Don't auto-reconnect if the user explicitly stopped the VPN
    if (ref.read(userStoppedProvider)) {
      debugPrint('[AutoConnect] skipped — user explicitly stopped');
      return;
    }

    try {
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
    } catch (e) {
      debugPrint('[AutoConnect] startup failed: $e');
      // Don't crash — user can start manually from dashboard
    }
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

    // Activate heartbeat at root level so it runs regardless of active tab.
    // The provider itself guards: only runs while CoreStatus.running.
    ref.watch(coreHeartbeatProvider);

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
      home: const _AuthGate(),
    );
  }
}

// ── Auth gate ──────────────────────────────────────────────────────────────────

/// Shows login page when not authenticated, main shell when logged in.
/// On first login, shows onboarding before main shell.
class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  bool? _hasSeenOnboarding;

  @override
  void initState() {
    super.initState();
    SettingsService.getHasSeenOnboarding().then((v) {
      if (mounted) setState(() => _hasSeenOnboarding = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    switch (authState.status) {
      case AuthStatus.unknown:
        return const SizedBox.shrink();
      case AuthStatus.loggedOut:
        return const YueAuthPage();
      case AuthStatus.loggedIn:
      case AuthStatus.guest:
        if (_hasSeenOnboarding == null) return const SizedBox.shrink();
        if (_hasSeenOnboarding == false) {
          return OnboardingPage(
            onComplete: () => setState(() => _hasSeenOnboarding = true),
          );
        }
        return const MainShell();
    }
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key = const ValueKey('mainShell')});

  /// Tab indices for programmatic navigation.
  static const tabDashboard = 0;
  static const tabProxies   = 1;
  static const tabStore     = 2;
  static const tabSettings  = 3;

  static void switchToTab(BuildContext context, int index) {
    context.findAncestorStateOfType<_MainShellState>()?.switchTab(index);
  }

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _currentIndex;
  final _builtTabs = <int, bool>{0: true};

  void switchTab(int index) {
    setState(() {
      _currentIndex = index;
      _builtTabs[index] = true;
    });
    SettingsService.setLastTabIndex(index);
  }

  static const _pages = [
    DashboardPage(),
    NodesPage(),
    StorePage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = ref.read(initialTabIndexProvider).clamp(0, _pages.length - 1);
    _builtTabs[_currentIndex] = true;
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
                onSelect: (i) => switchTab(i),
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
                  children: [
                    for (int i = 0; i < _pages.length; i++)
                      _builtTabs[i] == true ? _pages[i] : const SizedBox.shrink(),
                  ],
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
      (const Icon(Icons.storefront_outlined, size: 20),
       const Icon(Icons.storefront_rounded, size: 20), s.navStore),
      (const Icon(Icons.person_outline_rounded, size: 20),
       const Icon(Icons.person_rounded, size: 20), s.navMine),
    ];

    return Scaffold(
      body: RepaintBoundary(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            for (int i = 0; i < _pages.length; i++)
              _builtTabs[i] == true ? _pages[i] : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => switchTab(i),
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
      (Icons.storefront_outlined, Icons.storefront_rounded, s.navStore),
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
                    Text('悦通',
                        style: YLText.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                    Text('AI · 全球加速',
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
                  ? Icons.person_rounded
                  : Icons.person_outline_rounded,
              label: s.navMine,
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
    // On mobile, return true to absorb unhandled async errors and prevent
    // the OS from killing the app. On desktop, return false so the platform
    // can present the error.
    return Platform.isAndroid || Platform.isIOS;
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
