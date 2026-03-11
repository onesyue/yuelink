# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YueLink (by Yue.to) is a cross-platform proxy client built with Flutter + mihomo (Clash.Meta) Go core.
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
```

**Critical split**: FFI is for lifecycle only (init/start/stop). All data operations (proxies, traffic, connections, rules) go through the REST API (`MihomoApi`), never FFI. This matches FlClash/Clash Verge Rev architecture.

### Key layers

- **`core/`** — Go wrapper around mihomo. Exports C functions via `//export` (CGO). Compiled to `.so`/`.dylib`/`.dll` (dynamic) or `.a` (static, iOS only) via `setup.dart`. Android builds use `-tags with_gvisor` (required for TUN fd/file-descriptor mode — without it mihomo fails with "gVisor is not included in this build").
- **`lib/ffi/`** — Dart FFI bindings. `CoreBindings` has raw FFI (8 lifecycle symbols: InitCore, StartCore, StopCore, Shutdown, IsRunning, ValidateConfig, UpdateConfig, FreeCString). `CoreController` is the high-level wrapper; data methods (getProxies, changeProxy, testDelay, getTraffic) always delegate to `CoreMock` — they exist only for mock mode UI development.
- **`lib/providers/`** — Riverpod state management. `core_provider.dart` (lifecycle, traffic, heartbeat), `proxy_provider.dart` (nodes, groups, delay tests), `profile_provider.dart` (subscriptions), `proxy_provider_provider.dart` (remote proxy providers).
- **`lib/pages/`** — 4-tab layout: Dashboard (connect/traffic/status), Nodes (proxy groups + routing mode), Subscriptions (profiles), Settings. Settings sub-pages: connections, logs, overwrite, proxy providers.
- **`lib/services/`** — `VpnService` (MethodChannel), `MihomoApi` (REST on port 9090), `MihomoStream` (WebSocket for traffic/logs), `CoreManager` (lifecycle singleton — handles VPN internally per platform), `ProfileService` (static methods for profile CRUD + config loading), `OverwriteService` (config merging), `ConfigTemplate` (config processing with ensure-pattern injection), `SettingsService` (SharedPreferences wrapper), `GeoDataService` (pre-downloads GeoIP/GeoSite files before core start), `AppNotifier` (global toast/snackbar), `AutoUpdateService`/`UpdateChecker` (app updates), `WebdavService` (backup/sync).
- **`lib/theme.dart`** — Design system: `YLColors` (zinc palette + semantic colors), `YLText` (typography), `YLSpacing`/`YLRadius`, `YLShadow` (context-aware for dark mode), reusable widgets (`YLSurface`, `YLStatusDot`, `YLChip`, `YLDelayBadge`, `YLPillSegmentedControl`, etc.).
- **`lib/l10n/app_strings.dart`** — Hand-written `S` class for i18n. Both Chinese and English via `_e ? 'en' : 'zh'` ternaries. No code generation. Use `S.of(context)` in widgets, `S.current` in providers/services without BuildContext.

### Platform VPN implementations

| Platform | Mechanism | Location |
|----------|-----------|----------|
| Android | `VpnService` + TUN fd → Go core (always, regardless of connectionMode) | `android/.../YueLinkVpnService.kt` |
| iOS | `NEPacketTunnelProvider` (separate process, static lib) | `ios/PacketTunnel/` |
| macOS | System proxy via `networksetup` | `lib/providers/core_provider.dart` |
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
- **iOS TUN config**: `PacketTunnelProvider.injectTunConfig()` uses `stack: gvisor`. Also forces `find-process-mode: off` and injects full DNS fallback config.
- Connection mode UI is hidden on mobile — only shown on desktop (`isDesktop = Platform.isMacOS || Platform.isWindows`).
- MethodChannel name: `com.yueto.yuelink/vpn` (consistent across all platforms).
- Package/Bundle ID: `com.yueto.yuelink`
- App Group (iOS): `group.com.yueto.yuelink`
- User-Agent for subscription downloads: `clash.meta` (required for airport compatibility).
- `ProfileService` uses static methods, not a Riverpod provider. Call `ProfileService.loadConfig(id)` directly.
- `YLColors.primary` is black (`#000000`) — never use it as foreground in dark mode. Use `isDark ? Colors.white : YLColors.primary` pattern.
- Android native strings (VPN notification etc.) use Android string resources with `values-zh/` locale variant, not the Dart `S` class.
- **Sidebar uses instant state switching** (no AnimatedContainer). This is intentional to avoid flicker on Windows. Do not add animation back.

### FFI symbol alignment

Dart bindings (`core_bindings.dart`) must exactly match Go exports (`core/hub.go`). Current 8 Dart bindings match 8 of 9 Go exports (`GetVersion` is intentionally unbound — version comes via REST API). **Never add FFI bindings for data operations** — those belong in `MihomoApi`. All failable exports return `Pointer<Utf8>` (C string), not `int`.

### Mock mode

When Go core is unavailable (no native library), `CoreController` automatically falls back to `CoreMock`, which simulates proxy groups, nodes, traffic, and connections. UI development works fully without Go — just `flutter run`.

### Config processing pipeline (`ConfigTemplate.process()`)

Uses "ensure" pattern: only injects when missing, never overwrites subscription-provided settings.

1. Replace template variables (`$app_name` → `YueLink`)
2. `_ensureMixedPort` — without it mihomo silently skips HTTP+SOCKS listener
3. `_ensureExternalController` — REST API endpoint for data operations
4. `_ensureDns` — comprehensive fake-ip + fallback + fallback-filter (all modes, not just TUN)
5. `_ensureSniffer` — HTTP/TLS/QUIC domain detection for DOMAIN-type rules
6. `_ensureGeodata` — geodata-mode + geo URLs + auto-update for GEOIP/GEOSITE rules
7. `_ensureProfile` — store-selected + store-fake-ip persistence
8. `_ensurePerformance` — tcp-concurrent, unified-delay, TLS fingerprint
9. `_ensureAllowLan` — allow-lan + bind-address for mixed-port
10. `_ensureFindProcessMode` — `always` on desktop, `off` on mobile (no permission)
11. `_injectTunFd` — Android TUN fd injection (only when tunFd provided)

iOS PacketTunnelProvider has its own `injectTunConfig()` in Swift with equivalent logic (runs in separate process, can't use Dart ConfigTemplate).

### Core startup sequence & diagnostics

`CoreManager.start()` runs 8 observable steps, each recorded in `StartupReport` (`lib/models/startup_report.dart`) with name, success, errorCode, error, detail, and durationMs:

| Step | errorCode | What it does |
|------|-----------|--------------|
| `ensureGeo` | E009 | Copy GeoIP/GeoSite assets to homeDir (CDN fallback if missing) |
| `initCore` | E002 | Call `InitCore(homeDir)` via FFI, set up Go logrus → `core.log` |
| `vpnPermission` | E003 | Android only: request VpnService permission |
| `startVpn` | E004 | Android only: get TUN fd from `VpnService` |
| `buildConfig` | E005 | `OverwriteService.apply()` + `ConfigTemplate.process()` (sync, no Isolate) |
| `startCore` | E006 | Call `StartCore(configYaml)` via FFI (hub.Parse + listeners) |
| `waitApi` | E007 | Poll REST API up to 50× × 100ms = 5s |
| `verify` | E008 | Check `IsRunning` + API available + DNS diagnostic |

On failure, `StartupReport.failureSummary` returns `"[Exx_CODE] stepName: error"` — shown in `_StartupErrorBanner` on dashboard (expandable: shows all steps + last 20 lines of Go `core.log`). Report saved to `startup_report.json`. Go side logs tagged `[BOOT]`/`[CORE]` via logrus redirected to `core.log`; Dart reads this after startup in `_finishReport()`.

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
