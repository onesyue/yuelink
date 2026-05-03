import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:window_manager/window_manager.dart';

import 'constants.dart';
import 'i18n/app_strings.dart';
import 'i18n/strings_g.dart';
import 'modules/nodes/providers/nodes_providers.dart'
    show
        DelayResultsNotifier,
        ExpandedGroupNamesNotifier,
        TestUrlNotifier,
        delayResultsProvider,
        delayTestingProvider,
        expandedGroupNamesProvider,
        proxyGroupsProvider,
        testUrlProvider;
import 'modules/settings/providers/settings_providers.dart';
import 'modules/onboarding/onboarding_page.dart';
import 'modules/onboarding/persona_prompt_page.dart';
import 'modules/onboarding/ios_install_guide_page.dart';
import 'modules/carrier/carrier_provider.dart';
import 'modules/yue_auth/presentation/auth_loading_fallback.dart';
import 'modules/yue_auth/presentation/yue_auth_page.dart';
import 'modules/yue_auth/providers/yue_auth_providers.dart';
import 'modules/dashboard/providers/dashboard_providers.dart';
import 'core/providers/core_provider.dart';
import 'modules/profiles/providers/profiles_providers.dart';
import 'shared/app_notifier.dart';
import 'core/kernel/core_manager.dart';
import 'core/platform/macos_gatekeeper.dart';
import 'core/platform/tile_service.dart';
import 'core/platform/window_close_policy.dart';
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
import 'app/android_tile_controller.dart';
import 'app/app_quit_controller.dart';
import 'app/app_resume_controller.dart';
import 'app/bootstrap/bootstrap_settings.dart';
import 'app/bootstrap/runtime_bootstrap.dart';
import 'app/bootstrap/single_instance_guard.dart';
import 'app/app_tray_controller.dart';
import 'app/deeplink_controller.dart';
import 'app/deeplink_provider.dart';
import 'app/hotkey_controller.dart';
import 'app/main_shell.dart';
import 'theme.dart';

/// Global navigator key for deep-link navigation outside widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

/// Pre-loaded onboarding flag (avoids async blank flash in _AuthGate).
final hasSeenOnboardingProvider =
    NotifierProvider<HasSeenOnboardingNotifier, bool>(
      HasSeenOnboardingNotifier.new,
    );

class HasSeenOnboardingNotifier extends Notifier<bool> {
  HasSeenOnboardingNotifier([this._initial = false]);
  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
}

/// Pre-loaded onboarding persona ('newcomer' | 'experienced' | 'unknown' | null).
/// Null means the persona prompt hasn't been answered yet. Gated behind the
/// `onboarding_split` feature flag in `_AuthGate`.
final onboardingPersonaProvider =
    NotifierProvider<OnboardingPersonaNotifier, String?>(
      OnboardingPersonaNotifier.new,
    );

class OnboardingPersonaNotifier extends Notifier<String?> {
  OnboardingPersonaNotifier([this._initial]);
  final String? _initial;

  @override
  String? build() => _initial;

  void set(String? value) => state = value;
}

// initialTabIndexProvider, initialBuiltTabsProvider, tileNavRequestProvider
// moved to lib/app/main_shell.dart together with MainShell itself.
//
// tileShowNodeInfoProvider moved to lib/modules/settings/providers/
// settings_providers.dart as part of the Android tile controller split.

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

  configureAndroidEdgeToEdge();
  configureImageCacheLimits();
  initErrorLogging();
  initTelemetryAndFeatureFlags();

  final bootstrap = await loadBootstrapSettingsSnapshot();

  // Apply global strings language before runApp (for tray etc.)
  S.setLanguage(bootstrap.savedLanguage);

  // ── Single instance guard (macOS / Windows) ─────────────────────────────
  // Must run before windowManager.ensureInitialized() so the second instance
  // can exit(0) before creating a window. The first instance's server is ready
  // to receive "show" commands as soon as windowManager is initialized below.
  if (Platform.isMacOS || Platform.isWindows) {
    final isFirst = await SingleInstanceGuard.ensure();
    if (!isFirst) {
      exit(0);
    }
  }

  await cleanupDirtySystemProxy();
  installSignalProxyCleanup();
  setupLaunchAtStartup();
  await initializeDesktopWindow();

  // Warm the NodeTelemetry inventory cache from the active profile so
  // URL-test / smart-node features have fp/type lookups available before
  // the user triggers a subscription sync. Fire-and-forget — never blocks
  // cold start, never throws.
  if (bootstrap.savedProfileId != null &&
      bootstrap.savedProfileId!.isNotEmpty) {
    // Bind to a final local so the closure captures a non-nullable
    // value — Dart's flow analysis doesn't promote a mutable outer
    // var across the closure boundary.
    final activeProfileId = bootstrap.savedProfileId!;
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
        themeProvider.overrideWith(() => ThemeNotifier(bootstrap.savedTheme)),
        languageProvider.overrideWith(
          () => LanguageNotifier(bootstrap.savedLanguage),
        ),
        accentColorProvider.overrideWith(
          () => AccentColorNotifier(bootstrap.savedAccentColor),
        ),
        subSyncIntervalProvider.overrideWith(
          () => SubSyncIntervalNotifier(bootstrap.savedSubSyncInterval),
        ),
        preloadedProfileIdProvider.overrideWithValue(bootstrap.savedProfileId),
        routingModeProvider.overrideWith(
          () => RoutingModeNotifier(bootstrap.savedRoutingMode),
        ),
        connectionModeProvider.overrideWith(
          () => ConnectionModeNotifier(bootstrap.savedConnectionMode),
        ),
        quicPolicyProvider.overrideWith(
          () => QuicPolicyNotifier(bootstrap.savedQuicPolicy),
        ),
        desktopTunStackProvider.overrideWith(
          () => DesktopTunStackNotifier(bootstrap.savedDesktopTunStack),
        ),
        logLevelProvider.overrideWith(
          () => LogLevelNotifier(bootstrap.savedLogLevel),
        ),
        autoConnectProvider.overrideWith(
          () => AutoConnectNotifier(bootstrap.savedAutoConnect),
        ),
        userStoppedProvider.overrideWith(
          () => UserStoppedNotifier(bootstrap.savedManualStopped),
        ),
        systemProxyOnConnectProvider.overrideWith(
          () => SystemProxyOnConnectNotifier(bootstrap.savedSystemProxy),
        ),
        testUrlProvider.overrideWith(
          () => TestUrlNotifier(bootstrap.savedTestUrl),
        ),
        closeBehaviorProvider.overrideWith(
          () => CloseBehaviorNotifier(bootstrap.savedCloseBehavior),
        ),
        toggleHotkeyProvider.overrideWith(
          () => ToggleHotkeyNotifier(bootstrap.savedToggleHotkey),
        ),
        delayResultsProvider.overrideWith(
          () => DelayResultsNotifier(bootstrap.savedDelayResults),
        ),
        expandedGroupNamesProvider.overrideWith(
          () => ExpandedGroupNamesNotifier(<String>{}),
        ),
        initialTabIndexProvider.overrideWithValue(bootstrap.savedTabIndex),
        hasSeenOnboardingProvider.overrideWith(
          () => HasSeenOnboardingNotifier(bootstrap.savedOnboarding),
        ),
        onboardingPersonaProvider.overrideWith(
          () => OnboardingPersonaNotifier(bootstrap.savedPersona),
        ),
        initialBuiltTabsProvider.overrideWithValue(bootstrap.savedBuiltTabs),
        tileShowNodeInfoProvider.overrideWith(
          () => TileShowNodeInfoNotifier(bootstrap.savedTileShowNodeInfo),
        ),
        // Pre-loaded auth state: eliminates blank screen from async
        // AuthNotifier._init() in the common case. v1.0.22 P0-4b: when
        // bootstrap couldn't read auth state confidently (timeout or
        // throw), pass `null` so AuthNotifier.build() falls into _init()
        // for a fresh attempt — without this, a transient SecureStorage
        // hang at cold start would cache a permanent "loggedOut" view of
        // a user who actually has a token on disk.
        preloadedAuthStateProvider.overrideWithValue(
          bootstrap.authBootstrapUncertain
              ? null
              : (bootstrap.savedToken != null &&
                    bootstrap.savedToken!.isNotEmpty)
              ? AuthState(
                  status: AuthStatus.loggedIn,
                  token: bootstrap.savedToken!,
                  userProfile: bootstrap.savedProfile,
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
  late final AndroidTileController _tile;
  late final HotkeyController _hotkey;
  late final AppQuitController _quit;
  late final AppResumeController _resume;
  late final DeeplinkController _deeplink;

  // Managed provider subscriptions — cleaned up in dispose()
  ProviderSubscription? _langSub;
  ProviderSubscription? _statusSub;
  ProviderSubscription? _groupsSub;
  ProviderSubscription? _profilesSub;
  ProviderSubscription? _carrierSub;
  ProviderSubscription? _exitIpSub;
  ProviderSubscription? _tileNodeInfoSub;
  ProviderSubscription? _entitlementSuspectSub;
  ProviderSubscription? _delayResetSub;
  ProviderSubscription? _routingModeTraySub;
  ProviderSubscription? _connectionModeTraySub;

  /// True while the initial post-frame recovery has run.
  /// Prevents didChangeAppLifecycleState(resumed) from re-running
  /// _onAppResumed() on the same engine-create cycle.
  bool _initialRecoveryDone = false;

  // Resume in-flight flag is owned by AppResumeController; reach it via
  // `_resume.inFlight`. The controller coalesces overlapping run() calls
  // so main.dart no longer guards the second-event race itself.

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
      onQuit: () => _quit.runQuit(),
    );
    _tile = AndroidTileController(
      ref: ref,
      // Reuses the same active-profile lookup the tray controller does —
      // tile-tap → start core uses whichever profile the user picked
      // last, falling back to "no profile" silently.
      loadProfileConfig: _loadSelectedProfileConfig,
      onTilePreferences: () {
        // Long-press on the QS tile (QS_TILE_PREFERENCES intent) →
        // open the Nodes tab once MainShell mounts. Decoupled via
        // tileNavRequestProvider so the controller doesn't need to
        // know about MainShell's BuildContext.
        ref.read(tileNavRequestProvider.notifier).set(MainShell.tabProxies);
      },
    );
    _hotkey = HotkeyController(
      ref: ref,
      // Tray + global hotkey share the same toggle action — pressing
      // Ctrl+Alt+C does exactly what right-click → Connect/Disconnect
      // in the system tray menu does, including the routing through
      // CoreActions / ProxyGroupsNotifier.
      onTriggered: _tray.handleToggle,
    );
    _quit = AppQuitController(
      ref: ref,
      closeSingleInstanceServer: SingleInstanceGuard.close,
    );
    _resume = AppResumeController(ref: ref);
    _deeplink = DeeplinkController(
      ref: ref,
      deepLinkUrlProvider: deepLinkUrlProvider,
    );
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      _resume.setupVpnRevocationListener();
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      _resume.startNetworkChangePolling();
    }
    if (Platform.isAndroid) {
      _tile.init();
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
          await _resume.run().timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              debugPrint('[Init] Android resume recovery timed out');
            },
          );
          // Mark initial recovery as done so didChangeAppLifecycleState
          // doesn't re-run resume on this same engine-create cycle.
          _initialRecoveryDone = true;
        }
        await _maybeAutoConnect().timeout(
          Platform.isAndroid
              ? const Duration(seconds: 8)
              : const Duration(seconds: 20),
          onTimeout: () {
            debugPrint('[Init] auto-connect timed out');
          },
        );
        // Clear the recovery guard AFTER auto-connect completes.
        // This ensures heartbeat and VPN revocation callbacks don't interfere
        // during the entire recovery + auto-connect sequence.
        if (Platform.isAndroid) {
          ref.read(recoveryInProgressProvider.notifier).set(false);
        }
        _checkSubscriptionExpiry();
        _checkForUpdateOnLaunch();
        _deeplink.init(mounted: () => mounted);
        _hotkey.init();
        // macOS-only silent Gatekeeper repair. Fire-and-forget — never
        // blocks the launch path, never surfaces UI in Settings, only
        // prompts for the system password if the running .app still has
        // the `com.apple.quarantine` xattr (typically right after a fresh
        // download or self-update). Idempotent: once xattr is cleared,
        // hasQuarantine() returns false and this becomes a no-op on
        // subsequent launches.
        if (Platform.isMacOS) {
          unawaited(_maybeRepairGatekeeper());
        }
      } catch (e) {
        debugPrint('[Init] post-frame init error (non-fatal): $e');
        // Always clear recovery guard even on error
        if (Platform.isAndroid) {
          ref.read(recoveryInProgressProvider.notifier).set(false);
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
        _tile.pushState();
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

    // v1.0.22 P2-2: refresh tray statusLine when routing/connection
    // mode changes. The tooltip + menu header now encode both modes
    // (e.g. "YueLink · 已连接 · 规则 · TUN · HK-1") so the user can
    // identify the active configuration without opening the main
    // window — but only if the tray repaints on each switch.
    _routingModeTraySub = ref.listenManual(routingModeProvider, (prev, next) {
      if (prev == next) return;
      _tray.updateMenu(
        status: ref.read(coreStatusProvider),
        groups: ref.read(proxyGroupsProvider),
      );
    });
    _connectionModeTraySub = ref.listenManual(connectionModeProvider, (
      prev,
      next,
    ) {
      if (prev == next) return;
      _tray.updateMenu(
        status: ref.read(coreStatusProvider),
        groups: ref.read(proxyGroupsProvider),
      );
    });

    // Re-check subscription expiry after profiles are updated
    _profilesSub = ref.listenManual(profilesProvider, (prev, next) {
      if (next is AsyncData) _checkSubscriptionExpiry();
    });

    // Hotkey re-registration on settings change is handled inside
    // HotkeyController.init() — see _hotkey wiring in initState.

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
        ref.read(delayResultsProvider.notifier).clear();
        ref.read(delayTestingProvider.notifier).clear();
      }
    });

    // Android tile subtitle refresh on exit-IP resolution and on the
    // show-node-info toggle. Both are cheap and idempotent.
    if (Platform.isAndroid) {
      _exitIpSub = ref.listenManual(exitIpInfoProvider, (_, _) {
        _tile.pushState();
      });
      _tileNodeInfoSub = ref.listenManual(tileShowNodeInfoProvider, (_, _) {
        _tile.pushState();
      });
    }

    // iOS only: PacketTunnel reached .connected then dropped within 10 s →
    // signature of an untrusted IPA (TrollStore / unsigned re-sign). Push a
    // full-screen install-method guide so users stop hitting "connect" and
    // wondering why nothing happens. Listener is plumbed regardless of
    // platform (provider is null on non-iOS) and gated by Platform.isIOS at
    // the dispatch site so we don't accidentally surface the iOS guide on
    // Android even if someone misuses the provider in the future.
    _entitlementSuspectSub = ref.listenManual(iosEntitlementSuspectProvider, (
      prev,
      next,
    ) {
      if (next == null || next == prev) return;
      if (!Platform.isIOS) return;
      final ctx = navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final secs = (next.elapsedMs / 1000).toStringAsFixed(1);
      IOSInstallGuidePage.push(
        ctx,
        errorContext: S.current.iosGuideErrorBanner(seconds: secs),
      );
    });
  }

  /// Load the config YAML from the currently selected profile.
  /// Returns null if no profile is selected or loading fails.
  /// Used by [AndroidTileController] (and any other path that needs to
  /// kick off a connect from outside the dashboard) — kept here in
  /// _YueLinkAppState because the lookup is shared across the tray
  /// controller and the tile controller, and pulling in `ProfileService`
  /// is cheap.
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
    _carrierSub?.close();
    _exitIpSub?.close();
    _tileNodeInfoSub?.close();
    _entitlementSuspectSub?.close();
    _delayResetSub?.close();
    _routingModeTraySub?.close();
    _connectionModeTraySub?.close();
    TileService.onToggleRequested = null;
    TileService.onOpenPreferences = null;
    WidgetsBinding.instance.removeObserver(this);
    _resume.dispose();
    unawaited(_deeplink.dispose());
    _tray.dispose();
    unawaited(_hotkey.dispose());
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  // ── App lifecycle ─────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Battery optimization: pause WebSocket streams and reduce heartbeat
    // frequency when the app goes to background.
    ref
        .read(appInBackgroundProvider.notifier)
        .set(state != AppLifecycleState.resumed);

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
      // On Android, the first resume after engine recreate is already
      // handled by addPostFrameCallback. Without this guard, the resume
      // handler runs TWICE on the same cycle: once from post-frame, once
      // from here. The double call causes race conditions (concurrent
      // API checks, duplicate stream invalidations, state flip-flop).
      if (Platform.isAndroid && !_initialRecoveryDone) {
        debugPrint(
          '[AppLifecycle] skipping resumed — initial recovery pending',
        );
        return;
      }
      // Second-level coalescing (in-flight check) is owned by
      // AppResumeController.run() — call unconditionally and trust the
      // controller to drop duplicates.
      _resume.run().whenComplete(() {
        // Clear recovery guard for subsequent resume calls
        // (background→foreground). The initial engine-create path
        // clears this in the post-frame callback.
        if (Platform.isAndroid) {
          ref.read(recoveryInProgressProvider.notifier).set(false);
        }
      });
    }
  }

  // (Resume + deeplink handling live in AppResumeController + DeeplinkController.)

  // ── Global hotkeys ────────────────────────────────────────────────────────
  // All registration / re-registration / cleanup lives in
  // lib/app/hotkey_controller.dart. _hotkey is wired in
  // initState; init() runs from the post-frame callback; dispose()
  // unregisters via _hotkey.dispose() in dispose().

  // ── Window manager callbacks ─────────────────────────────────────

  @override
  void onWindowClose() async {
    // If programmatic quit is in progress, don't interfere
    if (_quit.isQuitting) return;

    // Delegate the quit-vs-hide decision to the pure policy helper.
    // Honours the user's `closeBehavior` setting strictly on Windows
    // and macOS — the previous v1.0.22 P0-3 carve-out (Windows +
    // running → force-quit) was reverted because it overrode users
    // who explicitly chose 'tray'. Users who want quit-on-X set
    // `closeBehavior='exit'`; those who hit "无法退出" use the tray
    // right-click → Quit menu.
    final shouldQuit = shouldQuitOnWindowClose(
      platform: Platform.operatingSystem,
      status: ref.read(coreStatusProvider),
      behavior: ref.read(closeBehaviorProvider),
    );
    if (shouldQuit) {
      await _quit.runQuit();
    } else {
      await windowManager.hide();
    }
  }

  // ── Tray (Desktop Quick Control) ─────────────────────────────────
  //
  // All tray icon / menu / dispatch logic lives in
  // lib/app/app_tray_controller.dart. Connect/disconnect routes
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

  /// Detect-and-repair the macOS `com.apple.quarantine` xattr on the
  /// running `.app` bundle. Fully silent unless the OS itself surfaces
  /// the standard administrator-password dialog — there is no Settings
  /// row, no in-app dialog, no confirmation step.
  ///
  /// Skipped during onboarding: a brand-new user who hasn't finished
  /// the onboarding flow shouldn't be greeted by an unexpected
  /// password prompt — the in-app explanation hasn't even rendered yet.
  /// Once `hasSeenOnboarding` flips to true, the next launch repairs.
  ///
  /// Skipped outside an `.app` bundle (debug `flutter run`).
  ///
  /// Failure modes (user cancels password dialog, osascript missing,
  /// xattr fails): logged to EventLog and dropped. The xattr stays;
  /// the next launch will try again — entirely user-driven cadence.
  Future<void> _maybeRepairGatekeeper() async {
    try {
      if (MacOSGatekeeper.bundlePath() == null) return;
      if (!ref.read(hasSeenOnboardingProvider)) return;
      final dirty = await MacOSGatekeeper.hasQuarantine();
      if (!dirty) return;
      EventLog.writeTagged(
        'Gatekeeper',
        'auto_repair_start',
        context: {'bundle': MacOSGatekeeper.bundlePath()},
      );
      // Brief heads-up so the user understands the password dialog they're
      // about to see is initiated by YueLink (and isn't, e.g., a phishing
      // popup). One short toast — no modal, no flow interruption.
      if (mounted) {
        AppNotifier.info(S.current.gatekeeperFixRunning);
      }
      final ok = await MacOSGatekeeper.removeQuarantine();
      EventLog.writeTagged(
        'Gatekeeper',
        ok ? 'auto_repair_success' : 'auto_repair_failed_or_cancelled',
      );
      if (ok && mounted) {
        AppNotifier.success(S.current.gatekeeperFixSuccess);
      }
      // Failure path: stay silent. User-cancelled password dialogs are the
      // common case and shouldn't generate an error toast.
    } catch (e) {
      EventLog.writeTagged(
        'Gatekeeper',
        'auto_repair_exception',
        context: {'error': e},
      );
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
    final accentHex = ref.watch(accentColorProvider);

    // Parse accent color from hex string
    final accentColor = Color(int.parse('FF$accentHex', radix: 16));

    // Side-effect-only providers — heartbeat and subscription sync. They
    // exist to keep timers alive and don't emit a value the MaterialApp
    // cares about. Use ref.listen instead of ref.watch so the intent is
    // explicit: "subscribe to lifecycle, never rebuild me on emissions".
    // (Both are Provider<void>; ref.watch happened to work because null
    // == null, but ref.listen documents the contract clearly.)
    ref.listen<void>(coreHeartbeatProvider, (_, _) {});
    ref.listen<void>(subscriptionSyncProvider, (_, _) {});

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
          ref.read(onboardingPersonaProvider.notifier).set(chosen);
        },
      );
    }

    // 1b. Onboarding first — before login, on ALL platforms.
    //
    // Value-first: completing onboarding drops the user into guest mode,
    // not the login wall. They land on the Dashboard, see the app's
    // shape (mock or third-party-imported profiles work), and reach the
    // login prompt either from the Dashboard's guest banner or from
    // Settings → 前往登录. Users who explicitly logged out of an
    // existing account still see YueAuthPage (loggedOut branch below)
    // — that's a clear "I want to switch account" signal we shouldn't
    // bypass.
    if (!hasSeenOnboarding) {
      return OnboardingPage(
        onComplete: () {
          ref.read(hasSeenOnboardingProvider.notifier).set(true);
          if (ref.read(authProvider).status == AuthStatus.loggedOut) {
            ref.read(authProvider.notifier).skipLogin();
          }
        },
      );
    }

    // 2. Auth check
    final authState = ref.watch(authProvider);
    switch (authState.status) {
      case AuthStatus.unknown:
        // v1.0.22 P0-4c: render a quiet centred loader instead of
        // SizedBox.shrink(). With P0-4a's bootstrap timeout and
        // P0-4b's _init() timeout/catch, unknown is guaranteed
        // transient (max ~5 s on a wedged SecureStorage); showing
        // anything beats a blank window.
        return const AuthLoadingFallback();
      case AuthStatus.loggedOut:
        return const YueAuthPage();
      case AuthStatus.loggedIn:
      case AuthStatus.guest:
        return const MainShell();
    }
  }
}

// ── Crash logging ─────────────────────────────────────────────────────────────

// Error logging moved to ErrorLogger (lib/services/error_logger.dart).
// Call ErrorLogger.init() in main() to set up FlutterError.onError +
// PlatformDispatcher.onError + optional remote reporting (Sentry etc.).
