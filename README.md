# 悦通 · YueLink

**专为 Yue.to 账号、AI 服务与流媒体场景打造的跨平台代理客户端**

[![Build](https://github.com/onesyue/yuelink/actions/workflows/build.yml/badge.svg)](https://github.com/onesyue/yuelink/actions/workflows/build.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.41-blue)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-lightgrey)]()
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

YueLink 是一个基于 Flutter + [mihomo](https://github.com/MetaCubeX/mihomo) 构建的跨平台代理客户端，面向 Yue.to 账号体系做了完整集成：登录后可自动同步订阅、节点、套餐、订单、公告、签到和 Emby 媒体服务。

它既是一个日常可用的代理客户端，也是一个具备桌面增强能力的独立分发应用：支持 Android / iOS / macOS / Windows / Linux，支持 GitHub Release 自更新、桌面 TUN / Service Mode、模块运行时、启动诊断与一键修复。

---

## 项目定位

- **Yue.to 深度集成**：账号登录、订阅同步、套餐购买、优惠券、订单历史、公告、签到、Emby 全链路接入。
- **多平台一致体验**：Android / iOS 走系统 VPN 能力，桌面端默认系统代理，也支持切换 TUN。
- **独立分发优先**：GitHub Releases 提供五端正式产物，应用内支持稳定版 / 预发布更新通道。
- **可开发、可扩展**：Flutter UI + Go core 解耦，支持 mock mode、本地原生构建、CI 全平台发布。

---

## 核心能力

| 能力域 | 当前能力 |
|------|------|
| 代理与连接 | 登录后自动同步订阅；多配置导入/导出；代理组切换；节点测速；延迟排序；规则 / 全局 / 直连路由模式；连接明细与日志页 |
| 桌面增强 | 系统代理模式；桌面 TUN 模式；Service Mode 特权辅助进程；托盘菜单；全局快捷键；开机启动；连接修复与启动报告 |
| 账号与运营 | 套餐展示；购买 / 续费；优惠码校验；订单历史；公告拉取；每日签到；账户与流量信息 |
| 流媒体 | Emby 媒体库首页、详情页、剧集页、原生播放器、断点续播、字幕和音轨控制、代理感知图片缓存 |
| 更新与发布 | GitHub Release 自更新；稳定版 / 预发布双通道；SHA-256 校验；多镜像 manifest 拉取 |
| 国际化 | 简体中文 / English 双语切换 |

### 重点特性

#### 1. 代理核心

- 基于 mihomo 内核，Flutter 通过 FFI 管理生命周期，通过 REST / WebSocket 获取代理、流量、日志和连接数据。
- Android 使用 `VpnService + TUN (gVisor)`。
- iOS 使用 `NetworkExtension / PacketTunnel`。
- 桌面端默认 `systemProxy`，可切换 `TUN`；必要时可安装 `Service Mode` 特权 helper。

#### 2. Emby 媒体体验

- Netflix 风格首页：Hero Banner + 横向海报行。
- 原生播放器：倍速、字幕大小、音轨切换、播放进度同步、续播提示。
- 兼容 STRM 搬运库和合集库。
- API、图片、视频、字幕都走代理链路。

#### 3. Surge 模块运行时

YueLink 当前内置一套可用的 Surge 模块兼容层，支持：

- `.sgmodule` 下载、解析、启用 / 禁用 / 删除
- Rule 注入到 mihomo YAML
- MITM Engine 与 Root CA 生成 / 导出
- URL Rewrite、Request / Response Header Rewrite
- `http-response` 响应脚本

这套模块运行时的定位是**最小可用实现**，不是完整 Surge Script 运行时。已知限制包括：

- Android 7+ 对用户安装 CA 的信任限制
- Certificate Pinning 应用无法被 MITM
- 当前只支持 Response Script，不支持 `$httpClient`、真实 `$persistentStore`、HTTP/2 MITM、WebSocket 拦截

相关文档：

- [模块能力清单](docs/MODULE_RUNTIME_CAPABILITIES.md)
- [已知限制](docs/MODULE_RUNTIME_KNOWN_LIMITATIONS.md)
- [模块运行时发布说明](docs/RELEASE_NOTES_MODULE_RUNTIME.md)

#### 4. 桌面排障与运维

- 设置页内置**连接修复**页面，可执行重建 VPN、清理缓存、重同步订阅、一键修复。
- 启动失败会自动生成 `startup_report.json`，记录启动步骤、错误码、耗时和核心日志摘要。
- 桌面端支持托盘菜单、快速显示窗口、快捷键切换、开机启动。

---

## 下载与产物

正式版与预发布版均通过 GitHub Releases 分发：

- Release 列表：https://github.com/onesyue/yuelink/releases
- 稳定版 tag：`vX.Y.Z`
- 预发布 tag：`pre`

### 正式版产物命名

| 文件 | 适用平台 | 说明 |
|------|----------|------|
| `YueLink-<version>-android-universal.apk` | Android | 默认推荐；绝大多数用户下载这个即可 |
| `YueLink-<version>-android-arm64-v8a.apk` | Android | 64 位 ARM 设备专用 |
| `YueLink-<version>-android-armeabi-v7a.apk` | Android | 32 位 ARM 设备专用 |
| `YueLink-<version>-android-x86_64.apk` | Android | x86_64 设备或模拟器 |
| `YueLink-<version>-ios.ipa` | iOS | TrollStore / AltStore / SideStore 侧载包 |
| `YueLink-<version>-macos-universal.dmg` | macOS | Intel + Apple Silicon 通用 DMG |
| `YueLink-<version>-windows-amd64-setup.exe` | Windows | 默认推荐安装版 |
| `YueLink-<version>-windows-amd64-portable.zip` | Windows | 免安装便携版 |
| `YueLink-<version>-linux-amd64.AppImage` | Linux | x86_64 AppImage |

每个产物都会附带一个同名 `.sha256` 校验文件。

### 产物选择建议

- **Android**：优先下载 `android-universal.apk`，只有明确知道设备架构时再选分 ABI 包。
- **Windows**：优先下载 `setup.exe`，需要绿色版时再用 `portable.zip`。
- **macOS**：统一下载 `macos-universal.dmg`，无需区分 Intel 和 Apple Silicon。
- **iOS**：当前为独立分发侧载包，不走 App Store 安装。

---

## 安装说明

### Android

1. 允许安装未知来源应用。
2. 安装 `YueLink-<version>-android-universal.apk`。
3. 首次启动时授予 VPN 权限。

### iOS

支持以下侧载方式：

- **TrollStore**：推荐，安装后不过期
- **AltStore / SideStore**：自签安装，需按各自规则重签

### macOS

1. 打开 `YueLink-<version>-macos-universal.dmg`
2. 将 `YueLink.app` 拖入 `Applications`
3. 若首次启动被 Gatekeeper 拦截：
   - 优先双击 DMG 内附带的 `修复无法打开.command`
   - 或手动执行 `sudo xattr -cr /Applications/YueLink.app`

### Windows

- 安装版：运行 `YueLink-<version>-windows-amd64-setup.exe`
- 便携版：解压 `YueLink-<version>-windows-amd64-portable.zip` 后直接运行

### Linux

```bash
chmod +x YueLink-<version>-linux-amd64.AppImage
./YueLink-<version>-linux-amd64.AppImage
```

---

## 平台支持

| 平台 | 最低系统 | 网络实现 | 分发形态 | 备注 |
|------|---------|---------|---------|------|
| Android | Android 6.0 | `VpnService + TUN (gVisor)` | APK | 支持分应用代理 |
| iOS | iOS 15 | `PacketTunnel / NetworkExtension` | IPA | 侧载分发 |
| macOS | macOS 12 | 默认系统代理，可切换桌面 TUN | DMG | 支持 Service Mode |
| Windows | Windows 10 1903+ x64 | 默认系统代理，可切换桌面 TUN | EXE / ZIP | 支持托盘、快捷键、Service Mode |
| Linux | 主流 x86_64 桌面发行版 | 默认系统代理，可切换桌面 TUN | AppImage | 支持 Service Mode |

### 说明

- 移动端始终使用系统 VPN 能力，不提供系统代理模式切换。
- 桌面端默认连接模式为 `systemProxy`，适合大多数场景。
- 桌面 TUN 适合更完整的系统级接管需求；如需稳定的特权辅助，可安装 `Service Mode`。

---

## 更新通道

YueLink 在**独立分发版**中内置自更新逻辑：

- 默认检查稳定版 `update.json`
- 可在设置中切换到预发布通道 `update-pre.json`
- manifest 支持多镜像拉取，适配 GitHub API 不稳定或受限网络环境
- 下载后会校验 SHA-256

注意：

- **独立分发版**：支持应用内检查更新和下载更新
- **商店模式构建**：通过 `--dart-define=STANDALONE=false` 编译，自更新入口会被关闭

---

## 从源码运行

### 环境要求

| 工具 | 版本要求 | 备注 |
|------|---------|------|
| Flutter | `>= 3.38.4` | CI 当前使用 `3.41.7` |
| Dart | `>= 3.10.3` | 随 Flutter 安装 |
| Go | `>= 1.22` | CI 当前使用 `1.23` |
| Xcode | `>= 15` | iOS / macOS 构建 |
| Android NDK | `r26+` | Android 原生构建 |

### 快速开始：Mock Mode

不需要 Go core，也能跑完整 UI：

```bash
git clone --recursive https://github.com/onesyue/yuelink.git
cd yuelink
flutter pub get
flutter run
```

当本地没有原生内核时，YueLink 会自动进入 mock mode，用模拟的代理组、节点、流量和连接数据驱动界面。

### mihomo 子模块与补丁

`core/mihomo/` 是 git 子模块，首次克隆必须带 `--recursive`，或者在已有仓库中执行：

```bash
git submodule update --init --recursive
```

`core/patches/*.patch` 会在 **本地** `dart setup.dart build` 执行时自动应用到子模块，CI 也会在构建前应用同一份补丁。补丁应用是幂等的：若已应用会直接跳过，重复执行不会失败。出现冲突时会中止构建并提示具体 patch 名称。

### 完整原生构建

```bash
git clone --recursive https://github.com/onesyue/yuelink.git
cd yuelink
flutter pub get

# 首次构建桌面端时启用对应平台
flutter config --enable-macos-desktop
flutter config --enable-windows-desktop
flutter config --enable-linux-desktop

# Android：构建全部 ABI
dart setup.dart build -p android
dart setup.dart install -p android
flutter build apk

# iOS：构建 arm64 静态库
dart setup.dart build -p ios
dart setup.dart install -p ios
flutter build ios

# Windows / Linux：建议显式指定 amd64
dart setup.dart build -p windows -a amd64
dart setup.dart install -p windows
flutter build windows

dart setup.dart build -p linux -a amd64
dart setup.dart install -p linux
flutter build linux

# macOS 见下方 universal 示例
flutter build macos
```

#### macOS Universal

macOS 需要分别构建两个架构，再由 `install` 合并：

```bash
dart setup.dart build -p macos -a arm64
dart setup.dart build -p macos -a x86_64
dart setup.dart install -p macos
flutter build macos --release
```

#### Linux AppImage

仓库提供了一个 Linux AppImage 打包脚本：

```bash
bash scripts/build_linux.sh <version>
```

#### 商店模式构建

如需构建不带自更新能力的商店版本：

```bash
flutter build ios --dart-define=STANDALONE=false
flutter build appbundle --dart-define=STANDALONE=false
```

### 分析与测试

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

当前仓库中有 `21` 个 Dart 测试文件，CI 还包含集成 smoke test 与发布矩阵构建。

---

## CI 与发布

CI 只在推送 tag 或手动 `workflow_dispatch` 时触发：

- `pre`：构建全平台预发布，覆盖上一个 pre-release，并刷新 `update-pre.json` manifest
- `vX.Y.Z`：构建全平台正式版，创建 GitHub Release，并刷新 `update.json` manifest
- `vX.Y.Z-pre` 同样视为 pre-release（`prerelease: true`）

`dev` / `master` 分支的 push 不会触发 `build.yml`，仅触发 `ci.yml`（analyze + test）。

### 发布流程

1. 所有代码先合入 `dev`，触发 `ci.yml`
2. 需要预发布时移动 `pre` tag：

   ```bash
   git tag -d pre && git push origin :refs/tags/pre
   git tag pre && git push origin pre
   ```

3. 正式版：`dev` → `master` 合入后再打 `vX.Y.Z` 并推送
4. CI 执行：应用 `core/patches/*.patch` → 构建 Go 核心 → `dart setup.dart install` → Flutter 打包 → 签名 / 归档 → 上传产物 → 创建 Release + manifest

发布矩阵覆盖 Android / iOS / macOS / Windows / Linux（仅 `linux-amd64.AppImage`）。产物由 CI 自动命名、附加 `.sha256`、刷新 release notes 与 updater manifest。

---

## 仓库结构

| 路径 | 作用 |
|------|------|
| `lib/modules/` | 业务模块：登录、首页、节点、商店、设置、Emby、模块运行时等 |
| `lib/core/` | 核心运行层：FFI、内核生命周期、系统代理、Service Mode、存储 |
| `lib/infrastructure/` | 数据源与仓储：XBoard API、mihomo REST / WebSocket |
| `lib/domain/` | 纯数据模型 |
| `lib/shared/` | 通用工具与 UI 辅助 |
| `lib/i18n/` | 双语文案与 slang 生成代码 |
| `core/` | Go 侧 mihomo 封装 |
| `service/` | 桌面特权 helper |
| `docs/` | 模块运行时与其它专题文档 |

---

## 常见问题

### 1. macOS 提示“无法打开”或“无法验证开发者”

使用 DMG 内附带的 `修复无法打开.command`，或执行：

```bash
sudo xattr -cr /Applications/YueLink.app
```

### 2. Android 安装在安全文件夹 / 第二用户后 VPN 无法工作

Android 的 `VpnService` 只能在主用户空间可靠工作。Samsung Secure Folder 等二级用户环境可能无法建立有效 TUN。

### 3. 模块运行时已经安装 Root CA，但某些 App 仍无法 MITM

这是 Android 用户 CA 信任限制和证书固定带来的已知边界，不是 YueLink 单独能绕过的问题。详见 [模块已知限制](docs/MODULE_RUNTIME_KNOWN_LIMITATIONS.md)。

### 4. 为什么某些构建不显示“检查更新”

这是商店模式构建的预期行为。`STANDALONE=false` 时，自更新逻辑会被关闭，以满足商店分发约束。

---

## 许可证

[MIT](LICENSE)
