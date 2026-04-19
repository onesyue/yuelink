# CLAUDE.md

Guidance for Claude Code working in this repo. Keep this file lean — only record gotchas and conventions that aren't derivable from reading the code.

## Project

YueLink (悦通) — Flutter UI + mihomo (Clash.Meta) Go core. Targets: Android, iOS, macOS, Windows, Linux. Package/Bundle ID: `com.yueto.yuelink`. iOS App Group: `group.com.yueto.yuelink`.

## Build

```bash
flutter pub get
dart setup.dart build -p <android|ios|macos|windows> [-a <arch>]
dart setup.dart install -p <platform>          # copies libs into platform dirs (gitignored)
dart setup.dart clean
flutter run                                    # mock mode if no native lib
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk|ios|macos|windows
```

Requires Go ≥ 1.22, Flutter ≥ 3.38.4, Dart ≥ 3.10.3. CI uses Flutter 3.41.5 / Go 1.23. Xcode ≥ 15. Android NDK r26+.

**macOS universal**: build `arm64` and `x86_64` separately, then `install` merges via `lipo`.

**Android signed release**:
```bash
KEYSTORE_PATH="$(pwd)/android/app/yuelink.jks" KEYSTORE_PASSWORD=yuelink2024 \
KEY_ALIAS=yuelink KEY_PASSWORD=yuelink2024 \
flutter build apk --release --split-per-abi
```

Native libs install to: `android/app/src/main/jniLibs/<abi>/libclash.so`, `ios/Frameworks/libclash.a(+.h)`, `macos/Frameworks/libclash.dylib`, `windows/libs/<arch>/libclash.dll`.

## Architecture overview

```
Flutter (Dart, Riverpod) → CoreController (FFI) → hub.go (CGO) → mihomo
                         → MihomoApi (REST :9090) ← ─ ─ ─ ─ ─ ─ ─ ─┘
                                                                    ↕
                                                   Platform VPN (TUN / system proxy)
XBoardApi (HTTPS) → CloudFront → XBoard panel
```

Unified `ClashCore` interface (`lib/core/clash_core.dart`): `RealClashCore` dispatches lifecycle to FFI and data to REST; `MockClashCore` routes to `CoreMock`. Callers always go through `CoreManager.instance.core.X()`. Streaming (traffic / connections / logs websockets) lives in dedicated repositories — real-mode only; mocks are timer-based polls.

`lib/` is flat — no legacy `pages/` `services/` `providers/` `ffi/` `l10n/`. Top-level: `core/`, `domain/`, `infrastructure/`, `modules/`, `shared/`, `i18n/`, `theme.dart`, `constants.dart`, `main.dart`. New features go in `lib/modules/<feature>/`.

`core/managers/` — one file per external system: `core_lifecycle_manager`, `core_heartbeat_manager`, `system_proxy_manager`. `core/kernel/` holds `core_manager.dart` (8-step startup), `config_template.dart`, `geodata_service.dart`, `overwrite_service.dart`, `process_manager.dart`, `recovery_manager.dart`. `core/providers/core_provider.dart` is thin Riverpod wiring (~160 lines).

`infrastructure/datasources/xboard/` is a 5-file module (`client`, `errors`, `models`, `api`, `index` barrel). Always import via `index.dart`.

`appVersionProvider` reads version from `pubspec.yaml` at runtime — no hardcoded version. CI passes `--build-name` with `-pre` suffix for pre-releases.

## Platform VPN

| Platform | Mechanism |
|----------|-----------|
| Android | `VpnService` + TUN fd (always, regardless of connectionMode) — `android/.../YueLinkVpnService.kt` |
| iOS / TrollStore | `NEPacketTunnelProvider` separate process; AppDelegate handles `startVpn`/`stopVpn`/`resetVpnProfile`/`clearAppGroupConfig`; 20s timeout; `backgroundVpnObserver` sends `vpnRevoked`. Min iOS 15. |
| macOS | `networksetup` on ALL interfaces (`_verifySystemProxy` checks each) |
| Windows | Registry |

MethodChannel name: `com.yueto.yuelink/vpn`.

## Critical conventions (gotchas — not derivable from code)

### Core / FFI
- **Default connection mode is `systemProxy`** (not TUN). Mobile always uses VPN regardless; setting only applies to desktop.
- iOS Go core must be `c-archive`, not `c-shared`. Extension has ~15MB memory limit.
- All Go state behind a single mutex (`state.go`).
- **All Go exports return `*C.char`**: empty = success, non-empty = error, NULL pointer = success (Go can return NULL after panic recovery). `CoreController._callStringFn` handles all three.
- **Never use `Isolate.run()` for FFI**. Re-opening `DynamicLibrary` in a new isolate hangs on Android/macOS. `InitCore` (~1s) and `StartCore` (~2s) run synchronously on main isolate. Same for pure Dart config processing — <10ms, no isolate needed.
- `CoreManager` handles VPN per-platform — `CoreActions` must NOT call `VpnService` directly.
- FFI bindings (`core_bindings.dart`) cover lifecycle + MITM control only. Data goes through `MihomoApi`. All failable exports return `Pointer<Utf8>`.

### Android
- VPN permission always requested (no connectionMode guard).
- `POST_NOTIFICATIONS` requested at runtime in `MainActivity.onStart()` for API 33+. Without it the foreground notification is suppressed and the service may be killed.
- **Samsung Secure Folder** apps run as user 95; `VpnService.establish()` always returns null for non-primary users (TUN fd = -1). Only one VPN can be active system-wide. Verify with `adb shell dumpsys package com.yueto.yuelink | grep dataDir` — must show `/data/user/0/`.
- **TUN config** (`ConfigTemplate._injectTunFd`): `stack: gvisor`, `auto-route: false`, `auto-detect-interface: false` (netlink banned on 14+), `find-process-mode: off`. Never set `auto-route: true` with VpnService fd.
- Build with `-tags with_gvisor` (required for fd mode).
- APK install via MethodChannel `installApk` uses `FileProvider` (`${applicationId}.fileprovider`, `cache-path`). Needs `REQUEST_INSTALL_PACKAGES`.

### iOS
- **TUN config** (`PacketTunnelProvider.injectTunConfig`): `stack: gvisor`, `find-process-mode: off`, keep-alive-interval. **DNS is handled entirely by Dart `ConfigTemplate._ensureDns()`** — do NOT add DNS injection in Swift.
- **App Group geo sync** (`AppDelegate.writeConfigToAppGroup`, called on every `startVpn`): writes `config.yaml` AND copies `GeoIP.dat`/`GeoSite.dat`/`country.mmdb`/`ASN.mmdb` from main app's Application Support to `AppGroup/mihomo/`. Without this, GEOIP/GEOSITE rules fail silently in the extension. Skipped when destination is up-to-date.
- **TrollStore**: `ios/PacketTunnel/Info.plist` MUST have `CFBundleExecutable = $(EXECUTABLE_NAME)` — without it ldid fails (TrollStore error 175). Entitlements: `application-groups` + `networkextension: packet-tunnel-provider`. Do NOT add push, iCloud, or `keychain-access-groups`.

### Privilege boundary probing (cross-platform principle)
- **The OS saying a helper is "running" is not the same as the helper answering.** Always probe the endpoint you're about to call, never the administrative registration. Each platform has its own version of this race — SCM `RUNNING` vs socket `bind()`, `launchctl bootstrap` vs Unix socket listen, `systemctl active` vs `bind()`, `VpnService.prepare()` `RESULT_OK` vs `establish()`, `saveToPreferences` vs `configurationStale` — they all fix the same way.
- Canonical pattern: `ServiceManager.isInstalled()` = administrative check (cheap, fast); `ServiceManager.isReady()` = installed + ping. Any code path about to use the helper (IPC, start, status) uses `isReady()`. `isInstalled()` is only for UI "should we show the install button?" decisions.
- Startup steps must include an explicit `waitService` probe before `startService` (see `_startDesktopServiceMode`) — install-time `_waitUntilReachable` isn't enough because service can die between install and first use.
- Retries: first-attempt failure after a permission grant / install is almost always a settle race. Retry once after a 1.5 s grace before surfacing the error. Applied in `startAndroidVpn`, iOS `configurationStale` retry, `ServiceClient.start`.

### Desktop
- Connection mode UI hidden on mobile (`isDesktop = Platform.isMacOS || Platform.isWindows`).
- **Port conflict**: Before `ConfigTemplate.process()`, `CoreManager` calls `_findAvailablePort(preferred)` for both `mixedPort` and `apiPort`, scanning `[preferred, preferred+20)`. `mixedPort` is patched into the config string via `ConfigTemplate.setMixedPort()`. Mobile skips this (handled at OS level).
- **macOS secure storage**: `SecureStorageService` writes JSON in Application Support — NOT `flutter_secure_storage`. The Keychain needs signing entitlements that block `flutter run` without a paid account. Do NOT switch back or add `keychain-access-groups`.
- **Sidebar uses instant state switching** (no AnimatedContainer) — intentional, avoids Windows flicker.
- Settings providers: `closeBehaviorProvider` ('tray'|'exit', default 'tray'), `toggleHotkeyProvider` (lowercase "ctrl+alt+c", parsed via `parseStoredHotkey()`).

### XBoard auth & API
- Login returns two tokens: **`auth_data`** (Sanctum, has `Bearer ` prefix — use for API Authorization) and `token` (raw, only for subscription URLs via Client middleware). Always use `auth_data` for API.
- `AuthTokenService` is the single source of truth for token, subscribe URL, cached UserProfile JSON, api host.
- `AuthNotifier._init()` shows cached profile while refreshing in background. 401/403 triggers auto-logout.
- `syncSubscription()` downloads YAML → `ProfileService.addProfile/updateProfile()` named `'悦通'`. Auto-selects on first create.
- **XBoard returns `{"status":"fail","message":"..."}` with HTTP 200 for business errors.** `_assertSuccess(json)` throws `XBoardApiException` — callers must NOT swallow this.
- **XBoard `tinyint(1)` bool casting**: PHP encodes as JSON `true`/`false`, not `1`/`0`. `as int?` throws. All store models use `_toInt`/`_toBool` helpers. Never `json['field'] as int?` for XBoard numeric fields.
- **Traffic units**: `UserProfile.transferEnable`/`uploadUsed`(`u`)/`downloadUsed`(`d`) are **bytes** — pass directly to `formatBytes()`. `StorePlan.transferEnable` is **GB** (different table).
- **Checkout**: `CheckoutResult.type == -1` = free/instant (no URL); 0 = QR URL; 1 = redirect. `PaymentMethod.payment` is a String (`"alipay"`), not int. `OrderStatus.isSuccess` includes `processing`(1), `completed`(3), `discounted`(4).
- **CloudFront fallback**: primary `https://yuetong.app`, fallback `https://d7ccm19ki90mg.cloudfront.net`. All `XBoardApi` instantiations in `yue_auth_providers.dart` MUST pass `fallbackUrl: _kDirectOriginUrl`. Auto-retries on 502/503.

### TLS / HTTP
- Always use `XBoardApi._buildClient()` (returns `IOClient(HttpClient())`) for CloudFront calls. Plain `http.Client` doesn't reliably send TLS SNI on all platforms; CloudFront rejects with `HandshakeException`. Each `_get`/`_post` creates a fresh client and closes in `finally`.
- **Dart `HttpClient` cascade + arrow function parser bug**: do NOT chain `..findProxy = (_) => '...'` with other cascade setters — Dart misattributes the type. Always set as separate statements:
  ```dart
  final client = HttpClient();
  client.findProxy = (uri) => 'PROXY 127.0.0.1:$port';
  client.connectionTimeout = const Duration(seconds: 10);
  ```

### Config processing (`ConfigTemplate.process()`)
"Ensure" pattern — only injects when missing, never overwrites subscription settings.
1. Template variables (`$app_name` → `YueLink`)
2. `_ensureMixedPort` — without it mihomo silently skips HTTP+SOCKS listener
3. `_ensureExternalController` — always replaces with `127.0.0.1:port`
4. `_ensureDns` — two paths: (a) no dns section: inject full default with expanded `fake-ip-filter` + domestic DoH; (b) existing: ensure `enable: true`, **detect actual indent from existing keys** (`RegExp(r'\n( +)\S').firstMatch(dnsSection)`), inject `nameserver-policy` + `direct-nameserver` for Apple/iCloud — prevents "dial tcp 0.0.0.0:443" when subscription routes Apple DIRECT
5. `_ensureSniffer` — HTTP/TLS/QUIC for DOMAIN rules
6. `_ensureGeodata` — geodata-mode + geo URLs + auto-update
7. `_ensureProfile` — store-selected + store-fake-ip
8. `_ensurePerformance` — tcp-concurrent, unified-delay, TLS fingerprint
9. `_ensureAllowLan`
10. `_ensureFindProcessMode` — `always` desktop, `off` mobile
11. `_injectTunFd` — Android only

**YAML injection rule**: never inject with hardcoded indentation. Always detect indent from sibling keys first. String injection at section boundaries only safe for top-level keys appended at EOF. `setMixedPort()` uses regex on the `mixed-port: N` line.

### Startup & diagnostics
`CoreManager.start()` runs 8 steps recorded in `StartupReport` with errorCode (E002–E009). On failure, dashboard `_StartupErrorBanner` shows `[Exx] step: error` (expandable: all steps + last 20 lines of `core.log`). Saved to `startup_report.json`. Go logs tagged `[BOOT]`/`[CORE]` via logrus → `core.log`.

Steps: `ensureGeo`(E009) → `initCore`(E002) → `vpnPermission`(E003, Android) → `startVpn`(E004, Android) → `buildConfig`(E005, port check + overwrite + template) → `startCore`(E006) → `waitApi`(E007, progressive 50→100→200ms × 100, ~14s cap) → `verify`(E008).

### Lifecycle / heartbeat
- `_YueLinkAppState` implements `WidgetsBindingObserver`. On `resumed`, `_onAppResumed()` immediately checks `CoreManager.isRunning` + `api.isAvailable()` — do NOT wait for the 10s heartbeat.
- `coreHeartbeatProvider` is `ref.watch`-ed in `_YueLinkAppState.build()` (root), not just Dashboard. Provider self-guards: `if (status != running) return`.
- **Auth gate**: `_AuthGate` returns `const Scaffold()` (blank) during `AuthStatus.unknown`. Do NOT show `CircularProgressIndicator` — auth resolves in ~100ms, spinner causes white flash.
- **Listener placement**: use `ref.listenManual()` in `initState` (via `Future.microtask`) for one-time listeners, not `ref.listen()` in `build` which re-registers every frame. Store `ProviderSubscription`, `.close()` in `dispose`.
- `_appLinks.uriLinkStream.listen()` → store as `_appLinksSub`, cancel in `dispose`.

### Streams / WebSocket
- **Single-WebSocket rule for `/traffic`**: `trafficStreamProvider` keeps ONE `trafficSub` writing both `trafficProvider` and a local `TrafficHistory` ring buffer (1800 entries, 1Hz). Two connections to the same endpoint → mihomo drops the second silently, chart goes blank. History reset on stop and crash.
- **TrafficHistory perf**: version-based change detection. Mutated in-place with `version++`. `ChartCard` watches `trafficHistoryVersionProvider` (cheap int) and reads history by reference. Never `.copy()` per tick.
- `MihomoStream` uses exponential backoff (2→4→8→16→30s cap), resets on success. Never fixed-interval retry.
- `MihomoStream` passes secret via `Authorization: Bearer` header (not URL query) via `IOWebSocketChannel.connect(uri, headers:)`.
- `StreamController` with `onCancel`: always call `controller.close()` in `onCancel` in addition to cancelling upstream subs.

### File I/O
- Always `dir.create(recursive: true)` before writing — Application Support may not exist on first run. `SettingsService`, `SecureStorageService`, `AnnouncementReadService` all follow this.
- **Announcements**: `AnnouncementReadService` persists read IDs as JSON in `read_announcement_ids.json` (path_provider docs dir). NOT SharedPreferences/SecureStorage — needs to survive reinstalls.

### UI / theme
- `YLColors.primary` is black `#000000`. Never use as foreground in dark mode. Pattern: `isDark ? Colors.white : YLColors.primary`.
- `YLShadow` is context-aware for dark mode.
- Android native strings (VPN notification etc.) use Android string resources with `values-zh/`, NOT Dart `S` class.
- **Language detection** in `yue_auth_page.dart`: use `Localizations.localeOf(context).languageCode == 'en'`, NOT string compares like `s.navHome == 'Dashboard'`.
- **Node count**: Both `GroupCard` and `GroupListSection` use `_Badge` (pill, same as type badge) right after type badge. Plain `23` normally, `3/23` accent when filtered.

### Dashboard data
- **出口IP** (`exitIpInfoProvider`): routes HTTPS through mihomo's mixed-port to `api.ip.sb/geoip`. Direct mode skips proxy. This works for proxy-provider nodes (the old proxy-chain-resolution approach failed because providers don't expose `server`). Returns `ExitIpInfo` with `flagEmoji` + `locationLine`. Tap → `ref.invalidate`. Uses separate `HttpClient` statements (cascade bug).
- **StatsCard upload/download** = XBoard `userProfileProvider.uploadUsed`/`downloadUsed`, NOT locally accumulated. `TrafficUsageCard` (Mine) shows the same — always available regardless of VPN state.
- **ChartCard speed** = `trafficProvider` (1Hz) → `↓ x.xx MB/s / ↑ x.xx MB/s` in header.
- **Proxy group ordering**: by GLOBAL group's `all` field from `/proxies`, NOT alphabetical. See `ProxyGroupsNotifier.refresh()`.

### Profiles / subscriptions
- `ProfileService` uses static methods, NOT a Riverpod provider. Call `ProfileService.loadConfig(id)` directly.
- User-Agent for subscription downloads: `clash.meta` (required for airport compatibility).

### Emby module
Fully data-driven from server — no hardcoded library names/order. Reads `/emby/Users/{uid}/Views`. Empty libraries auto-hide. **HiDPI**: `EmbyImage` multiplies width by `devicePixelRatio` (1–3x); backdrops use 1920px direct. **Responsive posters**: 180/240/280 (mobile/tablet/desktop). Hero Banner picks first item with backdrop from `isMediaLibrary` (movies||tvshows only — boxsets excluded). LRU preview cache, max 5 libraries.

**STRM library support**: `_Library.includeItemTypes` returns `Movie,Video` (movies), `Series,Video` (tvshows), `MusicAlbum`, `BoxSet`. The `Video` type is required for STRM-based 搬运 servers — Emby indexes incomplete metadata files as generic `Video`. Without it, count = 0.

**Boxsets** (Emby 4.9 `CollectionType: "boxsets"`): `_Library.isCollectionLibrary` true. Sort by `SortName` asc; others by `DateCreated` desc. Detail page uses `BoxSet`-only query.

### Checkin (`yue.yuebao.website`)
- Standalone API, separate from XBoard. Server: Python FastAPI on `23.80.91.14:8011`, nginx-proxied.
- App check-in uses `v2_user.app_sign` — independent from Telegram Bot check-in (`user_account.sign`). One per day per system; rewards stack.
- **Server auth**: calls XBoard `/api/v1/user/info` **directly at `http://66.55.76.208:8001`**, NOT via CloudFront. CloudFront→origin is unreliable + nginx blocks non-CF traffic by UA + python-urllib UA is rejected. XBoard does NOT return `id` — server resolves user by `email` from DB.
- Midnight reset: APScheduler `Asia/Shanghai` clears `app_sign` for all users.
- `_isAlreadyCheckedError` must only match genuine "already checked" — never match auth/server errors. `_assertSuccess` must reject all non-2xx (don't treat 502 as success).
- Deploy: `scp main.py root@23.80.91.14:/opt/checkin-api/main.py && ssh root@23.80.91.14 systemctl restart checkin-api`.

### Environment
- `EnvConfig.isStandalone` (default `true`) gates self-update. Build for store: `flutter build ios --dart-define=STANDALONE=false`.
- `UpdateChecker` only runs when standalone. Skip-version persists via `SettingsService`.
- `SubscriptionSyncService` 30min background timer for stale profiles. Activated via `ref.watch(subscriptionSyncProvider)` in root.
- `ErrorLogger.init()` in `main()` — writes `crash.log` + `EventLog` + `RemoteReporter`.
- `LogExportService` collects core.log + crash.log + event.log + startup_report.json with PII redaction (11 regex patterns).
- **Telemetry** (`lib/shared/telemetry.dart`): opt-in (default OFF), anonymous UUID `client_id` persisted in SettingsService. Event names are constants in `TelemetryEvents` — never pass raw strings. Errors/startup_fail use `priority: true` to survive buffer overflow. Settings → `TelemetryPreviewPage` shows the last 50 events so users can see exactly what's been recorded. Server side lives in `server/telemetry/` (FastAPI module + HTML dashboard), deployed alongside `checkin-api` on 23.80.91.14.
- `RecoveryManager.resetCoreToStopped(ref)` is the canonical "reset to stopped" — use it instead of writing 4 provider states manually.

## Testing & enforcement

```bash
flutter test                    # 207 tests
bash scripts/check_imports.sh   # modules must NOT import datasources/ directly
```

Modules import via repository/auth layer. `yue_auth` re-exports `XBoardApiException`, `UserProfile` etc. via `yue_auth_providers.dart`. `store_repository.dart` re-exports store types.

Pre-commit (`scripts/pre-commit`): analyze + test + import check. Install: `ln -sf ../../scripts/pre-commit .git/hooks/pre-commit`.

`analysis_options.yaml`: `cancel_subscriptions`, `close_sinks`, `prefer_const_constructors`, `avoid_unnecessary_containers`.

## Git & CI

- Branches: `master` (release), `dev` (development). CI triggers only on tags + `workflow_dispatch`.
- Tags: `v*` → GitHub Release; `pre` → pre-release (overwrites previous). Move `pre`: `git tag -d pre && git push origin :refs/tags/pre && git tag pre && git push origin pre`.
- Release flow: commit to `dev` → move `pre` for test build → merge `dev`→`master` → `git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z`. Never tag before pushing the commit.
- Pipeline: analyze+test → Go cores (matrix) → Flutter builds (download artifacts → install → build) → release.
- Artifacts: `YueLink-Windows-Setup.exe` (Inno), `YueLink-macOS.dmg` (create-dmg, universal), `YueLink-Android.apk` (fat), `YueLink-iOS.ipa` (no-codesign).
- Submodule: `core/mihomo`. Clone with `--recursive`.
- **mihomo patches** (`core/patches/`, applied in CI): `0001-non-fatal-buildAndroidRules` (PackageManager errors non-fatal), `0002-non-fatal-mmdb-and-iptables` (MMDB/ASN `log.Fatalln` → `Errorln`, removes `os.Exit(2)` in iptables). Prevents Go from killing the whole Flutter process on non-critical failures.
