# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YueLink (by Yue.to) is a cross-platform proxy client built with Flutter + mihomo (Clash.Meta) Go core.
Supports: Android, iOS, macOS, Windows, Linux.

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

Go >= 1.22 required for core compilation. Flutter >= 3.38.4, Dart >= 3.10.3. CI uses Flutter 3.41.5, Go 1.23.

## Architecture

```
Flutter UI (Dart, Riverpod) → CoreController (dart:ffi) → hub.go (CGO //export) → mihomo engine
                                                                                       ↕
                              MihomoApi (REST :9090) ← ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ mihomo HTTP API
                                                                                       ↕
                                                              Platform VPN service (TUN/system proxy)
```

**Unified `ClashCore` interface** (`lib/core/clash_core.dart`): every clash operation — lifecycle AND data — lives on one abstract class. `RealClashCore` dispatches lifecycle to FFI bindings (`CoreController`) and data to REST (`MihomoApi`); `MockClashCore` routes everything to `CoreMock`. Callers do `CoreManager.instance.core.X()` and don't care which side they're on. See CLAUDE.md for the canonical layout and call patterns.

> NOTE: This file is older than CLAUDE.md. CLAUDE.md is the authoritative architecture reference; refer to it first when in doubt.

### Key layers (post dual-layer cleanup)

- **`core/`** (Go) — Go wrapper around mihomo. Exports C functions via `//export` (CGO). Compiled to `.so`/`.dylib`/`.dll`/`.a` via `setup.dart`. Android builds use `-tags with_gvisor`.
- **`lib/core/`** — All kernel + FFI + managers + ClashCore + central providers + storage + service-mode helper.
- **`lib/infrastructure/`** — Datasources (mihomo REST, websocket, XBoard 5-file submodule) + repositories.
- **`lib/modules/`** — 17 feature modules (dashboard, nodes, store, emby, …). Each has page + providers/ + widgets/.
- **`lib/shared/`** — `app_notifier`, `error_logger`, `event_log`, `formatters/`, `rich_content`, `traffic_formatter`.
- **`lib/i18n/`** — slang JSON sources + codegen (`strings_g.dart`) + `S` adapter (`app_strings.dart`).
- **`lib/theme.dart`** — Design system: `YLColors`, `YLText`, `YLSpacing`/`YLRadius`, `YLShadow`, reusable widgets.

### Platform VPN implementations

| Platform | Mechanism | Location |
|----------|-----------|----------|
| Android | `VpnService` + TUN fd → Go core (always, regardless of connectionMode) | `android/.../YueLinkVpnService.kt` |
| iOS | `NEPacketTunnelProvider` (separate process, static lib) | `ios/PacketTunnel/` |
| macOS | System proxy via `networksetup` (or Service Mode TUN via Unix socket helper) | `lib/core/managers/system_proxy_manager.dart` |
| Windows | System proxy via registry (or Service Mode TUN via HTTP+token helper) | `lib/core/managers/system_proxy_manager.dart` |
| Linux | System proxy via gsettings/kwriteconfig (or Service Mode TUN) | `lib/core/managers/system_proxy_manager.dart` |

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

- **Branches**: `master` (release), `dev` (development). The release workflow (`build.yml`) only runs on tag pushes and manual `workflow_dispatch`. Branch pushes run `ci.yml` (analyze + test) only.
- **Tag strategy**: `v*` tags publish a GitHub Release (stable). `pre` is a floating pre-release tag that is re-pointed and overwritten each iteration. `vX.Y.Z-pre` tags are also treated as pre-releases.
- **Release flow**: commit to `dev` → move `pre` for a test build (`git tag -d pre && git push origin :refs/tags/pre && git tag pre && git push origin pre`) → merge `dev` → `master` → `git tag -a vX.Y.Z -m "…" && git push origin vX.Y.Z`. Never tag before pushing the commit.
- **CI pipeline** (`.github/workflows/build.yml`): checkout + submodule → apply `core/patches/*.patch` → build Go cores (per-platform matrix) → `dart setup.dart install` → Flutter build/package → upload artifact → release job downloads all artifacts, hashes, publishes, refreshes updater manifest.
- **Release artifacts**: `YueLink-<version>-android-{universal,arm64-v8a,armeabi-v7a,x86_64}.apk`, `YueLink-<version>-ios.ipa`, `YueLink-<version>-macos-universal.dmg`, `YueLink-<version>-windows-amd64-{setup.exe,portable.zip}`, `YueLink-<version>-linux-amd64.AppImage`. 每个产物都会附带同名 `.sha256` 校验文件。
- **Analyze in CI** uses `--no-fatal-infos --no-fatal-warnings` — only errors fail the build.
- Submodules: `core/mihomo` is a git submodule. Clone with `--recursive` or run `git submodule update --init --recursive`.
- **mihomo patches** (`core/patches/`): applied to `core/mihomo/` both by CI and by the local `dart setup.dart build` step (idempotent — already-applied patches are skipped). `0001-non-fatal-buildAndroidRules.patch` (PackageManager errors non-fatal), `0002-non-fatal-mmdb-and-iptables.patch` (MMDB/ASN `log.Fatalln` → `log.Errorln`, removes `os.Exit(2)` from iptables handler). These prevent the Go core from killing the entire Flutter process on non-critical failures.

## Testing

```bash
flutter test                          # Run all tests
flutter test test/models/             # Model tests (profile, proxy, traffic, rule, connection)
flutter test test/services/           # Service tests (config_template, mihomo_api, mihomo_stream, subscription_parser)
flutter test test/ffi/                # FFI/mock tests
flutter test test/providers/          # Provider tests
```
