# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YueLink (悦通) is a cross-platform proxy client built with Flutter + mihomo (Clash.Meta) Go core.
Supports: Android, iOS, macOS, Windows. (No Linux support.)

## Build Commands

```bash
flutter pub get                                    # Install Flutter dependencies
dart setup.dart build -p <platform> [-a <arch>]    # Compile Go core (android|ios|macos|windows)
dart setup.dart install -p <platform>              # Copy libs to Flutter platform dirs
dart setup.dart clean                              # Remove build artifacts
flutter run                                        # Run (mock mode if no native lib)
flutter analyze --no-fatal-infos --no-fatal-warnings  # Analyze (CI flags)
flutter test                                       # Run all tests
flutter test test/models/                          # Run single test directory
flutter build apk|ios|macos|windows                # Release builds
```

Go >= 1.22 required for core compilation. Flutter >= 3.22, Dart >= 3.4. CI uses Flutter 3.27.4, Go 1.23.

## Architecture

```
Flutter UI (Dart, Riverpod) → CoreController (dart:ffi) → hub.go (CGO //export) → mihomo engine
                                                                                       ↕
                              MihomoApi (REST :9090) ← ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ mihomo HTTP API
                                                                                       ↕
                                                              Platform VPN service (TUN/system proxy)

XBoardApi (HTTPS) ← ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ CloudFront → XBoard panel
```

**Critical split**: FFI is for lifecycle only (init/start/stop). All data operations (proxies, traffic, connections, rules) go through the REST API (`MihomoApi`), never FFI. This matches FlClash/Clash Verge Rev architecture.

### Directory structure (dual-layer — in transition)

The codebase has two parallel layers. Both are active; `main.dart` imports from both:

- **`lib/pages/` + `lib/providers/` + `lib/services/`** — original layer, still used for Dashboard, Nodes, Settings shell pages and core Riverpod providers (core_provider, proxy_provider, profile_provider).
- **`lib/modules/` + `lib/infrastructure/` + `lib/core/` + `lib/domain/`** — newer modular layer. New features go here.

Do not move code between layers without a reason. When adding new features, use the `lib/modules/` pattern.

### Key layers

- **`core/`** — Go wrapper around mihomo. Exports C functions via `//export` (CGO). Compiled to `.so`/`.dylib`/`.dll` (dynamic) or `.a` (static, iOS only) via `setup.dart`. Android builds use `-tags with_gvisor` (required for TUN fd/file-descriptor mode — without it mihomo fails with "gVisor is not included in this build").
- **`lib/ffi/`** (old) / **`lib/core/ffi/`** (new) — Dart FFI bindings. `CoreBindings` has raw FFI (8 lifecycle symbols: InitCore, StartCore, StopCore, Shutdown, IsRunning, ValidateConfig, UpdateConfig, FreeCString). `CoreController` is the high-level wrapper; data methods (getProxies, changeProxy, testDelay, getTraffic) always delegate to `CoreMock` — they exist only for mock mode UI development.
- **`lib/providers/`** — Riverpod state management. `core_provider.dart` (lifecycle, traffic, heartbeat), `proxy_provider.dart` (nodes, groups, delay tests), `profile_provider.dart` (subscriptions), `proxy_provider_provider.dart` (remote proxy providers).
- **`lib/pages/`** — Shell pages: Dashboard, Nodes, Settings (now repurposed as 我的/Mine account center). **4-tab nav**: 首页 | 线路 | 商店 | 我的. Tab constants in `MainShell`: `tabDashboard=0`, `tabProxies=1`, `tabStore=2`, `tabSettings=3`. The Profiles/Subscriptions tab has been removed from the nav (profiles still managed internally via auth sync).
- **`lib/services/`** — `VpnService` (MethodChannel), `MihomoApi` (REST on port 9090), `MihomoStream` (WebSocket for traffic/logs), `CoreManager` (lifecycle singleton — handles VPN internally per platform), `ProfileService` (static methods for profile CRUD + config loading), `OverwriteService` (config merging), `ConfigTemplate` (config processing with ensure-pattern injection), `SettingsService` (SharedPreferences wrapper), `GeoDataService` (pre-downloads GeoIP/GeoSite files before core start), `AppNotifier` (global toast/snackbar), `AutoUpdateService`/`UpdateChecker` (app updates), `WebdavService` (backup/sync).
- **`lib/theme.dart`** — Design system: `YLColors` (zinc palette + semantic colors), `YLText` (typography), `YLSpacing`/`YLRadius`, `YLShadow` (context-aware for dark mode), reusable widgets (`YLSurface`, `YLStatusDot`, `YLChip`, `YLDelayBadge`, `YLPillSegmentedControl`, etc.).
- **`lib/l10n/app_strings.dart`** — Hand-written `S` class for i18n. Both Chinese and English via `_e ? 'en' : 'zh'` ternaries. No code generation. Use `S.of(context)` in widgets, `S.current` in providers/services without BuildContext.

### Modules layer (`lib/modules/`)

| Module | Contents |
|--------|----------|
| `yue_auth/` | Login page, `AuthNotifier` (StateNotifier), `AuthState`, `xboardApiProvider` |
| `announcements/` | `AnnouncementBanner` widget, `AnnouncementsPage`, `AnnouncementReadService`, `announcementsProvider`, `readAnnouncementIdsProvider` |
| `emby/` | `embyProvider` (FutureProvider<EmbyInfo?>) — placeholder feature |
| `mine/` | `AccountCard`, `TrafficUsageCard` (always shows XBoard `u`/`d`/`transfer_enable` — no VPN required), `AccountActionsCard` — the 我的 page widgets |
| `store/` | `StorePage`, `PlanCard`, `PlanDetailSheet`, `CurrentPlanCard`, `PurchaseNotifier` (state machine: Idle→Loading→AwaitingPayment→Polling→Success/Failed; `payExistingOrder()` skips `createOrder` for pending orders from history), `OrderHistoryPage` (pending orders show Pay Now + `PaymentMethodSelector` + Cancel) |
| `dashboard/` | `HeroCard`, `QuickActionsCard`, `AnnouncementBanner`, `SubscriptionCard` (tappable → StorePage), `ExitIpCard`, `ChartCard`, `StatsCard` |
| `nodes/` | Proxy group UI (`GroupCard` + `GroupListSection` with pill badges for type+count, `NodeTile`, sort chip) |
| `profiles/` | Profile list page + providers |
| `connections/`, `logs/`, `settings/` | Sub-pages / providers |

**Node count display**: Both `GroupCard` and `GroupListSection` use a `_Badge` widget (pill style, same as type badge) placed immediately after the type badge. Shows plain count (`23`) normally, filtered count (`3/23`) in accent color when search is active. The sort button in the nodes app bar is a chip showing the current `NodeSortMode` label — tap cycles through modes.

### Infrastructure layer (`lib/infrastructure/`)

- **`datasources/xboard_api.dart`** — XBoard panel REST client (cedar2025/Xboard). Endpoint: `https://d7ccm19ki90mg.cloudfront.net`. Methods: `login`, `getSubscribeData` (combined: profile + subscribe URL via `/api/v1/user/getSubscribe`), `fetchSubscribeConfig`, `getEmby`, `getAnnouncements`, plus Store methods (`fetchPlans`, `createOrder`, `checkoutOrder`, `fetchOrderDetail`, `cancelOrder`, `fetchOrders`, `validateCoupon`, `fetchPaymentMethods`). Models: `LoginResponse`, `UserProfile`, `SubscribeData`, `SubscribeResult`, `Announcement`, `EmbyInfo`, `XBoardApiException`. **Critical**: XBoard returns `{"status":"fail","message":"..."}` with HTTP 200 for business-level errors. `_getRawData`/`_postRawData` both call `_assertSuccess(json)` which throws `XBoardApiException` on `status:"fail"` — callers must NOT wrap in try-catch that swallows this. **XBoard tinyint(1) bool casting**: PHP encodes `tinyint(1)` columns as JSON `true`/`false` instead of `1`/`0`. Dart `as int?` throws `type 'bool' is not a subtype of type 'int?'`. All store models (`StorePlan`, `StoreOrder`, `CouponResult`, `PaymentMethod`) use `_toInt(dynamic v)` / `_toBool(dynamic v)` helpers that handle `bool`, `int`, and `double` inputs. Never use `json['field'] as int?` directly for XBoard numeric fields. **Traffic units**: `UserProfile.transferEnable`, `uploadUsed` (`u`), `downloadUsed` (`d`) are all in **bytes** — pass directly to `formatBytes()`, do not multiply or divide. `StorePlan.transferEnable` is in **GB** (different table). **Checkout**: `CheckoutResult.type == -1` = free/instant (no URL, `paymentUrl` = `''`); type 0 = QR URL; type 1 = redirect URL. `PaymentMethod.payment` is a `String` (e.g. `"alipay"`), not int. `OrderStatus.isSuccess` includes `processing` (status=1, payment received but activating) in addition to `completed` (3) and `discounted` (4).
- **`datasources/mihomo_api.dart`** — mihomo REST client (port 9090).
- **`datasources/mihomo_stream.dart`** — WebSocket for real-time traffic/logs.

### XBoard auth flow

1. User logs in via `AuthNotifier.login(email, password)` → `XBoardApi.login()` → saves `auth_data` token + api host via `AuthTokenService`. **Important**: XBoard login returns two token fields: `auth_data` (Sanctum token, already has `Bearer ` prefix — use this for API Authorization header) and `token` (raw database token, only for subscription download URLs via Client middleware). Always use `auth_data` for API calls, matching both reference clients (ClashMetaForAndroid, clash-verge-rev).
2. `AuthNotifier` fetches `UserProfile` and subscribe URL on login; caches profile in secure storage.
3. `syncSubscription()`: downloads Clash YAML from subscribe URL → `ProfileService.addProfile/updateProfile()` with name `'悦通'`. Auto-selects the profile on first create.
4. On app start, `AuthNotifier._init()` restores token from secure storage and shows cached profile while refreshing in background. Token expired (401/403) triggers auto-logout.
5. `AuthTokenService` (`lib/core/storage/auth_token_service.dart`) is the single source of truth for: token, subscribe URL, cached UserProfile JSON, api host.

### TLS / HTTP client requirement

**Always use `XBoardApi._buildClient()`** (returns `IOClient(HttpClient())`) for all HTTP calls to the CloudFront endpoint. The plain `http.Client` from the `http` package does not reliably send TLS SNI on all platforms; CloudFront rejects connections without SNI with `HandshakeException: Connection terminated during handshake`. Every `_get`/`_post` call creates a fresh client and closes it in `finally`.

**dart:io `HttpClient` cascade + arrow function bug**: Do NOT use cascade (`..`) to set `findProxy` and other properties on the same `HttpClient` in a single chain when any assigned value is an arrow function. Dart's parser misattributes the type after `..findProxy = (_) => '...'`, causing downstream cascade setters to fail with "setter not defined for class String". Always set `HttpClient` properties as separate statements:
```dart
// WRONG — Dart parse bug
final client = HttpClient()..findProxy = (_) => 'PROXY ...'..connectionTimeout = ...;
// CORRECT
final client = HttpClient();
client.findProxy = (uri) => 'PROXY 127.0.0.1:$port';
client.connectionTimeout = const Duration(seconds: 10);
```

### Announcements read state

`AnnouncementReadService` persists read announcement IDs as a JSON array in `read_announcement_ids.json` (via `path_provider` app documents directory). Do not use SharedPreferences or SecureStorage for this — it is non-sensitive and needs to survive app reinstalls on the same device without re-prompting.

### Platform VPN implementations

| Platform | Mechanism | Location |
|----------|-----------|----------|
| Android | `VpnService` + TUN fd → Go core (always, regardless of connectionMode) | `android/.../YueLinkVpnService.kt` |
| iOS | `NEPacketTunnelProvider` (separate process, static lib) | `ios/PacketTunnel/` |
| iOS (TrollStore) | Same as above; minimum iOS 15.0 for PacketTunnel extension | — |
| macOS | System proxy via `networksetup` (sets ALL interfaces; `_verifySystemProxy` checks all and logs which are active vs missing) | `lib/providers/core_provider.dart` |
| Windows | System proxy via registry | `lib/providers/core_provider.dart` |

### Native library install paths

`setup.dart install` copies built libraries to these locations (all gitignored):

| Platform | Destination |
|----------|-------------|
| Android | `android/app/src/main/jniLibs/<abi>/libclash.so` |
| iOS | `ios/Frameworks/libclash.a` + `.h` |
| macOS | `macos/Frameworks/libclash.dylib` (universal via `lipo`) |
| Windows | `windows/libs/<arch>/libclash.dll` |

### Critical conventions

- **Default connection mode is `systemProxy`** (not TUN). Mobile (Android/iOS) always uses VPN regardless of this setting; the setting only applies to desktop.
- iOS: Go core must be `c-archive` (static library), not `c-shared`. Extension runs in separate process with ~15MB memory limit.
- Go core state is protected by a single mutex (`state.go`) — all exported functions must acquire the lock.
- **All Go exports that can fail return `*C.char`**: empty string = success, non-empty = error. **NULL pointer (address == 0) also means success** — Go can return NULL on some code paths (e.g., when panic is recovered). Dart `_callStringFn` in `CoreController` handles all three cases. Caller must free non-null results via `FreeCString`.
- **Never use `Isolate.run()` for FFI calls**. Spawning a new isolate to call CGO functions causes hangs on Android/macOS (new isolate re-opens `DynamicLibrary`, interacts badly with Go runtime). FFI calls (`InitCore` ~1s, `StartCore` ~2s) are made synchronously on the main isolate — well within ANR limits. Same rule applies to pure Dart config processing (`OverwriteService.apply`, `ConfigTemplate.process`) — these are <10ms and don't need isolate isolation.
- `CoreManager` handles VPN internally for each platform — `CoreActions` must NOT call `VpnService` directly.
- Android VPN permission is always requested (no connectionMode guard) because Android always needs VpnService.
- **Android notification permission**: `POST_NOTIFICATIONS` is requested at runtime in `MainActivity.onStart()` on Android 13+ (API 33+). Without it the foreground VPN notification is silently suppressed, and the service may be killed. The permission is declared in `AndroidManifest.xml` and requested via `checkSelfPermission`/`requestPermissions` (no AndroidX dependency needed).
- **Android Secure Folder (Samsung)**: Apps installed inside Samsung Secure Folder run as user 95 (not user 0). `VpnService.establish()` always returns null for non-primary users — TUN fd will be -1 and VPN will never work. Only one VPN can be active system-wide; a Secure Folder instance running its VPN blocks the main-space instance. Verify with `adb shell dumpsys package com.yueto.yuelink | grep dataDir` — must show `/data/user/0/`.
- **Android TUN config**: `ConfigTemplate._injectTunFd()` replaces the entire `tun:` section with Android-safe settings: `stack: gvisor`, `auto-route: false`, `auto-detect-interface: false` (netlink banned on Android 14+), `find-process-mode: off`. Never set `auto-route: true` when using VpnService fd.
- **iOS TUN config**: `PacketTunnelProvider.injectTunConfig()` uses `stack: gvisor`. Also forces `find-process-mode: off`, injects full DNS fallback config when no dns section exists, and calls `ensureDnsPatched()` when a dns section is present (ensures `enable: true` + `nameserver-policy` for Apple/iCloud — mirrors Dart `_ensureDns` behavior).
- Connection mode UI is hidden on mobile — only shown on desktop (`isDesktop = Platform.isMacOS || Platform.isWindows`).
- MethodChannel name: `com.yueto.yuelink/vpn` (consistent across all platforms).
- Package/Bundle ID: `com.yueto.yuelink`
- App Group (iOS): `group.com.yueto.yuelink`
- User-Agent for subscription downloads: `clash.meta` (required for airport compatibility).
- `ProfileService` uses static methods, not a Riverpod provider. Call `ProfileService.loadConfig(id)` directly.
- `YLColors.primary` is black (`#000000`) — never use it as foreground in dark mode. Use `isDark ? Colors.white : YLColors.primary` pattern.
- Android native strings (VPN notification etc.) use Android string resources with `values-zh/` locale variant, not the Dart `S` class.
- **Sidebar uses instant state switching** (no AnimatedContainer). This is intentional to avoid flicker on Windows. Do not add animation back.
- **App lifecycle**: `_YueLinkAppState` implements `WidgetsBindingObserver`. On `AppLifecycleState.resumed`, `_onAppResumed()` immediately checks `CoreManager.isRunning` + `api.isAvailable()` and resets state if core died in the background — do NOT wait for the 10s heartbeat. Register/unregister via `WidgetsBinding.instance.addObserver/removeObserver` in `initState`/`dispose`.
- **Heartbeat scope**: `coreHeartbeatProvider` is `ref.watch`-ed in `_YueLinkAppState.build()` (root widget), not just the Dashboard page. This keeps the 10s crash-detection timer active regardless of which tab is visible. The provider itself guards: `if (status != CoreStatus.running) return` — no timer when stopped.
- **Auth gate startup flash**: `_AuthGate` returns `const Scaffold()` (blank) during `AuthStatus.unknown`. Do NOT show `CircularProgressIndicator` there — auth resolves in ~100ms from cached storage and the spinner causes a visible white flash before content loads.
- **Port conflict handling (desktop)**: Before `ConfigTemplate.process()`, `CoreManager` calls `_findAvailablePort(preferred)` for both `mixedPort` and `apiPort`. If the preferred port is busy (other proxy software running), the next free port in range `[preferred, preferred+20)` is used. For `mixedPort`, the config string is patched via `ConfigTemplate.setMixedPort()` before processing. Mobile platforms skip this — VPN replacement is handled at OS level.
- **Stream subscription lifecycle**: `_appLinks.uriLinkStream.listen()` result must be stored as `_appLinksSub` and cancelled in `dispose()`. `ref.listenManual()` returns a `ProviderSubscription` that must be `.close()`d in `dispose()` — not `.cancel()`. `ref.listen()` in `build()` is managed automatically by Riverpod.
- **iOS TrollStore distribution**: `ios/PacketTunnel/Info.plist` **must** have `CFBundleExecutable = $(EXECUTABLE_NAME)`. Without it, ldid fails with "Cannot find key CFBundleExecutable" (exit code 1, TrollStore error 175) during recursive bundle signing. `CFBundleDisplayName` should be `悦通`. The entitlements (`application-groups` + `networkextension: packet-tunnel-provider`) are compatible with TrollStore — do NOT add push notifications, iCloud, or `keychain-access-groups`.
- **macOS secure storage**: `SecureStorageService` uses a JSON file in Application Support directory (`path_provider`) on macOS, NOT `flutter_secure_storage`. The Keychain (both legacy and Data Protection) requires signing entitlements that block `flutter run` without a paid developer account. The JSON-file approach is the standard for non-App-Store macOS apps (used by FlClash etc.). Do NOT switch macOS back to `flutter_secure_storage` or add `keychain-access-groups` to entitlements.

### FFI symbol alignment

Dart bindings (`core_bindings.dart`) must exactly match Go exports (`core/hub.go`). Current 8 Dart bindings match 8 of 9 Go exports (`GetVersion` is intentionally unbound — version comes via REST API). **Never add FFI bindings for data operations** — those belong in `MihomoApi`. All failable exports return `Pointer<Utf8>` (C string), not `int`.

### Mock mode

When Go core is unavailable (no native library), `CoreController` automatically falls back to `CoreMock`, which simulates proxy groups, nodes, traffic, and connections. UI development works fully without Go — just `flutter run`.

### Config processing pipeline (`ConfigTemplate.process()`)

Uses "ensure" pattern: only injects when missing, never overwrites subscription-provided settings.

1. Replace template variables (`$app_name` → `YueLink`)
2. `_ensureMixedPort` — without it mihomo silently skips HTTP+SOCKS listener
3. `_ensureExternalController` — REST API endpoint for data operations (always replaces existing value with `127.0.0.1:port`)
4. `_ensureDns` — two-path logic: (a) **no dns section**: inject full default including expanded `fake-ip-filter` and domestic DoH nameservers; (b) **existing dns section**: ensure `enable: true`, then detect actual indentation from existing keys (`RegExp(r'\n( +)\S').firstMatch(dnsSection)`) and inject `nameserver-policy` + `direct-nameserver` for Apple/iCloud using the detected indent — prevents "dial tcp 0.0.0.0:443" when subscription routes Apple domains DIRECT and UDP DNS returns 0.0.0.0.
5. `_ensureSniffer` — HTTP/TLS/QUIC domain detection for DOMAIN-type rules
6. `_ensureGeodata` — geodata-mode + geo URLs + auto-update for GEOIP/GEOSITE rules
7. `_ensureProfile` — store-selected + store-fake-ip persistence
8. `_ensurePerformance` — tcp-concurrent, unified-delay, TLS fingerprint
9. `_ensureAllowLan` — allow-lan + bind-address for mixed-port
10. `_ensureFindProcessMode` — `always` on desktop, `off` on mobile (no permission)
11. `_injectTunFd` — Android TUN fd injection (only when tunFd provided)

**YAML injection safety rule**: Never inject into an existing YAML block with hardcoded indentation. Always detect the actual indent from existing sibling keys first (see `_ensureDns` indent detection pattern). String injection at section boundaries only works safely for top-level keys (0 indent) appended at EOF. `ConfigTemplate.setMixedPort()` is the only method that replaces an existing top-level scalar — it uses a regex on the `mixed-port: N` line.

iOS PacketTunnelProvider has its own `injectTunConfig()` in Swift with equivalent logic (runs in separate process, can't use Dart ConfigTemplate).

### Core startup sequence & diagnostics

`CoreManager.start()` runs 8 observable steps, each recorded in `StartupReport` (`lib/models/startup_report.dart`) with name, success, errorCode, error, detail, and durationMs:

| Step | errorCode | What it does |
|------|-----------|--------------|
| `ensureGeo` | E009 | Copy GeoIP/GeoSite assets to homeDir (CDN fallback if missing) |
| `initCore` | E002 | Call `InitCore(homeDir)` via FFI, set up Go logrus → `core.log` |
| `vpnPermission` | E003 | Android only: request VpnService permission |
| `startVpn` | E004 | Android only: get TUN fd from `VpnService` |
| `buildConfig` | E005 | Port conflict check (desktop: scan for free ports) + `OverwriteService.apply()` + `ConfigTemplate.process()` (sync, no Isolate) |
| `startCore` | E006 | Call `StartCore(configYaml)` via FFI (hub.Parse + listeners) |
| `waitApi` | E007 | Poll REST API up to 50× × 100ms = 5s |
| `verify` | E008 | Check `IsRunning` + API available + DNS diagnostic |

On failure, `StartupReport.failureSummary` returns `"[Exx_CODE] stepName: error"` — shown in `_StartupErrorBanner` on dashboard (expandable: shows all steps + last 20 lines of Go `core.log`). Report saved to `startup_report.json`. Go side logs tagged `[BOOT]`/`[CORE]` via logrus redirected to `core.log`; Dart reads this after startup in `_finishReport()`.

### Dashboard data sources

- **出口IP** (`exitIpInfoProvider`, aliased as `proxyServerIpProvider`, in `lib/modules/dashboard/providers/dashboard_providers.dart`): Resolves the selected proxy node's exit IP via mihomo REST API — does NOT route through the mixed port. Flow: (1) `GET /proxies` → find first real user group from `GLOBAL.all` order; (2) follow `.now` chain recursively to a leaf proxy with a `server` field; (3) DNS-resolve the hostname via `InternetAddress.lookup`; (4) call `api.ip.sb/geoip/{ip}` **directly** (no proxy) for country/city/ISP. Returns `ExitIpInfo` with `flagEmoji` (Unicode Regional Indicators) and `locationLine`. Tap on `ExitIpCard` → `ref.invalidate(exitIpInfoProvider)`.
- **Traffic chart** (`ChartCard`): Driven by a **single** WebSocket to mihomo `/traffic`. `trafficStreamProvider` maintains one `trafficSub` that writes both `trafficProvider` (current speed) and a local `TrafficHistory` ring buffer (1800 entries, 1 Hz). Two separate WebSocket connections to the same endpoint are unreliable — mihomo silently drops the second, leaving the chart blank. `trafficHistoryProvider` is reset to an empty `TrafficHistory()` on both manual stop and heartbeat-detected crash.
- **StatsCard upload/download**: Shows XBoard `userProfileProvider.uploadUsed` / `downloadUsed` (`u`/`d` fields), NOT locally accumulated traffic. `TrafficUsageCard` on Mine page also shows these fields broken out individually — they are always available from the cached profile regardless of VPN state.
- **ChartCard speed**: Watches `trafficProvider` (1Hz WebSocket ticks) and displays real-time `↓ x.xx MB/s / ↑ x.xx MB/s` in the header alongside the historical curve.
- **Language detection** in `yue_auth_page.dart`: Use `Localizations.localeOf(context).languageCode == 'en'`, NOT string comparisons like `s.navHome == 'Dashboard'`.

### Proxy group ordering

Groups are ordered by the `GLOBAL` group's `all` field from the mihomo API (`/proxies`), not alphabetically. See `proxy_provider.dart` `ProxyGroupsNotifier.refresh()`.

## Git & CI

- **Branches**: `master` (main/release), `dev` (development). CI triggers on push to `main` and `dev`, and on tags.
- **Tag strategy**: `alpha.N` tags trigger full builds (APK/IPA/DMG/EXE as artifacts, no GitHub Release) for testing. `v*` tags additionally create a GitHub Release. Use `alpha.*` during development, `v1.0.0` etc. for production releases.
- **Release flow**: commit to `dev` → `git tag alpha.N && git push origin alpha.N` (test build) or `git tag vX.Y.Z && git push origin vX.Y.Z` (release). Never tag before pushing the commit.
- **CI pipeline** (`.github/workflows/build.yml`): analyze+test → build Go cores (per-platform matrix) → Flutter builds (download core artifacts → install → build) → release (on `v*` tags only).
- **Release artifacts**: `YueLink-Windows-Setup.exe` (Inno Setup), `YueLink-macOS.dmg` (create-dmg, universal binary), `YueLink-Android.apk` (fat universal), `YueLink-iOS.ipa` (no-codesign).
- **Analyze in CI** uses `--no-fatal-infos --no-fatal-warnings` — only errors fail the build.
- Submodules: `core/mihomo` is a git submodule. Clone with `--recursive` or run `git submodule update --init --recursive`.
- **mihomo patches** (`core/patches/`): Applied during CI build. `0001-non-fatal-buildAndroidRules.patch` (PackageManager errors non-fatal), `0002-non-fatal-mmdb-and-iptables.patch` (MMDB/ASN `log.Fatalln` → `log.Errorln`, removes `os.Exit(2)` from iptables handler). These prevent the Go core from killing the entire Flutter process on non-critical failures.

## Testing

```bash
flutter test                          # Run all tests
flutter test test/models/             # Model tests (profile, proxy, traffic, rule, connection)
flutter test test/services/           # Service tests (config_template, mihomo_api, mihomo_stream, subscription_parser)
flutter test test/ffi/                # FFI/mock tests
flutter test test/providers/          # Provider tests
```
