import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'constants.dart';
import 'i18n/app_strings.dart';
import 'i18n/strings_g.dart';
import 'modules/dashboard/dashboard_page.dart';
import 'modules/nodes/nodes_page.dart';
import 'modules/settings/settings_page.dart';
import 'modules/settings/providers/settings_providers.dart';
import 'modules/settings/hotkey_codec.dart';
import 'modules/onboarding/onboarding_page.dart';
import 'modules/onboarding/persona_prompt_page.dart';
import 'modules/carrier/carrier_provider.dart';
import 'modules/yue_auth/presentation/yue_auth_page.dart';
import 'modules/yue_auth/providers/yue_auth_providers.dart';
import 'modules/connections/providers/connections_providers.dart';
import 'modules/dashboard/providers/dashboard_providers.dart';
import 'modules/dashboard/providers/traffic_providers.dart';
import 'core/managers/system_proxy_manager.dart';
import 'core/providers/core_provider.dart';
import 'modules/profiles/providers/profiles_providers.dart';
import 'shared/app_notifier.dart';
import 'core/kernel/core_manager.dart';
import 'core/kernel/recovery_manager.dart';
import 'core/platform/quit_watchdog.dart';
import 'core/platform/tile_service.dart';
import 'core/platform/vpn_service.dart';
import 'core/platform/window_close_policy.dart';
import 'core/storage/auth_token_service.dart';
import 'core/env_config.dart';
import 'shared/error_logger.dart';
import 'shared/event_log.dart';
import 'shared/telemetry.dart';
import 'shared/node_telemetry.dart';
import 'shared/feature_flags.dart';
import 'core/profile/profile_service.dart';
import 'core/profile/subscription_sync_service.dart';
import 'modules/updater/update_checker.dart';
import 'core/storage/settings_service.dart';
import 'shared/desktop/app_tray_controller.dart';
import 'modules/emby/emby_media_page.dart';
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
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
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
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.write('show\n');
      await socket.flush();
      await socket.close();
    } catch (e) {
      EventLog.writeTagged(
        'App',
        'single_instance_show_failed',
        context: {'error': e},
      );
    }
    return false;
  }
}

/// Jump-to-profile-page notifier (deep link triggers this).
final deepLinkUrlProvider = StateProvider<String?>((ref) => null);

/// Initial tab index restored from SettingsService (Android process restore).
final initialTabIndexProvider = Provider<int>((ref) => 0);

/// Pre-loaded onboarding flag (avoids async blank flash in _AuthGate).
final hasSeenOnboardingProvider = StateProvider<bool>((ref) => false);

/// Pre-loaded onboarding persona ('newcomer' | 'experienced' | 'unknown' | null).
/// Null means the persona prompt hasn't been answered yet. Gated behind the
/// `onboarding_split` feature flag in `_AuthGate`.
final onboardingPersonaProvider = StateProvider<String?>((ref) => null);

/// Pre-loaded built tabs (avoids SizedBox.shrink for previously visited tabs).
final initialBuiltTabsProvider = Provider<List<int>>((ref) => [0]);

/// One-shot navigation request from outside the widget tree (e.g. the
/// Android Quick Settings tile long-press). MainShell listens and swaps
/// to the requested tab, then resets to null.
final tileNavRequestProvider = StateProvider<int?>((ref) => null);

/// Android-only: include current exit node ("🇭🇰 香港") in the tile
/// subtitle when connected. Default off — the Quick Settings panel is
/// visible to anyone who pulls down the shade.
final tileShowNodeInfoProvider = StateProvider<bool>((ref) => false);

void main() {
  // Zone-level safety net — catches fire-and-forget async exceptions that
  // would otherwise kill the Dart isolate (and on Android, the whole app
  // process). ErrorLogger.init() wires FlutterError + PlatformDispatcher,
  // but Zone errors are a separate channel that neither of those covers.
  runZonedGuarded(_bootstrap, (error, stack) {
    ErrorLogger.captureException(error, stack, source: 'Zone');
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Android 15 edge-to-edge ──
  // Android 15 enforces edge-to-edge for apps targeting SDK 35+ and
  // deprecates the old "leave nav bar area" behavior. Match the system
  // bar colour to the scaffold background so the UI feels native end-
  // to-end. SafeArea / Scaffold handle the actual inset math; we just
  // make the bars transparent with the correct icon brightness.
  if (Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  // ── Image cache limit (prevent 1GB+ memory from decoded bitmaps) ──
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;

  // ── Error logging (local crash.log + optional remote Sentry/Crashlytics) ──
  ErrorLogger.init();

  // Scan for any Android-native crashes written by MainApplication's Kotlin
  // uncaught handler since our last start. Fire-and-forget — runs after
  // Telemetry.init below has initialized, and silently skips on non-Android.
  if (Platform.isAndroid) {
    unawaited(ErrorLogger.scanAndroidNativeCrashes());
  }

  // ── Anonymous telemetry (opt-in, default OFF) ──
  unawaited(
    Telemetry.init().then((_) async {
      // Daily heartbeat — emit at most once per calendar day (UTC) so retention
      // curves count users who launched the app even when no feature event
      // happened. Persisted as a YYYY-MM-DD string; cheap string compare.
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final last = await SettingsService.get<String>('telemetryDailyPingDay');
      if (last != today) {
        Telemetry.event('daily_ping');
        await SettingsService.set('telemetryDailyPingDay', today);
      }
    }),
  );

  // ── Remote feature flags — fire-and-forget, safe defaults apply on offline ──
  unawaited(FeatureFlags.I.init());

  // ── v1.0.22 P0-4a: bootstrap storage hardening ──────────────────────────
  //
  // Pre-fix: a Future.wait([SettingsService.load(), authService.getToken()])
  // gated `runApp()`. If either future hung (Windows Defender scanning
  // settings.json, slow Keychain unlock, FUSE/SMB volume stuck), the
  // Flutter root never instantiated and the user saw "原生白屏" with no
  // app log to diagnose because the engine wasn't loaded yet.
  //
  // Post-fix: each blocking storage call has a hard 4 s wall-clock cap,
  // and the entire data-gather block is wrapped in a single try/catch
  // with safe defaults pre-declared so any unexpected throw still lets
  // `runApp()` fire with a working override list. Cached token/profile
  // are only "lost" in the timeout/throw paths — AuthNotifier._init()
  // (P0-4b) re-reads SecureStorage on first run, so a transient hang
  // resolves into the correct logged-in state automatically once disk
  // I/O un-sticks.
  const bootstrapStorageTimeout = Duration(seconds: 4);
  final authService = AuthTokenService.instance;

  // Seed cache (never throws — falls back to {} on hang).
  await SettingsService.loadWithTimeout(bootstrapStorageTimeout);

  // Pre-declare every override target with a default that mirrors the
  // SettingsService getter fallback. If the cascade below throws, runApp
  // still fires with these in place — degraded but functional.
  String? savedToken;
  String savedAccentColor = '3B82F6';
  int savedSubSyncInterval = 6;
  ThemeMode savedTheme = ThemeMode.system;
  String? savedProfileId;
  String savedRoutingMode = 'rule';
  String savedConnectionMode = 'systemProxy';
  String savedQuicPolicy = SettingsService.defaultQuicPolicy;
  String savedDesktopTunStack = 'mixed';
  String savedLogLevel = 'error';
  bool savedAutoConnect = false;
  bool savedManualStopped = false;
  bool savedSystemProxy = true;
  String savedLanguage = 'zh';
  String savedTestUrl = 'https://www.gstatic.com/generate_204';
  String savedCloseBehavior = 'tray';
  String savedToggleHotkey = 'ctrl+alt+c';
  Map<String, int> savedDelayResults = const {};
  int savedTabIndex = 0;
  List<int> savedBuiltTabs = const [0];
  bool savedOnboarding = false;
  String? savedPersona;
  bool savedTileShowNodeInfo = false;
  UserProfile? savedProfile;

  try {
    savedToken = await authService
        .getToken()
        .timeout(bootstrapStorageTimeout, onTimeout: () => null);

    // One-time accent reset (v1.0.16): force Blue-500 default for existing installs
    await SettingsService.migrateAccentToBlueIfNeeded();
    savedAccentColor = await SettingsService.getAccentColor();
    savedSubSyncInterval = await SettingsService.getSubSyncInterval();
    savedTheme = await SettingsService.getThemeMode();
    savedProfileId = await SettingsService.getActiveProfileId();
    savedRoutingMode = await SettingsService.getRoutingMode();
    savedConnectionMode = await SettingsService.getConnectionMode();
    savedQuicPolicy = await SettingsService.getQuicPolicy();
    savedDesktopTunStack = await SettingsService.getDesktopTunStack();
    savedLogLevel = await SettingsService.getLogLevel();
    savedAutoConnect = await SettingsService.getAutoConnect();
    // v1.0.21 hotfix: hydrate userStoppedProvider from disk so
    // _maybeAutoConnect() sees the manual-stop intent even on engine
    // recreate / cold start. Without this, the provider's default (false)
    // lets auto-connect fire after a user had explicitly disconnected.
    savedManualStopped = await SettingsService.getManualStopped();
    savedSystemProxy = await SettingsService.getSystemProxyOnConnect();
    savedLanguage = await SettingsService.getLanguage();
    savedTestUrl = await SettingsService.getTestUrl();
    savedCloseBehavior = await SettingsService.getCloseBehavior();
    savedToggleHotkey = await SettingsService.getToggleHotkey();
    savedDelayResults = await SettingsService.getDelayResults();
    savedTabIndex = await SettingsService.getLastTabIndex();
    savedBuiltTabs = await SettingsService.getBuiltTabs();
    savedOnboarding = await SettingsService.getHasSeenOnboarding();
    savedPersona = await SettingsService.get<String>('onboardingPersona');
    savedTileShowNodeInfo = await SettingsService.getTileShowNodeInfo();

    // Profile fetch is gated on token presence — only one secure-storage
    // read here, and only if we actually need it.
    if (savedToken != null && savedToken.isNotEmpty) {
      savedProfile = await authService
          .getCachedProfile()
          .timeout(bootstrapStorageTimeout, onTimeout: () => null);
    }
  } catch (e, st) {
    debugPrint(
      '[Bootstrap] data gather threw — runApp will use safe defaults: $e\n$st',
    );
    // The pre-declared defaults above are already populated. Continue
    // straight to runApp() rather than letting the exception escape and
    // white-screen the user.
  }

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

  // ── Orphaned system-proxy cleanup ───────────────────────────────────────
  // If the last session crashed / was SIGKILLed / lost power while holding
  // the system proxy, the OS is left pointing at a dead 127.0.0.1:7890 and
  // every HTTP client on the machine looks "offline". The dirty flag lives
  // in SettingsService across sessions; if it's set and core isn't running
  // yet (we haven't started it), unconditionally reassert clear.
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await SystemProxyManager.cleanupIfDirty();
  }

  // ── Signal-driven shutdown cleanup (macOS / Linux) ──────────────────────
  // Catches system shutdown, `kill`, and Ctrl+C — paths that bypass the
  // Dart tray/window-close handlers. Windows has no POSIX signals; its
  // WM_ENDSESSION is handled in windows/runner/flutter_window.cpp. Keeps
  // the 2s cap in lockstep with _handleQuit so behaviour is consistent.
  if (Platform.isMacOS || Platform.isLinux) {
    for (final sig in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
      sig.watch().listen((_) async {
        try {
          await CoreActions.clearSystemProxyStatic().timeout(
            const Duration(seconds: 2),
          );
        } catch (e) {
          // Fire-and-forget — writeTagged does not await the file write,
          // so exit(0) below is never blocked by logging. If the buffered
          // write loses its race with process termination, that is fine:
          // the proxy-clear failure we care about is also logged by the
          // OS-side networksetup stderr.
          EventLog.writeTagged(
            'App',
            'signal_proxy_clear_failed',
            context: {'error': e},
          );
        }
        exit(0);
      });
    }
  }

  // Configure launch at startup (desktop only)
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
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

  // Warm the NodeTelemetry inventory cache from the active profile so
  // URL-test / smart-node features have fp/type lookups available before
  // the user triggers a subscription sync. Fire-and-forget — never blocks
  // cold start, never throws.
  if (savedProfileId != null && savedProfileId.isNotEmpty) {
    // Bind to a final local so the closure captures a non-nullable
    // value — Dart's flow analysis doesn't promote a mutable outer
    // var across the closure boundary.
    final activeProfileId = savedProfileId;
    unawaited(
      NodeTelemetry.ensureInventoryLoaded(
        loadActiveConfig: () => ProfileService.loadConfig(activeProfileId),
      ),
    );
  }

  // Initialize core manager
  CoreManager.instance;

  // ── Global hotkeys (desktop) ─────────────────────────────────────────────
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await hotKeyManager.unregisterAll();
  }

  runApp(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) => savedTheme),
        languageProvider.overrideWith((ref) => savedLanguage),
        accentColorProvider.overrideWith((ref) => savedAccentColor),
        subSyncIntervalProvider.overrideWith((ref) => savedSubSyncInterval),
        preloadedProfileIdProvider.overrideWithValue(savedProfileId),
        routingModeProvider.overrideWith((ref) => savedRoutingMode),
        connectionModeProvider.overrideWith((ref) => savedConnectionMode),
        quicPolicyProvider.overrideWith((ref) => savedQuicPolicy),
        desktopTunStackProvider.overrideWith((ref) => savedDesktopTunStack),
        logLevelProvider.overrideWith((ref) => savedLogLevel),
        autoConnectProvider.overrideWith((ref) => savedAutoConnect),
        userStoppedProvider.overrideWith((ref) => savedManualStopped),
        systemProxyOnConnectProvider.overrideWith((ref) => savedSystemProxy),
        testUrlProvider.overrideWith((ref) => savedTestUrl),
        closeBehaviorProvider.overrideWith((ref) => savedCloseBehavior),
        toggleHotkeyProvider.overrideWith((ref) => savedToggleHotkey),
        delayResultsProvider.overrideWith((ref) => savedDelayResults),
        expandedGroupNamesProvider.overrideWith((ref) => <String>{}),
        initialTabIndexProvider.overrideWithValue(savedTabIndex),
        hasSeenOnboardingProvider.overrideWith((ref) => savedOnboarding),
        onboardingPersonaProvider.overrideWith((ref) => savedPersona),
        initialBuiltTabsProvider.overrideWithValue(savedBuiltTabs),
        tileShowNodeInfoProvider.overrideWith((ref) => savedTileShowNodeInfo),
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
      // TranslationProvider feeds slang's `Translations.of(context)` —
      // required for the new `S.of(context)` adapter (which forwards to
      // slang's `t`). Sits inside ProviderScope so Riverpod's languageProvider
      // can still drive the locale change via S.setLanguage().
      child: TranslationProvider(child: const YueLinkApp()),
    ),
  );
}

class YueLinkApp extends ConsumerStatefulWidget {
  const YueLinkApp({super.key});

  @override
  ConsumerState<YueLinkApp> createState() => _YueLinkAppState();
}

class _YueLinkAppState extends ConsumerState<YueLinkApp>
    with WindowListener, WidgetsBindingObserver {
  late final AppTrayController _tray;
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _appLinksSub;

  // Managed provider subscriptions — cleaned up in dispose()
  ProviderSubscription? _langSub;
  ProviderSubscription? _statusSub;
  ProviderSubscription? _groupsSub;
  ProviderSubscription? _profilesSub;
  ProviderSubscription? _hotkeySub;
  ProviderSubscription? _carrierSub;
  ProviderSubscription? _exitIpSub;
  ProviderSubscription? _tileNodeInfoSub;
  ProviderSubscription? _delayResetSub;

  /// Guard to prevent onWindowClose from interfering during programmatic quit.
  bool _isQuitting = false;

  /// True while the initial post-frame recovery has run.
  /// Prevents didChangeAppLifecycleState(resumed) from re-running
  /// _onAppResumed() on the same engine-create cycle.
  bool _initialRecoveryDone = false;

  /// True while `_onAppResumed` is executing. Fast background↔foreground
  /// flips on mobile (and multi-window surface redraws on desktop) can
  /// deliver a second `resumed` before the first handler's awaits return;
  /// without this guard, two handlers race on the same provider invalidations
  /// and `RecoveryManager.checkCoreHealth()` calls.
  bool _resumeInFlight = false;

  @override
  void initState() {
    super.initState();
    _tray = AppTrayController(
      ref: ref,
      showMainWindow: _showMainWindow,
      loadSelectedProfileConfig: () async {
        // Mirrors the old _handleTrayConnect lookup: return null when
        // there's no active profile OR when loading it fails; the
        // controller treats null as "show main window".
        final activeId = ref.read(activeProfileIdProvider);
        if (activeId == null) return null;
        return ProfileService.loadConfig(activeId);
      },
      onQuit: _handleQuit,
    );
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid || Platform.isIOS) {
      _setupVpnRevocationListener();
    }
    if (Platform.isAndroid) {
      _setupTileService();
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
    if (Platform.isMacOS || Platform.isWindows) {
      _tray.init();
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
        _checkForUpdateOnLaunch();
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
      _tray.updateMenu(
        status: ref.read(coreStatusProvider),
        groups: ref.read(proxyGroupsProvider),
      );
    });

    // Sync tray menu with connection state; notify on unexpected disconnect
    _statusSub = ref.listenManual(coreStatusProvider, (prev, next) {
      _tray.updateMenu(status: next, groups: ref.read(proxyGroupsProvider));
      // Update Android Quick Settings tile state (includes transition
      // flag for "连接中..." / "断开中..." intermediate UX).
      if (Platform.isAndroid) {
        _pushTileState();
      }
      if (prev == CoreStatus.running && next == CoreStatus.stopped) {
        if (!ref.read(userStoppedProvider) &&
            !ref.read(recoveryInProgressProvider)) {
          AppNotifier.warning(S.current.disconnectedUnexpected);
        }
      }
    });

    // Sync tray proxy submenu when proxy groups change
    _groupsSub = ref.listenManual(proxyGroupsProvider, (_, groups) {
      _tray.updateMenu(status: ref.read(coreStatusProvider), groups: groups);
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

    // Single source of truth for "core just died → wipe cached delay
    // results". Previously duplicated across main.dart (VPN revoked,
    // resume check), core/managers/core_heartbeat_manager (retry giveup,
    // proxy conflict) and core/managers/core_lifecycle_manager (stop
    // finally). Those call sites now rely on this one listener so the
    // two core/managers files can drop their modules/nodes imports.
    _delayResetSub = ref.listenManual<CoreStatus>(coreStatusProvider, (
      prev,
      next,
    ) {
      if (prev != null &&
          prev != CoreStatus.stopped &&
          next == CoreStatus.stopped) {
        ref.read(delayResultsProvider.notifier).state = {};
        ref.read(delayTestingProvider.notifier).state = {};
      }
    });

    // Android tile subtitle refresh on exit-IP resolution and on the
    // show-node-info toggle. Both are cheap and idempotent.
    if (Platform.isAndroid) {
      _exitIpSub = ref.listenManual(exitIpInfoProvider, (_, __) {
        _pushTileState();
      });
      _tileNodeInfoSub = ref.listenManual(tileShowNodeInfoProvider, (_, __) {
        _pushTileState();
      });
    }
  }

  /// Register VPN revocation listener (Android only).
  ///
  /// Uses the recoveryInProgressProvider as the guard instead of a local
  /// bool, so it stays in sync with the provider-level guard that heartbeat
  /// also respects. This prevents VPN revocation from racing with recovery.
  void _setupVpnRevocationListener() {
    VpnService.listenForRevocation(
      () {
        // Skip if recovery is in progress — the recovery logic will handle
        // state correctly. Without this guard, onVpnRevoked races with
        // _onAppResumed() on engine recreate and resets state prematurely.
        if (ref.read(recoveryInProgressProvider)) {
          debugPrint('[App] VPN revoked during recovery — ignoring');
          return;
        }
        debugPrint('[App] VPN revoked — resetting state');
        resetCoreToStopped(ref);
        // delay-state wipe happens via _delayResetSub (core status → stopped).
        AppNotifier.warning(S.current.disconnectedUnexpected);
      },
      onTransportChanged: (prev, now) async {
        // Wi-Fi → cellular / cellular → Wi-Fi: stale TCP pool + polluted
        // fake-ip mappings kill perceived responsiveness for ~30 s after
        // the switch. Flush both.  Skip the initial "none → wifi" transition
        // at cold start — there's nothing to flush yet.
        if (prev == 'none') return;
        if (CoreManager.instance.isMockMode) return;
        try {
          final api = CoreManager.instance.api;
          if (!await api.isAvailable()) return;
          debugPrint(
            '[App] transport $prev→$now — flushing fake-ip + '
            'closing connections',
          );
          // Fire both in parallel; either one failing isn't fatal.
          await Future.wait<void>([
            api.flushFakeIpCache().then((_) {}).catchError((_) {}),
            api.closeAllConnections().then((_) {}).catchError((_) {}),
          ]);
          // Invalidate cached delay results — proxies that were fast on
          // Wi-Fi may be slow on cellular and vice versa.
          ref.read(delayResultsProvider.notifier).state = {};
        } catch (e) {
          debugPrint('[App] transport-change flush threw: $e');
        }
      },
    );
  }

  /// Set up Android Quick Settings tile integration.
  ///
  /// Initializes the MethodChannel listener for tile toggle requests
  /// and sets the callback to toggle VPN via the existing core lifecycle.
  void _setupTileService() {
    TileService.init();
    TileService.onToggleRequested = _performTileToggle;
    TileService.onOpenPreferences = () {
      // Route long-press (QS_TILE_PREFERENCES) to the Nodes tab.
      ref.read(tileNavRequestProvider.notifier).state = MainShell.tabProxies;
    };
    // Push the current state immediately — the tile may have been added
    // while the app was closed and its SharedPreferences may be stale.
    _pushTileState();
    // Drain any toggle queued by the native ProxyTileService while the
    // engine was still booting (the headless cold-start path).
    Future.microtask(() async {
      if (await TileService.consumePendingToggle()) {
        debugPrint('[App] Draining queued tile toggle from cold-start');
        await _performTileToggle();
      }
    });
  }

  /// Compute and push the full tile state to native — active flag,
  /// transition (starting/stopping), and optional "🇭🇰 香港" subtitle.
  /// Called on any of: core status change, exit-IP resolution, or the
  /// showNodeInTile toggle.
  void _pushTileState() {
    if (!Platform.isAndroid) return;
    final status = ref.read(coreStatusProvider);
    final active = status == CoreStatus.running;
    final transition = switch (status) {
      CoreStatus.starting => 'starting',
      CoreStatus.stopping => 'stopping',
      _ => null,
    };
    String? subtitle;
    if (active && transition == null && ref.read(tileShowNodeInfoProvider)) {
      final info = ref.read(exitIpInfoProvider).value;
      if (info != null && info.flagEmoji.isNotEmpty) {
        final loc = info.locationLine;
        subtitle = loc.isNotEmpty ? '${info.flagEmoji} $loc' : info.flagEmoji;
      }
    }
    TileService.updateState(
      active: active,
      transition: transition,
      subtitle: subtitle,
    );
  }

  Future<void> _performTileToggle() async {
    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.starting || status == CoreStatus.stopping) {
      debugPrint('[App] Tile toggle ignored — core is $status');
      return;
    }
    debugPrint('[App] Tile toggle — current status: $status');
    final actions = ref.read(coreActionsProvider);
    if (status == CoreStatus.running) {
      await actions.stop();
    } else {
      final configYaml = await _loadSelectedProfileConfig();
      if (configYaml != null) {
        await actions.start(configYaml);
      } else {
        debugPrint('[App] Tile toggle: no profile selected, cannot start');
      }
    }
  }

  /// Load the config YAML from the currently selected profile.
  /// Returns null if no profile is selected or loading fails.
  Future<String?> _loadSelectedProfileConfig() async {
    try {
      final activeId = await SettingsService.getActiveProfileId();
      if (activeId == null) return null;
      return await ProfileService.loadConfig(activeId);
    } catch (e) {
      debugPrint('[App] Failed to load profile config: $e');
      return null;
    }
  }

  /// Detect carrier via YueOps after VPN connects.
  /// Fetches the user's real (direct) IP to determine ISP (CT/CU/CM).
  ///
  /// Order matters: `detectCarrier()` fetches `/config` as part of its
  /// Future.wait; `startPolling()` schedules the periodic poll without
  /// firing an immediate one, so we don't hit `/config` twice in the same
  /// tick. The scheduled poll kicks in at its normal 30-minute interval.
  void _startCarrierDetection() {
    final carrier = ref.read(carrierProvider.notifier);
    carrier.detectCarrier();
    carrier.startPolling();
  }

  @override
  void dispose() {
    _langSub?.close();
    _statusSub?.close();
    _groupsSub?.close();
    _profilesSub?.close();
    _hotkeySub?.close();
    _carrierSub?.close();
    _exitIpSub?.close();
    _tileNodeInfoSub?.close();
    _delayResetSub?.close();
    TileService.onToggleRequested = null;
    TileService.onOpenPreferences = null;
    WidgetsBinding.instance.removeObserver(this);
    _appLinksSub?.cancel();
    _tray.dispose();
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

    // SettingsService now coalesces writes — flush any pending changes
    // when the app goes inactive/background/detached so we don't lose
    // them if the OS kills us.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      Telemetry.event(TelemetryEvents.appBackgrounded);
      unawaited(SettingsService.flush());
      unawaited(Telemetry.flush());
    }

    if (state == AppLifecycleState.resumed) {
      Telemetry.event(TelemetryEvents.appResumed);
      // On Android, the first resume after engine recreate is already handled
      // by addPostFrameCallback. Without this guard, _onAppResumed() runs
      // TWICE on the same cycle: once from post-frame, once from here.
      // The double call causes race conditions (concurrent API checks,
      // duplicate stream invalidations, state flip-flop).
      if (Platform.isAndroid && !_initialRecoveryDone) {
        debugPrint(
          '[AppLifecycle] skipping resumed — initial recovery pending',
        );
        return;
      }
      // Second-level guard: coalesce overlapping resume events. If a handler
      // is already running, drop this one — the in-flight call will finish
      // refreshing everything. Without this, two resume events during the
      // same ~1-2s window double-invalidate streams and race on recovery.
      if (_resumeInFlight) {
        debugPrint('[AppLifecycle] resumed coalesced — handler in flight');
        return;
      }
      _resumeInFlight = true;
      _onAppResumed().whenComplete(() {
        _resumeInFlight = false;
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
      // Respect the user's explicit stop. userStoppedProvider is set to
      // true by CoreLifecycleManager.stop() and only cleared on a fresh
      // start(). When it's true, the user tapped disconnect — state must
      // stay stopped until the next user-initiated connect.
      //
      // Bug this guards against: after user stop, the Go core / service
      // helper / PacketTunnel extension can still respond "alive" on the
      // mihomo API for a short window (shutdown sequence in flight, or
      // Service Mode helper's mihomo subprocess still winding down).
      // The old recovery path saw `health.alive && health.apiOk == true`,
      // bumped status → running and wiped userStoppedProvider, so the UI
      // showed "connected" while the TUN fd / system proxy were actually
      // gone — the user had a "connected" indicator and dead network.
      //
      // Engine-recreate on Android (the case this recovery path was
      // written for) is unaffected: Riverpod rebuilds ProviderScope from
      // defaults, so userStoppedProvider reverts to false and we go
      // through the normal health check.
      // v1.0.21 hotfix: also consult the persisted manual-stop flag.
      // The in-memory userStoppedProvider is wiped to its default (false)
      // whenever Riverpod's ProviderScope rebuilds — which happens on
      // every Android engine recreate (background-kill of the Flutter
      // engine while the VPN service + Go core continue running). Without
      // the persisted check, the recovery branch below would see the
      // still-alive mihomo API and pull the UI back to "running" even
      // though the user had explicitly disconnected, leaving them with a
      // "connected" indicator and a dead network.
      final persistedManualStopped = await SettingsService.getManualStopped();
      if (persistedManualStopped && !ref.read(userStoppedProvider)) {
        // Hydrate the in-memory provider from persistence so subsequent
        // listeners (heartbeat, VPN revocation callback) also respect it.
        ref.read(userStoppedProvider.notifier).state = true;
      }
      if (ref.read(userStoppedProvider) || persistedManualStopped) {
        debugPrint(
          '[AppLifecycle] resumed in user-stopped state — '
          'skipping health recovery '
          '(persisted=$persistedManualStopped, '
          'provider=${ref.read(userStoppedProvider)})',
        );
        return;
      }
      ref.read(recoveryInProgressProvider.notifier).state = true;
      try {
        final health = await RecoveryManager.checkCoreHealth();
        // v1.0.22 P0-1: TOCTOU re-check. Between the await above and the
        // state mutations below, the user may have tapped Stop — the
        // first guard at the top of this method only covers the pre-await
        // window. Without this re-check the recovery branch overwrites
        // `coreStatusProvider` to running and clears `userStoppedProvider`,
        // resurrecting the very bug v1.0.21 P0-1 was supposed to fix:
        // UI shows "connected" while TUN fd / system proxy are gone.
        //
        // Re-read both the in-memory provider AND the persisted flag —
        // either becoming true between the two checks means the user
        // stopped during the await, and we must not promote to running.
        final userStoppedNow = ref.read(userStoppedProvider);
        final persistedNow = await SettingsService.getManualStopped();
        if (userStoppedNow || persistedNow) {
          debugPrint(
            '[AppLifecycle] manual stop landed during health-check await — '
            'aborting recovery (provider=$userStoppedNow, '
            'persisted=$persistedNow)',
          );
          ref.read(recoveryInProgressProvider.notifier).state = false;
          return;
        }
        if (health.alive && health.apiOk) {
          debugPrint(
            '[AppLifecycle] core alive but Dart state was $status — recovering',
          );
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
        // Note: on Android the recovery guard stays up so the post-frame
        // `_maybeAutoConnect()` callback can clear it after the cold-start
        // engine-recreate path completes. Other platforms don't take that
        // path on resume, so the `finally` below drops the guard
        // unconditionally — without it, a normal-but-no-mutation resume
        // (e.g. health check returns alive=false on iOS/desktop, which
        // skips the recovery branch) would leave the guard stuck and
        // suppress every subsequent heartbeat tick.
      } catch (e) {
        debugPrint('[AppLifecycle] recovery check failed: $e');
        ref.read(recoveryInProgressProvider.notifier).state = false;
      } finally {
        if (!Platform.isAndroid) {
          ref.read(recoveryInProgressProvider.notifier).state = false;
        }
      }
      return;
    }

    // 3. Normal case: Dart says running — verify core is still alive
    try {
      final health = await RecoveryManager.checkCoreHealth();
      if (!health.alive || !health.apiOk) {
        debugPrint('[AppLifecycle] core dead after resume — resetting state');
        resetCoreToStopped(ref);
        // delay-state wipe happens via _delayResetSub (core status → stopped).
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
        // v1.0.21 hotfix P0-2: system-proxy tamper detection on resume.
        // If the user flipped over to v2rayN / Clash Verge / any other proxy tool
        // while YueLink was backgrounded, the 60 s verify cache would
        // leave the heartbeat unable to notice for up to that TTL —
        // resulting in the "connected but no network" UX. force:true
        // bypasses the cache, and a tampered result immediately triggers
        // restore instead of waiting for the 30 s heartbeat round.
        unawaited(_resumeProxyTamperCheck());
      }
    } catch (e) {
      debugPrint('[AppLifecycle] resume check failed: $e');
    }
  }

  /// v1.0.21 hotfix P0-2: best-effort force-verify + restore on resume.
  /// Runs only when the user has systemProxy mode selected and core is
  /// running. Fire-and-forget: caller doesn't await; any exception is
  /// swallowed and logged so the rest of the resume path is unaffected.
  Future<void> _resumeProxyTamperCheck() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return;
    }
    if (ref.read(connectionModeProvider) != 'systemProxy') return;
    if (!ref.read(systemProxyOnConnectProvider)) return;
    try {
      final port = CoreManager.instance.mixedPort;
      final ok = await SystemProxyManager.verify(port, force: true);
      if (ok == false) {
        debugPrint(
          '[AppLifecycle] systemProxy tampered on resume '
          '(expected 127.0.0.1:$port) — restoring',
        );
        EventLog.write(
          '[AppLifecycle] systemProxy tamper detected on '
          'resume port=$port',
        );
        final restored = await SystemProxyManager.set(port);
        if (!restored) {
          AppNotifier.warning(S.current.errSystemProxyFailed);
        }
      }
    } catch (e) {
      debugPrint('[AppLifecycle] resume tamper check failed: $e');
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
      debugPrint(
        '[Hotkey] Skipping global hotkey on Linux (Wayland not supported)',
      );
      return;
    }
    try {
      final stored = ref.read(toggleHotkeyProvider);
      final toggleKey = parseStoredHotkey(stored);
      await hotKeyManager.register(
        toggleKey,
        keyDownHandler: (_) {
          _tray.handleToggle();
        },
      );
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
      await hotKeyManager.register(
        toggleKey,
        keyDownHandler: (_) {
          _tray.handleToggle();
        },
      );
    } catch (e) {
      debugPrint('[App] hotkey re-registration: $e');
    }
  }

  // ── Window manager callbacks ─────────────────────────────────────

  @override
  void onWindowClose() async {
    // If programmatic quit is in progress, don't interfere
    if (_isQuitting) return;

    // v1.0.22 P0-3: delegate the quit-vs-hide decision to the pure
    // policy helper. Adds a Windows + core-running carve-out so the
    // Win11 taskbar's right-click → Close window does not silently
    // hide while the VPN keeps running (the "无法退出" report).
    final shouldQuit = shouldQuitOnWindowClose(
      platform: Platform.operatingSystem,
      status: ref.read(coreStatusProvider),
      behavior: ref.read(closeBehaviorProvider),
    );
    if (shouldQuit) {
      await _handleQuit();
    } else {
      await windowManager.hide();
    }
  }

  // ── Tray (Desktop Quick Control) ─────────────────────────────────
  //
  // All tray icon / menu / dispatch logic lives in
  // lib/shared/desktop/app_tray_controller.dart. Connect/disconnect routes
  // through the same CoreManager / CoreActions / ProxyGroupsNotifier paths
  // the main UI uses — no independent connection logic.

  Future<void> _showMainWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[Tray] show window: $e');
    }
  }

  Future<void> _handleQuit() async {
    _isQuitting = true;

    // v1.0.21 hotfix P1-5: hard-cap the quit sequence with a watchdog
    // that runs in a SEPARATE isolate. Previously this was a
    // Future.delayed(3s) scheduled on the main isolate's event loop —
    // which is exactly the loop being starved when platform channel
    // awaits (windowManager.destroy / trayManager.destroy /
    // ServiceClient.stop) sit in blocking native calls under Win11.
    // User-reported symptom: tray → Quit, window closes, process stays
    // resident. The watchdog isolate has its own event loop so its
    // Future.delayed fires regardless of main-isolate jam; on fire it
    // SIGKILLs our pid which OS-level terminates the whole process.
    // Desktop only — mobile doesn't hit _handleQuit.
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await spawnQuitWatchdog(delay: const Duration(seconds: 3));
      } catch (e) {
        // Isolate spawn itself failed — fall back to a Dart Timer.
        // Worse safety net than the isolate (same jam risk) but better
        // than nothing; at least on a healthy event loop it still fires.
        debugPrint(
          '[Quit] watchdog isolate spawn failed: $e — '
          'falling back to Dart Timer',
        );
        Future.delayed(const Duration(seconds: 3), () {
          try {
            Process.killPid(pid, ProcessSignal.sigkill);
          } catch (e) {
            EventLog.writeTagged(
              'Quit',
              'quit_kill_fallback_failed',
              context: {'error': e},
            );
          }
          exit(0);
        });
      }
    }

    try {
      final status = ref.read(coreStatusProvider);
      if (status == CoreStatus.running) {
        await ref
            .read(coreActionsProvider)
            .stop()
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      }
      try {
        _singleInstanceServer?.close();
      } catch (e) {
        EventLog.writeTagged(
          'Quit',
          'quit_server_close_failed',
          context: {'error': e},
        );
      }
      // System proxy clear is the user-visible correctness requirement —
      // must complete before exit, or the OS keeps routing traffic through
      // a dead mixed-port. 2s cap covers the slow macOS path (N network
      // services × 3 networksetup calls); the global 3s timer above is the
      // hard safety net if this itself hangs.
      try {
        await CoreActions.clearSystemProxyStatic().timeout(
          const Duration(seconds: 2),
        );
      } catch (e) {
        EventLog.writeTagged(
          'Quit',
          'quit_proxy_clear_failed',
          context: {'error': e},
        );
      }
      try {
        trayManager.destroy();
      } catch (e) {
        EventLog.writeTagged(
          'Quit',
          'quit_tray_destroy_failed',
          context: {'error': e},
        );
      }
      try {
        windowManager.setPreventClose(false);
      } catch (e) {
        EventLog.writeTagged(
          'Quit',
          'quit_prevent_close_failed',
          context: {'error': e},
        );
      }
      try {
        windowManager.destroy();
      } catch (e) {
        EventLog.writeTagged(
          'Quit',
          'quit_window_destroy_failed',
          context: {'error': e},
        );
      }
    } catch (e) {
      EventLog.writeTagged(
        'Quit',
        'quit_cleanup_failed',
        context: {'error': e},
      );
    }
    exit(0);
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
        debugPrint(
          '[AutoConnect] config file not found for profile: $activeId',
        );
        return;
      }

      debugPrint(
        '[AutoConnect] starting with profile: $activeId (${config.length} bytes)',
      );
      final ok = await ref.read(coreActionsProvider).start(config);
      debugPrint('[AutoConnect] result: $ok');
    } catch (e) {
      debugPrint('[AutoConnect] startup failed: $e');
      // Don't crash — user can start manually from dashboard
    }
  }

  /// Auto-check for app updates on launch (standalone distribution only).
  /// Skipped versions, store builds, and the user's "auto-check off" setting
  /// are all filtered by UpdateChecker.check(auto: true).
  void _checkForUpdateOnLaunch() {
    if (!EnvConfig.isStandalone) return;
    UpdateChecker.instance.check(auto: true).then((info) {
      if (info != null && mounted) {
        AppNotifier.info(
          S.current.isEn
              ? 'New version v${info.latestVersion} available'
              : '发现新版本 v${info.latestVersion}',
        );
      }
    });
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
    final accentHex = ref.watch(accentColorProvider);

    // Parse accent color from hex string
    final accentColor = Color(int.parse('FF$accentHex', radix: 16));

    // Side-effect-only providers — heartbeat and subscription sync. They
    // exist to keep timers alive and don't emit a value the MaterialApp
    // cares about. Use ref.listen instead of ref.watch so the intent is
    // explicit: "subscribe to lifecycle, never rebuild me on emissions".
    // (Both are Provider<void>; ref.watch happened to work because null
    // == null, but ref.listen documents the contract clearly.)
    ref.listen<void>(coreHeartbeatProvider, (_, __) {});
    ref.listen<void>(subscriptionSyncProvider, (_, __) {});

    // DynamicColorBuilder pulls the OS palette (Material You) on Android 12+
    // and macOS, falling back to our seeded accentColor elsewhere. The
    // returned ColorSchemes are only applied when the user has NOT manually
    // picked an accent — once they pick a colour, our explicit accent wins
    // so the app doesn't spontaneously change palette under them.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic =
            accentColor == YLColors.primary &&
            lightDynamic != null &&
            darkDynamic != null;
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          locale: Locale(language),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: themeMode,
          theme: buildTheme(
            Brightness.light,
            accentColor: accentColor,
            dynamicScheme: useDynamic ? lightDynamic : null,
          ),
          darkTheme: buildTheme(
            Brightness.dark,
            accentColor: accentColor,
            dynamicScheme: useDynamic ? darkDynamic : null,
          ),
          home: const _AuthGate(),
        );
      },
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
    final persona = ref.watch(onboardingPersonaProvider);

    // 1a. Persona prompt (feature-flagged, first-launch only).
    //     Only shown when the `onboarding_split` flag is on AND the user
    //     hasn't answered yet. Both personas fall through to the normal
    //     OnboardingPage — we only record the answer here for later UX
    //     tailoring (skip-tooltips etc.). When the flag is off this branch
    //     is inert and the visual flow is unchanged.
    if (!hasSeenOnboarding &&
        persona == null &&
        FeatureFlags.I.boolFlag('onboarding_split')) {
      return PersonaPromptPage(
        onChosen: (chosen) async {
          await SettingsService.set('onboardingPersona', chosen);
          ref.read(onboardingPersonaProvider.notifier).state = chosen;
        },
      );
    }

    // 1b. Onboarding first — before login, on ALL platforms
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
  static const tabProxies = 1;
  static const tabEmby = 2;
  static const tabSettings = 3;

  static void switchToTab(BuildContext context, int index) {
    context.findAncestorStateOfType<_MainShellState>()?.switchTab(index);
  }

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _currentIndex;
  late final Map<int, bool> _builtTabs;
  ProviderSubscription? _tileNavSub;

  void switchTab(int index) {
    setState(() {
      _currentIndex = index;
      _builtTabs[index] = true;
    });
    SettingsService.setLastTabIndex(index);
    SettingsService.setBuiltTabs(
      _builtTabs.keys.where((k) => _builtTabs[k] == true).toList(),
    );
  }

  static const _pages = [
    DashboardPage(),
    NodesPage(),
    _EmbyTabPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = ref
        .read(initialTabIndexProvider)
        .clamp(0, _pages.length - 1);
    // Restore previously visited tabs from persistence (Android process restore)
    final savedTabs = ref.read(initialBuiltTabsProvider);
    _builtTabs = <int, bool>{
      for (final i in savedTabs)
        if (i >= 0 && i < _pages.length) i: true,
    };
    _builtTabs[_currentIndex] = true;

    // Listen for one-shot navigation requests from outside the widget
    // tree (currently: Android tile long-press). Reset to null after
    // handling so a re-set to the same value still fires.
    _tileNavSub = ref.listenManual<int?>(tileNavRequestProvider, (_, next) {
      if (next == null) return;
      if (next >= 0 && next < _pages.length) switchTab(next);
      // Use microtask so the notifier isn't mutated during the notification.
      Future.microtask(
        () => ref.read(tileNavRequestProvider.notifier).state = null,
      );
    });
  }

  @override
  void dispose() {
    _tileNavSub?.close();
    super.dispose();
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
                      _builtTabs[i] == true
                          ? _pages[i]
                          : const SizedBox.shrink(),
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
      (
        const Icon(Icons.home_outlined, size: 20),
        const Icon(Icons.home_filled, size: 20),
        s.navHome,
      ),
      (
        const Icon(Icons.public_outlined, size: 20),
        const Icon(Icons.public, size: 20),
        s.navProxies,
      ),
      (
        const Icon(Icons.play_circle_outline, size: 20),
        const Icon(Icons.play_circle_filled, size: 20),
        s.navEmby,
      ),
      (
        const Icon(Icons.person_outline_rounded, size: 20),
        const Icon(Icons.person_rounded, size: 20),
        s.navMine,
      ),
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
      // Unified tab bar across all platforms — iOS-style blurred background
      // with hairline top border, matching Telegram's cross-platform design.
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: _currentIndex,
        onTap: (i) => switchTab(i),
        backgroundColor: Theme.of(
          context,
        ).colorScheme.surface.withValues(alpha: 0.85),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.33,
          ),
        ),
        activeColor: Theme.of(context).colorScheme.primary,
        inactiveColor: Theme.of(context).brightness == Brightness.dark
            ? YLColors.zinc400
            : YLColors.zinc500,
        items: [
          for (int i = 0; i < mobileItems.length; i++)
            BottomNavigationBarItem(
              icon: mobileItems[i].$1,
              activeIcon: mobileItems[i].$2,
              label: mobileItems[i].$3,
            ),
        ],
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
      (Icons.play_circle_outline, Icons.play_circle_filled, s.navEmby),
    ];

    return Container(
      width: 230,
      color: isDark
          ? YLColors.zinc900
          : YLColors.zinc50, // Sidebar one shade lighter than zinc100 bg
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Brand ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: YLColors.primary,
                    borderRadius: BorderRadius.circular(YLRadius.xl),
                  ),
                  child: const Icon(
                    Icons.link_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '悦通',
                      style: YLText.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'AI · 全球加速',
                      style: YLText.caption.copyWith(color: YLColors.zinc400),
                    ),
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
                Icon(
                  icon,
                  size: 16,
                  color: isActive
                      ? (isDark ? Colors.white : YLColors.zinc900)
                      : YLColors.zinc500,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: YLText.body.copyWith(
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? (isDark ? Colors.white : YLColors.zinc900)
                        : YLColors.zinc500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Emby tab wrapper ──────────────────────────────────────────────────────────

/// Full-screen tab wrapper for 悦视频.
/// Watches [embyProvider] and delegates to [EmbyMediaPage] (native) or
/// [EmbyWebPage] (WebView fallback) once info is loaded.
class _EmbyTabPage extends ConsumerWidget {
  const _EmbyTabPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final emby = ref.watch(embyProvider);
    return emby.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, __) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => ref.invalidate(embyProvider),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(s.retry),
              ),
            ],
          ),
        ),
      ),
      data: (info) {
        if (info == null || !info.hasAccess) {
          return Scaffold(body: Center(child: Text(s.mineEmbyNoAccess)));
        }
        if (info.hasNativeAccess) {
          return EmbyMediaPage(
            serverUrl: info.serverBaseUrl!,
            userId: info.parsedUserId!,
            accessToken: info.parsedAccessToken!,
            serverId: info.parsedServerId ?? '',
          );
        }
        return EmbyWebPage(url: info.launchUrl!);
      },
    );
  }
}

// ── Crash logging ─────────────────────────────────────────────────────────────

// Error logging moved to ErrorLogger (lib/services/error_logger.dart).
// Call ErrorLogger.init() in main() to set up FlutterError.onError +
// PlatformDispatcher.onError + optional remote reporting (Sentry etc.).
