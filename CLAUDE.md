# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YueLink (by Yue.to) is a cross-platform proxy client built with Flutter + mihomo (Clash.Meta) Go core.
Supports: Android, iOS, macOS, Windows, Linux.

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
                                                              Platform VPN service (TUN/system proxy)
```

### Key layers

- **`core/`** — Go wrapper around mihomo. Exports C functions via `//export` (CGO). Compiled to `.so`/`.dylib`/`.dll` (dynamic) or `.a` (static, iOS only) via `setup.dart`.
- **`lib/ffi/`** — Dart FFI bindings. `CoreBindings` is raw FFI, `CoreController` is the high-level Dart API with memory management.
- **`lib/providers/`** — Riverpod state management. `core_provider.dart` (lifecycle, traffic, heartbeat), `proxy_provider.dart` (nodes, groups, delay tests), `profile_provider.dart` (subscriptions), `proxy_provider_provider.dart` (remote proxy providers).
- **`lib/pages/`** — Pages: home (connect/traffic), proxy/nodes (node selection + routing mode), connections, profile (subscriptions), settings. Plus `proxy_provider_page.dart` (accessed from Settings → Tools).
- **`lib/services/`** — `VpnService` (MethodChannel), `MihomoApi` (REST on port 9090), `MihomoStream` (WebSocket for traffic/logs), `CoreManager` (lifecycle singleton), `ProfileService` (static methods for profile CRUD + config loading), `OverwriteService` (config merging), `SettingsService` (SharedPreferences wrapper).
- **`lib/theme.dart`** — Design system: `YLColors` (zinc palette + semantic colors), `YLText` (typography), `YLSpacing`/`YLRadius` (spacing/radius scales), reusable widgets (`YLSurface`, `YLGlassSurface`, `YLStatusDot`, `YLSectionLabel`, `YLEmptyState`, `YLChip`, `YLDelayBadge`).
- **`lib/constants.dart`** — `AppConstants` (ports, version, config file names).
- **`lib/l10n/app_strings.dart`** — Hand-written `S` class for i18n. Both Chinese and English via `_e ? 'en' : 'zh'` ternaries. No code generation.

### Platform VPN implementations

| Platform | Mechanism | Location |
|----------|-----------|----------|
| Android | `VpnService` + TUN fd → Go core | `android/.../YueLinkVpnService.kt` |
| iOS | `NEPacketTunnelProvider` (separate process, static lib) | `ios/PacketTunnel/` |
| macOS | System proxy via `networksetup` | `lib/providers/core_provider.dart` |
| Windows | System proxy via registry | `lib/providers/core_provider.dart` |

### Native library install paths

`setup.dart install` copies built libraries to these locations (all gitignored):

| Platform | Destination | Xcode/build system expectation |
|----------|-------------|-------------------------------|
| Android | `android/app/src/main/jniLibs/<abi>/libclash.so` | Gradle picks up from jniLibs |
| iOS | `ios/Frameworks/libclash.a` + `.h` | `$(SOURCE_ROOT)/Frameworks/` — PacketTunnel target needs `LIBRARY_SEARCH_PATHS` |
| macOS | `macos/Frameworks/libclash.dylib` | Universal binary via `lipo` if both arches built |
| Windows | `windows/libs/libclash.dll` | — |

### Critical conventions

- iOS: Go core must be `c-archive` (static library), not `c-shared`. Extension runs in separate process with ~15MB memory limit.
- All C strings returned by Go core must be freed via `FreeCString` — handled automatically by `CoreController._callJsonFunction()`.
- Go core state is protected by a single mutex (`state.go`) — all exported functions must acquire the lock.
- MethodChannel name: `com.yueto.yuelink/vpn` (consistent across all platforms).
- Package/Bundle ID: `com.yueto.yuelink`
- App Group (iOS): `group.com.yueto.yuelink`
- User-Agent for subscription downloads: `clash.meta` (required for airport compatibility).
- `ProfileService` uses static methods, not a Riverpod provider. Call `ProfileService.loadConfig(id)` directly.

### Mock mode

When Go core is unavailable (no native library), `CoreController` automatically falls back to `CoreMock`, which simulates proxy groups, nodes, traffic, and connections. UI development works fully without Go — just `flutter run`.

### Core startup sequence

`CoreActions.start()` → `CoreManager._ensureInit()` (calls `InitCore(homeDir)` once) → `CoreManager.start(configYaml)` → `VpnService.startVpn()` → system proxy setup (desktop). The `_waitForApi()` call is non-blocking.

### Proxy group ordering

Groups are ordered by the `GLOBAL` group's `all` field from the mihomo API (`/proxies`), not alphabetically. See `proxy_provider.dart` `ProxyGroupsNotifier.refresh()`.

## Git & CI

- **Branches**: `master` (main/release), `dev` (development). CI triggers on push to `main` and `dev`, and on PRs.
- **CI pipeline** (`.github/workflows/build.yml`): analyze+test → build Go cores (per-platform matrix) → Flutter builds (download core artifacts → install → build).
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
