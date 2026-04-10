# 悦通 · YueLink

**专为 AI 与流媒体打造的全球加速网络**

[![Build](https://github.com/onesyue/yuelink/actions/workflows/build.yml/badge.svg)](https://github.com/onesyue/yuelink/actions/workflows/build.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.41-blue)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-lightgrey)]()
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

使用 [yue.to](https://yue.to) 账号登录即可自动同步订阅、连接节点。基于 Flutter + [mihomo](https://github.com/MetaCubeX/mihomo) (Clash.Meta) 内核构建。

---

## 下载

前往 [Releases](https://github.com/onesyue/yuelink/releases) 下载对应平台的安装包：

| 平台 | 文件 | 说明 |
|------|------|------|
| Android | `YueLink-Android.apk` | 通用包（arm64 / arm / x86_64） |
| iOS | `YueLink-iOS.ipa` | TrollStore / AltStore / SideStore 侧载 |
| macOS | `YueLink-macOS.dmg` | Intel + Apple Silicon 通用包 |
| Windows | `YueLink-Windows-Setup.exe` | x64 安装程序 |
| Linux | `YueLink-Linux-x86_64.AppImage` | x64 AppImage |

---

## 安装说明

### Android

1. 在手机"设置 → 安全"中开启"允许安装未知来源应用"
2. 下载 `YueLink-Android.apk` 后直接安装
3. 首次启动时会申请 VPN 权限，点击"确定"即可

**系统要求：** Android 6.0 及以上

### iOS

通过以下方式安装 `.ipa`：

- **TrollStore**（推荐）：直接安装，永不过期
- **AltStore / SideStore**：自签安装（7 天有效期，到期重签）

**系统要求：** iOS 15 及以上（iOS 18 / iOS 26 已验证兼容）

### macOS

1. 打开 `.dmg`，将 `YueLink.app` 拖入 `Applications` 文件夹
2. 首次打开时若提示"无法打开"或"无法验证开发者"，有两种方式修复：
   - **方式一（推荐）**：双击 DMG 中的 `修复无法打开.command` 脚本，输入密码即可
   - **方式二**：在终端执行：
     ```bash
     sudo xattr -cr /Applications/YueLink.app
     ```

**系统要求：** macOS 12 Monterey 及以上（Apple Silicon + Intel，无需 Rosetta）

### Windows

运行 `YueLink-Windows-Setup.exe` 安装即可。

**系统要求：** Windows 10 1903 及以上（x64）

### Linux

```bash
chmod +x YueLink-Linux-x86_64.AppImage
./YueLink-Linux-x86_64.AppImage
```

---

## 功能概览

### 核心功能

| 页面 | 功能 |
|------|------|
| **首页** | 一键连接 / 断开；出口 IP 检测（AI 解锁标识）；实时流量图表；套餐概览；公告轮播；运营商检测 |
| **线路** | 选择代理节点和代理组；一键测速；按延迟 / 名称排序；收藏节点；场景模式；智能选择；切换路由模式（规则 / 全局 / 直连） |
| **商店** | 购买或续费套餐；优惠码验证；多种支付方式；订单历史与待支付订单管理 |
| **我的** | 账户信息、流量统计、设备在线数；每日签到（流量 / 余额奖励）；同步订阅；检查更新；连接修复工具 |

### 悦视频（Emby 媒体库）

Netflix 风格的流媒体体验：
- **首页 Hero Banner** — 16:9 大图推荐位 + 播放按钮，自动轮播
- **横向海报行** — 每个媒体库独立一行，自动隐藏空库
- **自适应分辨率** — 手机 180px / 平板 240px / 桌面 280px 海报，HiDPI 自动适配
- **原生播放器** — 倍速播放、字幕大小调节、音轨切换、播放进度自动记录与续播
- **STRM 搬运库支持** — 兼容 STRM 索引的 Video 类型
- **合集库支持** — Emby 4.9 boxsets 自动识别
- **全代理链路** — API 请求、视频流、字幕、图片全部通过代理节点访问

### 配置管理

- **订阅自动同步** — 登录后自动下载配置，后台每 30 分钟检查更新
- **批量导入/导出** — 多选 YAML 文件一次导入；导出为独立 `{名称}.yaml` 文件
- **配置覆写** — 自定义规则和设置叠加到订阅配置上
- **应用内更新** — 自动检测 GitHub 新版本，支持跳过版本
- **分应用代理** — Android 支持按应用白名单/黑名单分流

---

## 平台支持

| 平台 | 代理方式 | 最低版本 |
|------|---------|---------|
| Android | VpnService + TUN (gVisor) | Android 6.0 |
| iOS | NetworkExtension (PacketTunnel) | iOS 15 |
| macOS | System Proxy (networksetup) | macOS 12 |
| Windows | System Proxy (注册表) | Windows 10 |
| Linux | System Proxy | — |

---

## 从源码构建

### 环境要求

| 工具 | 版本 | 说明 |
|------|------|------|
| Flutter | >= 3.27 | CI 使用 3.41.5 |
| Dart | >= 3.6 | 随 Flutter 附带 |
| Go | >= 1.22 | 构建 mihomo 内核，CI 使用 1.23 |
| Xcode | >= 15 | iOS / macOS 构建 |
| Android NDK | r26+ | Android 构建 |

### 快速开始（Mock 模式，无需 Go）

```bash
git clone --recursive https://github.com/onesyue/yuelink.git
cd yuelink
flutter pub get
flutter run        # 不需要 Go 内核，UI 全功能可用
```

Mock 模式会模拟代理组、节点、流量和连接数据，适合 UI 开发调试。

### 构建 Go 内核

```bash
# macOS 通用二进制
dart setup.dart build -p macos -a arm64
dart setup.dart build -p macos -a x86_64
dart setup.dart install -p macos

# Android / Windows / iOS / Linux
dart setup.dart build -p <platform>
dart setup.dart install -p <platform>
flutter build apk|ios|macos|windows|linux
```

### 分析与测试

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test                          # 207 个单元测试
bash scripts/check_imports.sh         # 架构分层检查
```

---

## 技术架构

```
Flutter UI (Dart + Riverpod)
    ↕ FFI（仅生命周期：init / start / stop）
mihomo Go 内核
    ↕ REST API :9090（代理数据、流量、连接）
    ↕ WebSocket（实时流量 / 日志 / 内存监控）

XBoard Panel API (CloudFront + 直连 fallback)
    ↕ HTTPS
悦通账号系统（登录、套餐、订阅、公告、签到、Emby）
```

| 层 | 职责 |
|----|------|
| `lib/modules/` | 功能模块（auth、dashboard、nodes、store、emby、checkin、profiles 等 16 个模块） |
| `lib/infrastructure/` | API 客户端（XBoard、mihomo REST/WebSocket）、Repository |
| `lib/core/` | FFI 绑定、CoreManager 启动序列、VPN 服务、安全存储、配置模板引擎 |
| `lib/domain/` | 数据模型（proxy、traffic、connection、store、account 等） |
| `lib/providers/` | Riverpod 全局状态管理（core、proxy、profile、connectivity） |
| `lib/shared/` | 通用工具（i18n、格式化、通知、主题） |
| `core/` | Go mihomo 包装（CGO //export，8 个导出符号） |

### 核心启动序列

CoreManager 执行 8 个有序步骤，每步可观测、可诊断：

1. **ensureGeo** — GeoIP/GeoSite 数据文件就绪
2. **initCore** — FFI 初始化 Go 运行时
3. **vpnPermission** — 请求 VPN 权限（Android）
4. **startVpn** — 获取 TUN fd（Android）
5. **buildConfig** — 端口冲突检测 + 配置合并 + 模板处理
6. **startCore** — FFI 启动 mihomo 引擎
7. **waitApi** — 等待 REST API 就绪
8. **verify** — 运行状态 + API + DNS 诊断验证

启动失败时自动生成诊断报告（`startup_report.json`），含每步耗时、错误码和 Go 核心日志。

---

## 标识符

| 字段 | 值 |
|------|-----|
| Package | `com.yueto.yuelink` |
| iOS App Group | `group.com.yueto.yuelink` |
| MethodChannel | `com.yueto.yuelink/vpn` |
| User-Agent | `clash.meta` |

---

## License

[MIT](LICENSE)
