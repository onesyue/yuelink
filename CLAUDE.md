# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YueLink (by Yue.to) is a cross-platform proxy client built with Flutter + mihomo (Clash.Meta) Go core.
Supports: Android, iOS, macOS, Windows, Linux. Version: `0.0.1-alpha` (dev uses `v0.0.1-alpha` tag; version increments only for releases).

## Build Commands

```bash
flutter pub get                                    # Install Flutter dependencies
dart setup.dart build -p <platform> [-a <arch>]    # Compile Go core (android|ios|macos|windows|linux)
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

- **`core/`** — Go wrapper around mihomo. Exports C functions via `//export` (CGO). Compiled to `.so`/`.dylib`/`.dll` (dynamic) or `.a` (static, iOS only) via `setup.dart`.
- **`lib/ffi/`** — Dart FFI bindings. `CoreBindings` has raw FFI (8 lifecycle symbols only: InitCore, StartCore, StopCore, Shutdown, IsRunning, ValidateConfig, UpdateConfig, FreeCString). `CoreController` is the high-level wrapper; data methods (getProxies, changeProxy, testDelay, getTraffic) always delegate to `CoreMock` — they exist only for mock mode UI development.
- **`lib/providers/`** — Riverpod state management. `core_provider.dart` (lifecycle, traffic, heartbeat), `proxy_provider.dart` (nodes, groups, delay tests), `profile_provider.dart` (subscriptions), `proxy_provider_provider.dart` (remote proxy providers).
- **`lib/pages/`** — 4-tab layout: Dashboard (connect/traffic/status), Nodes (proxy groups + routing mode), Profile (subscriptions), Settings. Settings sub-pages: connections, logs, overwrite, proxy providers.
- **`lib/services/`** — `VpnService` (MethodChannel), `MihomoApi` (REST on port 9090), `MihomoStream` (WebSocket for traffic/logs), `CoreManager` (lifecycle singleton — handles VPN internally per platform), `ProfileService` (static methods for profile CRUD + config loading), `OverwriteService` (config merging), `SettingsService` (SharedPreferences wrapper).
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
- `CoreManager` handles VPN internally for each platform — `CoreActions` must NOT call `VpnService` directly.
- Android VPN permission is always requested (no connectionMode guard) because Android always needs VpnService.
- Connection mode UI is hidden on mobile — only shown on desktop (`isDesktop = Platform.isMacOS || Platform.isWindows`).
- MethodChannel name: `com.yueto.yuelink/vpn` (consistent across all platforms).
- Package/Bundle ID: `com.yueto.yuelink`
- App Group (iOS): `group.com.yueto.yuelink`
- User-Agent for subscription downloads: `clash.meta` (required for airport compatibility).
- `ProfileService` uses static methods, not a Riverpod provider. Call `ProfileService.loadConfig(id)` directly.
- `YLColors.primary` is black (`#000000`) — never use it as foreground in dark mode. Use `isDark ? Colors.white : YLColors.primary` pattern.
- Android native strings (VPN notification etc.) use Android string resources with `values-zh/` locale variant, not the Dart `S` class.

### FFI symbol alignment

Dart bindings (`core_bindings.dart`) must exactly match Go exports (`core/hub.go`). Current 8 Dart bindings match 8 of 9 Go exports (`GetVersion` is intentionally unbound — version comes via REST API). **Never add FFI bindings for data operations** — those belong in `MihomoApi`.

### Mock mode

When Go core is unavailable (no native library), `CoreController` automatically falls back to `CoreMock`, which simulates proxy groups, nodes, traffic, and connections. UI development works fully without Go — just `flutter run`.

### Core startup sequence

`CoreActions.start()` → VPN permission (Android only) → `CoreManager.start(configYaml)` → `OverwriteService.apply()` → platform-specific VPN (Android: `startAndroidVpn()` for TUN fd, iOS: `startIosVpn()`) → `ConfigTemplate.process()` → `CoreController.start()` → `_waitForApi()` (non-blocking) → system proxy (desktop). `CoreManager` owns all VPN logic internally.

### Proxy group ordering

Groups are ordered by the `GLOBAL` group's `all` field from the mihomo API (`/proxies`), not alphabetically. See `proxy_provider.dart` `ProxyGroupsNotifier.refresh()`.

## Git & CI

- **Branches**: `master` (main/release), `dev` (development). CI triggers on push to `main` and `dev`, and on version tags (`v*`).
- **Versioning**: Dev cycle uses `v0.0.1-alpha` tag (delete + recreate on same tag). Version increments only for formal releases.
- **CI pipeline** (`.github/workflows/build.yml`): analyze+test → build Go cores (per-platform matrix) → Flutter builds (download core artifacts → install → build) → release (on `v*` tags).
- **Release artifacts**: `YueLink-Windows-Setup.exe` (Inno Setup), `YueLink-macOS.dmg` (create-dmg, universal binary), `YueLink-Android.apk` (fat universal), `YueLink-iOS.ipa` (no-codesign).
- **Analyze in CI** uses `--no-fatal-infos --no-fatal-warnings` — only errors fail the build.
- Submodules: `core/mihomo` is a git submodule. Clone with `--recursive` or run `git submodule update --init --recursive`.

## Testing

```bash
flutter test                          # Run all tests
flutter test test/models/             # Model tests (profile, proxy, traffic, rule, connection)
flutter test test/services/           # Service tests (config_template, mihomo_api, mihomo_stream, subscription_parser)
flutter test test/ffi/                # FFI/mock tests
flutter test test/providers/          # Provider tests
```
