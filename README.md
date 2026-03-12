# YueLink

**by [Yue.to](https://yue.to)**

[![Build](https://github.com/onesyue/yuelink/actions/workflows/build.yml/badge.svg)](https://github.com/onesyue/yuelink/actions/workflows/build.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.27-blue)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)

A cross-platform proxy client built with Flutter and the [mihomo](https://github.com/MetaCubeX/mihomo) (Clash.Meta) core.

## Platform Support

| Platform | Proxy Method | Status |
|----------|-------------|--------|
| Android | VpnService + TUN | ✅ |
| iOS | NetworkExtension (PacketTunnel) | ✅ |
| macOS | System Proxy (networksetup) | ✅ Apple Silicon (M1–M5) + Intel universal |
| Windows | System Proxy (registry) | ✅ |

## Features

- **Subscription management** — add, update, and import local configs; parse traffic and expiry info
- **Proxy nodes** — grouped view, search and filter, latency sorting, single and batch speed tests
- **Routing modes** — Rule / Global / Direct, switchable at any time
- **Connection monitor** — live connection list with search, filter, and one-tap close
- **Config overwrite** — layer custom rules on top of subscription configs
- **Proxy providers** — view and refresh remote proxy-provider sources
- **WebDAV sync** — backup and restore settings across devices
- **Split tunneling** — Android per-app whitelist / blacklist mode
- **GeoIP / GeoSite** — downloaded automatically on first launch, kept up to date
- Light / dark theme, Chinese / English language switch
- Launch at startup, auto-connect on open

## Quick Start

```bash
git clone --recursive https://github.com/onesyue/yuelink.git
cd yuelink
flutter pub get
flutter run   # runs in Mock mode — full UI works without the Go core
```

### Build the Go core (optional)

```bash
# macOS: build both arches then install the universal binary
dart setup.dart build -p macos -a arm64   # Apple Silicon (M1–M5)
dart setup.dart build -p macos -a x86_64  # Intel
dart setup.dart install -p macos          # lipo-merges into universal dylib
flutter run -d macos
```

## Architecture

YueLink is structured as a **Platform Shell + Generic Proxy Core + Yue.to Business Modules**.

```
YueLink
├── core/          Go wrapper around mihomo (FFI lifecycle only)
├── lib/
│   ├── app/       Startup, routing, theme
│   ├── core/      FFI bindings, kernel (CoreManager), platform VPN, storage
│   ├── domain/    Data models (pure Dart, no Flutter deps)
│   ├── infrastructure/  Datasources (MihomoApi, MihomoStream) + Repositories
│   ├── modules/
│   │   ├── dashboard/     Connect/traffic/status
│   │   ├── nodes/         Proxy groups + node-level granular refresh
│   │   ├── profiles/      Subscription management
│   │   ├── connections/   Active connections
│   │   ├── logs/          Log viewer
│   │   ├── settings/      App settings + sub-pages
│   │   │
│   │   ├── yue_auth/      [Skeleton] Yue.to authentication
│   │   ├── yue_account/   [Skeleton] Yue.to account & membership
│   │   ├── yue_store/     [Skeleton] Yue.to store & subscriptions
│   │   ├── announcements/ [Skeleton] Announcements & notifications
│   │   └── updater/       [Skeleton] App version updates
│   └── shared/    App-wide utilities (AppNotifier, formatters)
└── android/ios/macos/windows/  Platform runners
```

**Layer rules:**
- `modules/` pages consume `providers/` and `repositories/` only — never datasources or FFI directly
- `infrastructure/repositories/` mediate between providers and datasources (`MihomoApi`, `MihomoStream`)
- Business modules (`yue_*`, `announcements`, `updater`) do not touch mihomo core lifecycle
- `[Skeleton]` modules are directory-only in the current release; business logic not yet implemented

**Refresh model (Nodes page):**
One node delay update triggers exactly one `NodeTile` rebuild via `nodeDelayProvider(name)` family provider. `_DelayBatcher` in `ProxyRepository` batches delay results with a 300 ms flush window before writing to state.

FFI handles only core lifecycle (init, start, stop). All runtime data — proxies, traffic, connections — flows through the mihomo REST API. This mirrors the architecture of FlClash and Clash Verge Rev.

- **iOS** — compiled as a static library (`c-archive`) loaded inside a NetworkExtension process
- **All other platforms** — compiled as a shared library (`c-shared`)
- **Mock mode** — when no native library is present, `CoreController` falls back to `CoreMock`, which simulates proxy groups, traffic, and connections so the full UI is interactive without any Go toolchain

## Requirements

| Tool | Version | Notes |
|------|---------|-------|
| Flutter | >= 3.22 | UI framework (CI: 3.27.4) |
| Dart | >= 3.4 | bundled with Flutter |
| Go | >= 1.22 | builds the mihomo core (CI: 1.23) — optional in Mock mode |
| Android NDK | r26+ | Android builds only |
| Xcode | >= 15 | iOS / macOS builds only |

## Building

```bash
# Go core
dart setup.dart build -p <platform> [-a <arch>]   # android | ios | macos | windows
dart setup.dart install -p <platform>
dart setup.dart clean

# Flutter
flutter build apk          # Android (universal)
flutter build ios          # iOS
flutter build macos        # macOS
flutter build windows      # Windows
```

CI artifacts: `YueLink-Android.apk`, `YueLink-macOS.dmg` (universal arm64+x86_64), `YueLink-Windows-Setup.exe`.
iOS builds use `--no-codesign` for compile verification only; installation requires manual signing.

## Testing

```bash
flutter test       # unit tests
flutter analyze    # static analysis (CI: --no-fatal-infos --no-fatal-warnings)
```

## Project Structure

```
yuelink/
├── core/                  # Go wrapper around mihomo (CGO //export)
│   ├── mihomo/            # mihomo submodule
│   └── patches/           # patches for non-fatal MMDB / iptables issues
├── lib/
│   ├── ffi/               # dart:ffi bindings + CoreMock fallback
│   ├── models/            # data models
│   ├── providers/         # Riverpod state (core, proxy, profile, connections)
│   ├── pages/             # Dashboard / Nodes / Connections / Profile / Log / Settings
│   ├── services/          # CoreManager, MihomoApi, VpnService, GeoDataService, …
│   ├── l10n/              # i18n — hand-written S class, zh + en in one file
│   └── theme.dart         # design system (YLColors, YLText, YLShadow)
├── android/               # VpnService TUN implementation
├── ios/                   # PacketTunnel NetworkExtension
├── windows/               # Windows runner + Inno Setup installer script
├── setup.dart             # Go core build tool
└── test/                  # unit tests
```

## Identifiers

| Key | Value |
|-----|-------|
| Package / Bundle ID | `com.yueto.yuelink` |
| App Group (iOS) | `group.com.yueto.yuelink` |
| MethodChannel | `com.yueto.yuelink/vpn` |
| Config filename | `yuelink.yaml` |
| User-Agent | `clash.meta` |

## License

[MIT](LICENSE)
