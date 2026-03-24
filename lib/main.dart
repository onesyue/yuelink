import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'modules/store/store_page.dart';
import 'modules/onboarding/onboarding_page.dart';
import 'modules/carrier/carrier_provider.dart';
import 'modules/yue_auth/presentation/yue_auth_page.dart';
import 'modules/yue_auth/providers/yue_auth_providers.dart';
import 'domain/models/traffic.dart';
import 'domain/models/traffic_history.dart';
import 'modules/connections/providers/connections_providers.dart';
import 'modules/dashboard/providers/dashboard_providers.dart';
import 'providers/core_provider.dart';
import 'providers/profile_provider.dart';
import 'shared/app_notifier.dart';
import 'core/kernel/core_manager.dart';
import 'core/platform/vpn_service.dart';
import 'core/storage/auth_token_service.dart';
import 'services/profile_service.dart';
import 'core/storage/settings_service.dart';
import 'modules/emby/emby_providers.dart';
import 'modules/emby/emby_web_page.dart';
import 'theme.dart';

/// Global navigator key for deep-link navigation outside widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

// ── Single-instance IPC server (macOS / Windows) ──────────────────────────────
/// Local TCP server used as a single-instance mutex.
/// Port 47866 is fixed — chosen to avoid common conflicts.
/// The server accepts a "show\n" message from a second instance and brings
/// the window to the foreground. The second instance then exits immediately.
ServerSocket? _singleInstanceServer;

Future<bool> _ensureSingleInstance() async {
  const port = 47866;
  try {
    _singleInstanceServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4, port,
        shared: false);
    _singleInstanceServer!.listen((socket) {
      socket.listen((data) {
        final msg = String.fromCharCodes(data).trim();
        if (msg == 'show') {
          windowManager.show();
          windowManager.focus();
        }
        socket.close();
      });
    });
    return true; // We are the first instance
  } on SocketException {
    // Another instance is running — ask it to show itself
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port,
          timeout: const Duration(seconds: 1));
      socket.write('show\n');
      await socket.flush();
      await socket.close();
    } catch (_) {}
    return false;
  }
}

/// Jump-to-profile-page notifier (deep link triggers this).
final deepLinkUrlProvider = StateProvider<String?>((ref) => null);

/// Initial tab index restored from SettingsService (Android process restore).
final initialTabIndexProvider = Provider<int>((ref) => 0);

/// Pre-loaded onboarding flag (avoids async blank flash in _AuthGate).
final hasSeenOnboardingProvider = StateProvider<bool>((ref) => false);

/// Pre-loaded built tabs (avoids SizedBox.shrink for previously visited tabs).
final initialBuiltTabsProvider = Provider<List<int>>((ref) => [0]);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Crash logging ────────────────────────────────────────────────────────
  _setupCrashLogging();

  // Restore persisted settings — single disk read, then all sync from cache.
  await SettingsService.load();
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
  final savedBuiltTabs = await SettingsService.getBuiltTabs();
  final savedOnboarding = await SettingsService.getHasSeenOnboarding();

  // Pre-load auth state to eliminate blank screen flash on Android resume.
  // AuthNotifier._init() is async and shows AuthStatus.unknown (blank) until done.
  // By pre-reading token + cached profile here, we can pass them as initial state.
  final authService = AuthTokenService.instance;
  final savedToken = await authService.getToken();
  final savedProfile = (savedToken != null && savedToken.isNotEmpty)
      ? await authService.getCachedProfile()
      : null;

  // Apply global strings language before runApp (for tray etc.)
  S.setLanguage(savedLanguage);

  // ── Single instance guard (macOS / Windows) ─────────────────────────────
  // Must run before windowManager.ensureInitialized() so the second instance
  // can exit(0) before creating a window. The first instance's server is ready
  // to receive "show" commands as soon as windowManager is initialized below.
  if (Platform.isMacOS || Platform.isWindows) {
    final isFirst = await _ensureSingleInstance();
    if (!isFirst) {
      exit(0);
    }
  }

  // Configure launch at startup (macOS / Windows only)
  if (Platform.isMacOS || Platform.isWindows) {
    try {
      launchAtStartup.setup(
        appName: AppConstants.appName,
        appPath: Platform.resolvedExecutable,
      );
    } catch (e) {
      debugPrint('[App] launchAtStartup setup: $e');
    }
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
      preloadedProfileIdProvider.overrideWithValue(savedProfileId),
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
      hasSeenOnboardingProvider.overrideWith((ref) => savedOnboarding),
      initialBuiltTabsProvider.overrideWithValue(savedBuiltTabs),
      // Pre-loaded auth state: eliminates blank screen from async AuthNotifier._init()
      preloadedAuthStateProvider.overrideWithValue(
        (savedToken != null && savedToken.isNotEmpty)
            ? AuthState(
                status: AuthStatus.loggedIn,
                token: savedToken,
                userProfile: savedProfile,
              )
            : const AuthState(status: AuthStatus.loggedOut),
      ),
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
  ProviderSubscription? _carrierSub;

  /// Guard to prevent onWindowClose from interfering during programmatic quit.
  bool _isQuitting = false;

  /// True while the initial post-frame recovery has run.
  /// Prevents didChangeAppLifecycleState(resumed) from re-running
  /// _onAppResumed() on the same engine-create cycle.
  bool _initialRecoveryDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid || Platform.isIOS) {
      _setupVpnRevocationListener();
    }
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
        // On Android engine recreate, didChangeAppLifecycleState(resumed) may
        // NOT fire (it only triggers on transitions, not initial state).
        // Run the recovery check here to detect a surviving Go core immediately
        // instead of waiting up to 10s for the heartbeat.
        if (Platform.isAndroid) {
          await _onAppResumed();
          // Mark initial recovery as done so didChangeAppLifecycleState
          // doesn't re-run _onAppResumed() on this same engine create cycle.
          _initialRecoveryDone = true;
        }
        await _maybeAutoConnect();
        // Clear the recovery guard AFTER auto-connect completes.
        // This ensures heartbeat and VPN revocation callbacks don't interfere
        // during the entire recovery + auto-connect sequence.
        if (Platform.isAndroid) {
          ref.read(recoveryInProgressProvider.notifier).state = false;
        }
        _checkSubscriptionExpiry();
        _initDeepLinks();
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
          _registerHotkeys();
        }
      } catch (e) {
        debugPrint('[Init] post-frame init error (non-fatal): $e');
        // Always clear recovery guard even on error
        if (Platform.isAndroid) {
          ref.read(recoveryInProgressProvider.notifier).state = false;
        }
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
        // Only show "unexpected disconnect" if the user did NOT initiate stop
        // AND we're not in the middle of recovery (which temporarily resets state).
        // userStoppedProvider is set true in CoreActions.stop() before status changes.
        if (!ref.read(userStoppedProvider) &&
            !ref.read(recoveryInProgressProvider)) {
          AppNotifier.warning(S.current.disconnectedUnexpected);
        }
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

    // Carrier detection + SNI polling: start when core is running
    _carrierSub = ref.listenManual(coreStatusProvider, (prev, next) {
      if (next == CoreStatus.running && prev != CoreStatus.running) {
        _startCarrierDetection();
      } else if (next == CoreStatus.stopped && prev == CoreStatus.running) {
        ref.read(carrierProvider.notifier).stopPolling();
      }
    });
  }

  /// Register VPN revocation listener (Android only).
  ///
  /// Uses the recoveryInProgressProvider as the guard instead of a local
  /// bool, so it stays in sync with the provider-level guard that heartbeat
  /// also respects. This prevents VPN revocation from racing with recovery.
  void _setupVpnRevocationListener() {
    VpnService.listenForRevocation(() {
      // Skip if recovery is in progress — the recovery logic will handle
      // state correctly. Without this guard, onVpnRevoked races with
      // _onAppResumed() on engine recreate and resets state prematurely.
      if (ref.read(recoveryInProgressProvider)) {
        debugPrint('[App] VPN revoked during recovery — ignoring');
        return;
      }
      debugPrint('[App] VPN revoked — resetting state');
      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
      ref.read(trafficProvider.notifier).state = const Traffic();
      ref.read(trafficHistoryProvider.notifier).state = TrafficHistory();
      ref.read(trafficHistoryVersionProvider.notifier).state = 0;
      CoreManager.instance.stop().catchError((_) {});
      AppNotifier.warning(S.current.disconnectedUnexpected);
    });
  }

  /// Detect carrier via YueOps after VPN connects.
  /// Fetches the user's real (direct) IP to determine ISP (CT/CU/CM).
  void _startCarrierDetection() {
    final carrier = ref.read(carrierProvider.notifier);
    carrier.startPolling();
    carrier.detectCarrier();
  }

  @override
  void dispose() {
    _langSub?.close();
    _statusSub?.close();
    _groupsSub?.close();
    _profilesSub?.close();
    _hotkeySub?.close();
    _carrierSub?.close();
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
    // Battery optimization: pause WebSocket streams and reduce heartbeat
    // frequency when the app goes to background.
    ref.read(appInBackgroundProvider.notifier).state =
        state != AppLifecycleState.resumed;

    if (state == AppLifecycleState.resumed) {
      // On Android, the first resume after engine recreate is already handled
      // by addPostFrameCallback. Without this guard, _onAppResumed() runs
      // TWICE on the same cycle: once from post-frame, once from here.
      // The double call causes race conditions (concurrent API checks,
      // duplicate stream invalidations, state flip-flop).
      if (Platform.isAndroid && !_initialRecoveryDone) {
        debugPrint('[AppLifecycle] skipping resumed — initial recovery pending');
        return;
      }
      _onAppResumed().then((_) {
        // Clear recovery guard for subsequent resume calls (background→foreground).
        // The initial engine-create path clears this in the post-frame callback.
        if (Platform.isAndroid) {
          ref.read(recoveryInProgressProvider.notifier).state = false;
        }
      });
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
    //
    //    The recovery guard is set on the PROVIDER (not a local bool) so that
    //    both the heartbeat timer and the VPN revocation callback respect it.
    //    The guard stays up until auto-connect also completes — this prevents
    //    the status listener from firing "unexpected disconnect" during the
    //    brief stopped→running transition.
    if (status != CoreStatus.running) {
      ref.read(recoveryInProgressProvider.notifier).state = true;
      try {
        // On iOS the Go core runs in the PacketTunnel extension process;
        // isCoreActuallyRunning (FFI IsRunning) always returns false in the
        // main app. Check the REST API directly instead.
        final bool coreAlive;
        final bool apiOk;
        if (Platform.isIOS) {
          apiOk = await manager.api
              .isAvailable()
              .timeout(const Duration(seconds: 2), onTimeout: () => false);
          coreAlive = apiOk;
        } else {
          coreAlive = manager.isCoreActuallyRunning;
          apiOk = coreAlive ? await manager.api.isAvailable() : false;
        }
        if (coreAlive && apiOk) {
          debugPrint('[AppLifecycle] core alive but Dart state was $status — recovering');
          // Restore Dart state + ports to match reality
          await manager.markRunning();
          // Invalidate streams BEFORE setting status to running.
          // This ensures streams reconnect before heartbeat or listeners
          // check for data, preventing a brief "no data" state.
          ref.invalidate(trafficStreamProvider);
          ref.invalidate(memoryStreamProvider);
          ref.invalidate(connectionsStreamProvider);
          ref.invalidate(exitIpInfoProvider);
          // Now set state — this triggers the status listener and heartbeat
          ref.read(coreStatusProvider.notifier).state = CoreStatus.running;
          // Clear any stale startup error from previous session
          ref.read(coreStartupErrorProvider.notifier).state = null;
          // Also reset the user-stopped flag so the UI shows connected state
          ref.read(userStoppedProvider.notifier).state = false;
          ref.read(proxyGroupsProvider.notifier).refresh();
        }
        // Note: recovery guard stays up — cleared after _maybeAutoConnect
        // in the post-frame callback, or at the end of this method for
        // subsequent resume calls (not engine-create).
      } catch (e) {
        debugPrint('[AppLifecycle] recovery check failed: $e');
        ref.read(recoveryInProgressProvider.notifier).state = false;
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
        ref.read(trafficHistoryVersionProvider.notifier).state = 0;
        // Clear desktop system proxy to prevent dead-proxy network blackout
        if (Platform.isMacOS || Platform.isWindows) {
          CoreActions.clearSystemProxyStatic().catchError((_) {});
        }
        manager.stop().catchError((_) {});
      } else {
        // Core alive — refresh data but do NOT invalidate trafficStreamProvider.
        // Invalidating it creates a new TrafficHistory(), wiping the chart.
        // The WebSocket reconnection logic (exponential backoff in MihomoStream)
        // handles stale connections automatically when data stops flowing.
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
    } catch (e) {
      // Hotkey registration can fail if another app holds the shortcut
      debugPrint('[App] hotkey registration: $e');
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
    } catch (e) {
      debugPrint('[App] hotkey re-registration: $e');
    }
  }

  // ── Window manager callbacks ─────────────────────────────────────

  @override
  void onWindowClose() async {
    // If programmatic quit is in progress, don't interfere
    if (_isQuitting) return;

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
    } catch (e) {
      debugPrint('[App] tray menu update: $e');
    }
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
  void onTrayMenuItemClick(MenuItem menuItem) async {
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
        await _handleTrayToggle();
      case 'show':
        await _toggleWindowVisibility();
      case 'quit':
        await _handleQuit();
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
    } catch (e) {
      debugPrint('[App] window visibility toggle: $e');
    }
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
    _isQuitting = true;
    try {
      final status = ref.read(coreStatusProvider);
      if (status == CoreStatus.running) {
        await ref.read(coreActionsProvider).stop();
      }
      // Always clear system proxy on exit regardless of settings/state,
      // so quitting the app never leaves a dead proxy configured.
      if (Platform.isMacOS || Platform.isWindows) {
        try { await _singleInstanceServer?.close(); } catch (_) {}
        await CoreActions.clearSystemProxyStatic().catchError((_) {});
        await windowManager.setPreventClose(false);
        // Use destroy() instead of close() — close() triggers onWindowClose
        // callback which can interfere (e.g., hide the window instead of closing).
        await windowManager.destroy();
      } else {
        exit(0);
      }
    } catch (_) {
      // If anything fails during quit, force exit
      exit(0);
    }
  }

  Future<void> _maybeAutoConnect() async {
    // Skip if core is already running (e.g. recovered from Android engine recreate)
    if (ref.read(coreStatusProvider) == CoreStatus.running) {
      debugPrint('[AutoConnect] core already running — skipping');
      return;
    }
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

/// Gate flow: Onboarding (first launch) → Login → MainShell.
///
/// Onboarding is shown BEFORE the login page so first-time users see the
/// product intro regardless of auth state. This works on all platforms.
///
/// Auth state and onboarding flag are pre-loaded in main() to eliminate
/// blank screen flashes on Android engine recreate (background→foreground).
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSeenOnboarding = ref.watch(hasSeenOnboardingProvider);

    // 1. Onboarding first — before login, on ALL platforms
    if (!hasSeenOnboarding) {
      return OnboardingPage(
        onComplete: () {
          ref.read(hasSeenOnboardingProvider.notifier).state = true;
        },
      );
    }

    // 2. Auth check
    final authState = ref.watch(authProvider);
    switch (authState.status) {
      case AuthStatus.unknown:
        // With pre-loaded auth, this should never show. Keep as safety fallback.
        return const SizedBox.shrink();
      case AuthStatus.loggedOut:
        return const YueAuthPage();
      case AuthStatus.loggedIn:
      case AuthStatus.guest:
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
  /// Virtual — tapping this opens the in-app 悦视频 WebView; does not switch IndexedStack.
  static const tabEmby      = 4;

  static void switchToTab(BuildContext context, int index) {
    context.findAncestorStateOfType<_MainShellState>()?.switchTab(index);
  }

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _currentIndex;
  late final Map<int, bool> _builtTabs;

  void switchTab(int index) {
    if (index == MainShell.tabEmby) {
      _openEmby();
      return;
    }
    setState(() {
      _currentIndex = index;
      _builtTabs[index] = true;
    });
    SettingsService.setLastTabIndex(index);
    SettingsService.setBuiltTabs(
      _builtTabs.keys.where((k) => _builtTabs[k] == true).toList(),
    );
  }

  Future<void> _openEmby() async {
    final s = S.of(context);
    ref.invalidate(embyProvider);
    AppNotifier.info(s.mineEmbyOpening);
    final emby = await ref.read(embyProvider.future);
    if (!mounted) return;
    if (emby == null || !emby.hasAccess) {
      AppNotifier.warning(s.mineEmbyNoAccess);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EmbyWebPage(url: emby.launchUrl!)),
    );
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
    // Restore previously visited tabs from persistence (Android process restore)
    final savedTabs = ref.read(initialBuiltTabsProvider);
    _builtTabs = <int, bool>{
      for (final i in savedTabs)
        if (i >= 0 && i < _pages.length) i: true,
    };
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
        // tabEmby (4) is virtual — keep selectedIndex on the real current tab.
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

          // ── 我的 at bottom ────────────────────────────────────
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
