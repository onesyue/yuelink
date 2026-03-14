# 悦通 · 官方客户端

**专为 AI 与流媒体打造的全球加速网络**

[![Build](https://github.com/onesyue/yuelink/actions/workflows/build.yml/badge.svg)](https://github.com/onesyue/yuelink/actions/workflows/build.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.27-blue)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows-lightgrey)]()

使用 [yue.to](https://yue.to) 账号登录即可自动同步订阅、连接节点。基于 Flutter + [mihomo](https://github.com/MetaCubeX/mihomo) (Clash.Meta) 内核构建。

---

## 下载

前往 [Releases](https://github.com/onesyue/yuelink/releases) 下载对应平台的安装包：

| 平台 | 文件 | 说明 |
|------|------|------|
| macOS | `YueLink-macOS.dmg` | Intel + Apple Silicon 通用包 |
| Windows | `YueLink-Windows-Setup.exe` | x64 安装程序 |
| Android | `YueLink-Android.apk` | 通用包（arm64 / arm / x86_64） |
| iOS | 见下方说明 | 需手动签名安装 |

---

## 安装说明

### macOS

1. 打开 `.dmg`，将 `YueLink.app` 拖入 `Applications` 文件夹
2. 首次打开时 macOS Gatekeeper 可能提示"无法验证开发者"
3. 在终端执行以下命令移除隔离属性，之后即可正常打开：

```bash
xattr -cr /Applications/YueLink.app
```

4. 再次双击 `YueLink.app` 即可启动

> 如果已购买 Developer ID 签名版本，直接双击打开无需上述步骤。

**系统要求：**
- macOS 12 Monterey 及以上
- 支持 Apple Silicon（M1 / M2 / M3 / M4 / M5）及 Intel，无需 Rosetta
- macOS 26 已验证兼容

---

### Windows

直接运行 `YueLink-Windows-Setup.exe` 安装，安装完成后从开始菜单或桌面快捷方式启动。

**系统要求：** Windows 10 1903 及以上（x64）

---

### Android

1. 在手机"设置 → 安全"中开启"允许安装未知来源应用"
2. 下载 `YueLink-Android.apk` 后直接安装
3. 首次启动时会申请 VPN 权限，点击"确定"即可

**系统要求：** Android 6.0 及以上

---

### iOS

iOS 版本需要通过以下方式之一安装：

- **AltStore / SideStore**：使用开发者证书自签安装（7 天有效期，到期重签）
- **企业证书分发**：联系悦通团队获取企业签版本
- **TestFlight**（内测）：受邀用户可通过 TestFlight 安装

**系统要求：**
- iOS 15 及以上
- iOS 18 / iOS 26 已验证兼容

---

## 使用方法

### 登录与订阅

1. 打开 App，输入 [yue.to](https://yue.to) 账号的邮箱和密码
2. 登录后自动下载订阅配置，无需手动填写订阅链接

### 四个主要页面

| 页面 | 功能 |
|------|------|
| **首页** | 一键连接 / 断开；查看出口 IP、实时流量图表、套餐概览、公告 |
| **线路** | 选择代理节点和代理组；切换路由模式（规则 / 全局 / 直连） |
| **商店** | 购买或续费套餐；输入优惠码；选择支付方式；查看订单历史 |
| **我的** | 查看账户信息、上传/下载流量、套餐剩余天数；同步订阅；Emby 入口 |

### 连接步骤

1. 在**首页**点击连接按钮
2. 如需切换节点，前往**线路**页面选择代理组和节点
3. 连接成功后首页显示出口 IP 和实时速率

### 续费 / 购买套餐

1. 前往**商店**选择套餐和周期
2. 可输入优惠码享受折扣
3. 选择支付方式后点击「前往支付」
4. 支付完成返回 App 后自动查询结果并同步订阅

> 如有未支付的待付款订单，可在商店 → 订单记录中找到对应订单继续支付，或取消后重新下单。

---

## 平台支持

| 平台 | 代理方式 | 最低版本 |
|------|---------|---------|
| Android | VpnService + TUN (gVisor) | Android 6.0 |
| iOS | NetworkExtension (PacketTunnel) | iOS 15 |
| macOS | System Proxy (networksetup) | macOS 12 |
| Windows | System Proxy (注册表) | Windows 10 |

---

## 从源码构建

### 环境要求

| 工具 | 版本 | 说明 |
|------|------|------|
| Flutter | >= 3.22 | CI 使用 3.27.4 |
| Dart | >= 3.4 | 随 Flutter 附带 |
| Go | >= 1.22 | 构建 mihomo 内核，CI 使用 1.23 |
| Xcode | >= 15 | iOS / macOS 构建 |
| Android NDK | r26+ | Android 构建 |

### 快速开始（无 Go 内核的 Mock 模式）

```bash
git clone --recursive https://github.com/onesyue/yuelink.git
cd yuelink
flutter pub get
flutter run        # 不需要 Go，UI 全功能可用
```

### 构建 Go 内核

```bash
# macOS — 构建通用二进制（Apple Silicon + Intel）
dart setup.dart build -p macos -a arm64
dart setup.dart build -p macos -a x86_64
dart setup.dart install -p macos
flutter run -d macos

# Android
dart setup.dart build -p android
dart setup.dart install -p android
flutter build apk

# Windows
dart setup.dart build -p windows
dart setup.dart install -p windows
flutter build windows

# iOS（需要 Xcode + 开发者证书）
dart setup.dart build -p ios
dart setup.dart install -p ios
flutter build ios
```

### 分析与测试

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

---

## 技术架构

```
Flutter UI (Dart + Riverpod)
    ↕ FFI（仅生命周期：init / start / stop）
mihomo Go 内核
    ↕ REST API :9090（代理数据、流量、连接）

XBoard Panel API (CloudFront)
    ↕ HTTPS
悦通账号系统（登录、套餐、订阅 URL、公告、Emby）
```

- `lib/modules/yue_auth/` — 登录、账号状态管理
- `lib/modules/mine/` — 我的页面（套餐、流量、快捷操作）
- `lib/modules/store/` — 商店（套餐购买、订单管理、支付）
- `lib/modules/announcements/` — 公告系统
- `lib/modules/emby/` — Emby 服务入口
- `lib/infrastructure/datasources/xboard_api.dart` — XBoard 面板 API 客户端
- `lib/core/` — FFI 绑定、CoreManager、平台 VPN、存储

---

## 标识符

| 字段 | 值 |
|------|-----|
| Bundle ID | `com.yueto.yuelink` |
| iOS App Group | `group.com.yueto.yuelink` |
| MethodChannel | `com.yueto.yuelink/vpn` |
| User-Agent | `clash.meta` |

---

## License

[MIT](LICENSE)
