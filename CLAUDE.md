# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YueLink (by Yue.to) is a cross-platform proxy client built with Flutter + mihomo (Clash.Meta) Go core.
Supports: Android, iOS, macOS, Windows, Linux.

## Build Commands

```bash
# Install Flutter dependencies
flutter pub get

# Compile Go core (requires Go >= 1.22)
dart setup.dart build -p <platform> [-a <arch>]  # android|ios|macos|windows|linux
dart setup.dart install -p <platform>              # Copy libs to Flutter dirs
dart setup.dart clean                              # Remove build artifacts

# Run
flutter run

# Analyze
flutter analyze

# Build release
flutter build apk          # Android
flutter build ios          # iOS
flutter build macos        # macOS
flutter build windows      # Windows
```

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
- **`lib/pages/`** — 6-tab UI: home (connect/traffic), proxy (node selection + routing mode), connections, profile (subscriptions), log (logs + rules tab), settings. Plus `proxy_provider_page.dart` (accessed from Settings → Tools).
- **`lib/services/`** — Platform abstractions: `VpnService` (MethodChannel), `MihomoApi` (REST client for mihomo on port 9090), `MihomoStream` (WebSocket for traffic/logs), `CoreManager` (lifecycle singleton), `OverwriteService` (config merging), `SettingsService` (SharedPreferences wrapper).

### Platform VPN implementations

| Platform | Mechanism | Location |
|----------|-----------|----------|
| Android | `VpnService` + TUN fd → Go core | `android/.../YueLinkVpnService.kt` |
| iOS | `NEPacketTunnelProvider` (separate process, static lib) | `ios/PacketTunnel/` |
| macOS | System proxy via `networksetup` | `lib/providers/core_provider.dart` (`_setSystemProxy`) |
| Windows | System proxy via registry | `lib/providers/core_provider.dart` (`_setSystemProxy`) |

### Critical conventions

- iOS: Go core must be `c-archive` (static library), not `c-shared`. Extension runs in separate process with ~15MB memory limit.
- All C strings returned by Go core must be freed via `FreeCString` — handled automatically by `CoreController._callJsonFunction()`.
- Go core state is protected by a single mutex (`state.go`) — all exported functions must acquire the lock.
- MethodChannel name: `com.yueto.yuelink/vpn` (consistent across all platforms).
- Package/Bundle ID: `com.yueto.yuelink`
- App Group (iOS): `group.com.yueto.yuelink`
- User-Agent for subscription downloads: `clash.meta` (required for airport compatibility).

### Mock mode

When Go core is unavailable (no native library), `CoreController` automatically falls back to `CoreMock`, which simulates proxy groups, nodes, traffic, and connections. UI development works fully without Go.

### Core startup sequence

`CoreActions.start()` → `CoreManager._ensureInit()` (calls `InitCore(homeDir)` once) → `CoreManager.start(configYaml)` → `VpnService.startVpn()` → system proxy setup (desktop). The `_waitForApi()` call is non-blocking — startup returns immediately after the Go core starts, not after the API is available.

### Proxy group ordering

Groups are ordered by the `GLOBAL` group's `all` field from the mihomo API (`/proxies`), not alphabetically. See `proxy_provider.dart` `ProxyGroupsNotifier.refresh()`.

### i18n

Strings are defined in `lib/l10n/app_strings.dart` as a hand-written `S` class (no code generation). Both Chinese and English are in the same file via `_e ? 'en' : 'zh'` ternaries. JSON files in `lib/i18n/` are for the `slang` package (secondary system, regenerate with `dart run build_runner build`).

## Dependencies

- Flutter >= 3.22, Dart >= 3.4
- Go >= 1.22 (for core compilation)
- `flutter_riverpod` for state management
- `ffi` + `path_provider` + `http` + `web_socket_channel` as core Dart deps
- Android NDK r26+ for Android builds
- Xcode >= 15 for iOS/macOS builds

## Testing

```bash
flutter test                          # Run all tests
flutter test test/models/             # Run model tests only
flutter test test/services/           # Run service tests only
flutter test test/ffi/                # Run FFI/mock tests only
```

Test files: `test/models/` (profile, proxy, traffic, rule, connection), `test/providers/` (profile provider), `test/services/` (config_template, mihomo_api, mihomo_stream, subscription_parser), `test/ffi/` (core mock).
