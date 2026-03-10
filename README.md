# YueLink

**by [Yue.to](https://yue.to)**

[![Build](https://github.com/onesyue/yuelink/actions/workflows/build.yml/badge.svg)](https://github.com/onesyue/yuelink/actions/workflows/build.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.27-blue)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)

跨平台代理客户端，基于 Flutter + [mihomo](https://github.com/MetaCubeX/mihomo) (Clash.Meta) 内核。

## 平台支持

| 平台 | 代理方式 | 状态 |
|------|----------|------|
| Android | VpnService + TUN | ✅ |
| iOS | NetworkExtension (PacketTunnel) | ✅ |
| macOS | 系统代理 (networksetup) | ✅ |
| Windows | 系统代理 (注册表) | ✅ |

## 功能

- 订阅管理 — 添加 / 更新 / 自动刷新，解析流量与到期信息
- 代理节点 — 分组展示、搜索筛选、延迟排序、单节点 / 批量测速
- 连接监控 — 实时连接列表、搜索过滤、一键关闭
- 配置覆写 — 在订阅配置之上叠加自定义规则
- 代理提供者 — 查看与更新远程 proxy-provider
- WebDAV 同步 — 跨设备备份和恢复配置
- 分应用代理 — Android 黑白名单模式
- 亮色 / 暗色主题、中英文切换
- 开机自启、自动连接

## 快速开始

```bash
git clone --recursive https://github.com/onesyue/yuelink.git
cd yuelink
flutter pub get
flutter run   # Mock 模式，无需 Go 核心即可运行全部 UI
```

### 编译 Go 核心（可选）

```bash
dart setup.dart build -p macos -a arm64   # 或 android / ios / windows
dart setup.dart install -p macos
flutter run -d macos
```

## 架构

```
Flutter UI (Riverpod)
    ├── CoreController (dart:ffi) ──→ hub.go (CGO) ──→ mihomo engine
    │       生命周期: init / start / stop              ↕
    └── MihomoApi (REST :9090) ←───────────── mihomo HTTP API
            数据: proxies / traffic / connections      ↕
                                          Platform VPN (TUN / 系统代理)
```

FFI 仅负责核心生命周期管理，所有数据操作通过 REST API 完成。与 FlClash、Clash Verge Rev 架构一致。

- **iOS** — 静态库 (`c-archive`)，NetworkExtension 独立进程
- **其他平台** — 动态库 (`c-shared`)
- **Mock 模式** — Go 库不存在时自动降级为模拟数据，所有页面可完整交互

## 环境要求

| 工具 | 版本 | 说明 |
|------|------|------|
| Flutter | >= 3.22 | UI 框架 (CI: 3.27.4) |
| Dart | >= 3.4 | 随 Flutter 附带 |
| Go | >= 1.22 | 编译 mihomo 核心 (CI: 1.23)，Mock 模式下可选 |
| Android NDK | r26+ | Android 构建 |
| Xcode | >= 15 | iOS / macOS 构建 |

## 构建

```bash
# Go 核心
dart setup.dart build -p <platform> [-a <arch>]   # android|ios|macos|windows
dart setup.dart install -p <platform>
dart setup.dart clean

# Flutter
flutter build apk         # Android (fat universal)
flutter build ios          # iOS
flutter build macos        # macOS
flutter build windows      # Windows
```

CI 自动产出：`YueLink-Android.apk`、`YueLink-iOS.ipa`、`YueLink-macOS.dmg`、`YueLink-Windows-Setup.exe`。

## 测试

```bash
flutter test       # 78 个单元测试
flutter analyze    # 静态分析 (CI 使用 --no-fatal-infos --no-fatal-warnings)
```

## 项目结构

```
yuelink/
├── core/                  # Go 核心 (CGO //export → mihomo)
│   └── mihomo/            # mihomo 子模块
├── lib/
│   ├── ffi/               # dart:ffi 绑定 + CoreMock
│   ├── models/            # 数据模型
│   ├── providers/         # Riverpod 状态管理
│   ├── pages/             # UI 页面 (Dashboard / Nodes / Profile / Settings)
│   ├── services/          # MihomoApi / VpnService / CoreManager / SettingsService
│   ├── l10n/              # 中英文 i18n (手写 S 类)
│   └── theme.dart         # 设计系统 (YLColors / YLText / YLShadow)
├── android/               # VpnService TUN 实现
├── ios/                   # PacketTunnel NetworkExtension
├── macos/                 # macOS Runner
├── windows/               # Windows Runner + Inno Setup 安装脚本
├── setup.dart             # Go 核心编译工具
└── test/                  # 单元测试 (12 个测试文件)
```

## 标识

| 项目 | 值 |
|------|-----|
| Package ID | `com.yueto.yuelink` |
| App Group (iOS) | `group.com.yueto.yuelink` |
| MethodChannel | `com.yueto.yuelink/vpn` |
| 配置文件 | `yuelink.yaml` |
| User-Agent | `clash.meta` |

## 版本策略

- 开发阶段使用 `v0.0.1-alpha` 标签
- 正式发布时递增版本号（`v0.1.0`、`v1.0.0` 等）
- 推送 `v*` 标签触发 CI 全平台构建 + GitHub Release

## License

MIT
