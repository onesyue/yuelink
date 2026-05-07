# YueLink 代理客户端全面治理方案 —— 综合最终版

调研日期：2026-05-07
基线：yuelink master @ 3b370c7（v1.1.20 已发布）
版本：v6（基于 v5 + 第二轮内审：dns_policy_catalog 抽取、Private DNS 语义严谨化、CMFA 复核已通过）
对照对象：OpenClash 0.47.088 + mihomo alpha 2026-04-08 / Clash Verge Rev 2.4.7 + mihomo v1.19.21 / Samsung CMFA（包名 com.github.metacubex.clash.meta）

> **数量口径**：本方案 P1–P4 共 **16 项** 落地任务（P1×6 + P2×3 + P3×2 + P4×5），第 7 节「明确不做」**14 项**，第 11 节「已落地清单」作为底盘参考避免重复造轮子。任何排期/路线偏移先回这一句话核对。

---

## 0. 实测结论（4 行）

* **OpenClash（路由）**：mihomo alpha 2026-04-08，rule 模式，fake-ip，DNS 由 dnsmasq → 127.0.0.1:7874，TCP redir-port 7892 + UDP tproxy 7895，规则/策略组完整。redirect/iptables 路径，**无 TUN**。
* **Win11 Verge Rev**：v2.4.7，verge-mihomo.exe，mixed-port 7897，TUN（Meta 网卡）+ 系统代理同时启用，`strict-route: false`，DNS listen :1053。
* **YueLink**：已有系统代理、桌面 TUN（含 IPv6 ULA + dns-hijack 双协议）、Service Mode、Wintun、Android VpnService（含公网 IP split-route + setHttpProxy + setMetered）、iOS PacketTunnel、DNS fake-ip 全套、ECH/Secure-DNS 智能路由、连通性 OEM 13 厂商覆盖、QUIC reject 三档、链式代理。
* **Samsung 手机**（置信度：✅ **已用户复核**，2026-05-07 用户确认 `/Users/beita/Library/Android/sdk/platform-tools/adb` 可用，设备 SM_G9860 在线）：CMFA 已装、tun0 已起，Private DNS **mode = `opportunistic`**（specifier = `1dot1dot1dot1.cloudflare-dns.com`）。包名 `com.github.metacubex.clash.meta` 不可 debuggable，run-as 拒绝读 profile YAML（profile 内容拿不到，但 mode/specifier/路由/包元数据可拿）。`opportunistic` ≠ "强切 Cloudflare"——只是 Android 在条件允许时**优先**尝试 DoT，TUN 接管后通常仍能拦下，详见 P3-1。

---

## 1. 落地顺序（P0 → P4，按依赖排）

```
P0  只读报告 + Samsung 补采集 ─┐
                              ├→ P1  DNS/规则（release a）─┐  ✅ 已发
                              │                            │
                              └→ P2  TUN/系统代理（release b）─┐
                                                               │
                                                               ├→ P3  移动端（release c）─┐
                                                               │                          │
                                                               └→ P4  诊断基建 + 文档（release D，持续）
```

每个 P 阶段独立可发，不互相阻塞代码 — 但**测试**互相依赖（P1 改 DNS 后 P2 的 TUN 切换路径要复测）。

---

## 2. P0 — 只读对比报告 + Samsung 补采集

### 2.1 只读对比报告（已完成 ✅）

本文档即是。10 项固定对比维度，全部脱敏（订阅 URL / 节点地址 / secret / token / UUID / Reality public-key / short-id 已在原始 OpenClash config 上确认存在但报告中不引用具体值）。

| 维度 | OpenClash | Verge Rev | CMFA | YueLink |
|------|-----------|-----------|------|---------|
| 系统代理 | n/a | TUN+系统代理双开 | n/a | 二选一（systemProxy / tun，移动总走 VPN） |
| TUN | 无（redirect 模式）| sing-tun via mihomo / strict-route:false | mihomo gvisor | mihomo gvisor + sing-tun，strict-route:true（Win），iOS NEPacketTunnel |
| DNS | fake-ip + nameserver-policy 显式 34 AI 域名 + geosite:cn + 银行/运营商 | fake-ip + nameserver-policy 部分 + listen:1053 | fake-ip 默认 + Private DNS 受影响 | fake-ip + ECH/Secure-DNS 智能路由 + 13 OEM 连通性 + Apple/iCloud policy（**待补 AI 域名 + geosite:cn + 国内银行**）|
| 规则 | 119 + 30+ rule-providers | 用户挂订阅决定 + rules.yaml 增强 | 订阅 | 订阅 + 14 连通性 + 5 ECH + QUIC reject + provider DIRECT |
| 直连/全局/规则模式 | 全 + script | 全 + script | 全 | rule（默认）+ global + direct（**不做 script** 防傻瓜化偏离）|
| 订阅 provider | 30+ blackmatrix7 | 用户配 | 用户配 | 沿用订阅 |
| 策略组 | 212 行 / 全自动+手动 | 用户挂订阅 | 用户挂订阅 | 沿用订阅 + 链式代理 + 上游 dialer-proxy |
| 依赖/包 | luci-app-openclash + sing-box + kmod-tun | Tauri + Wintun + sidecar | Android APK | Flutter + mihomo c-archive(iOS)/c-shared(Android)/cgo(desktop) + Wintun + service helper |
| 日志诊断 | logread + custom log.sh | sidecar/service log | logcat | StartupReport E002–E009 + core.log + crash.log + EventLog + RemoteReporter |
| 恢复能力 | watchdog 脚本 | proxy_guard | n/a | RecoveryManager + 1.5s 重试 + isReady() 二段提权探测 |

### 2.2 Samsung 补采集（**只读**，不动设备）

**必须用 `/Users/beita/Library/Android/sdk/platform-tools/adb`**（已确认在 USB 连接、device 状态）。

补采项（CMFA 不可 debuggable，下面是能拿的全部）：

```bash
ADB=/Users/beita/Library/Android/sdk/platform-tools/adb

# VPN 状态
$ADB shell dumpsys connectivity | grep -E "VPN|tun0|underlying|iface" | head -50

# Private DNS
$ADB shell settings get global private_dns_mode
$ADB shell settings get global private_dns_specifier

# CMFA 包元数据
$ADB shell dumpsys package com.github.metacubex.clash.meta | grep -E "versionName|versionCode|userId|targetSdk|firstInstall|lastUpdate"

# CMFA 运行时权限（重点：POST_NOTIFICATIONS / VPN）
$ADB shell dumpsys package com.github.metacubex.clash.meta | grep -E "permission.*granted"

# tun0 路由
$ADB shell ip addr show tun0
$ADB shell ip route show table all | grep -E "tun0|default"

# 系统 DNS resolver（看 fake-ip 是否被 Private DNS 干预）
$ADB shell getprop | grep -E "net.dns|net.tcp"
```

**拿不到的（debuggable=false 限制）**：
* CMFA 当前 profile YAML 文件内容
* CMFA 运行时 mihomo config（在 internal storage）
* 分应用规则的具体配置
* CMFA 日志文件

**方案**：拿不到 profile YAML 不影响治理 — yuelink 自己注入 mihomo config，不依赖 CMFA 怎么写。Private DNS / VPN 路由 / 包权限是关键，已可拿。

---

## 3. P1 — DNS / 规则对齐（release **a**）✅ 已发

**6 类文件，单 PR 可发**：

1. `lib/core/kernel/config/dns_policy_catalog.dart`（**新建**）— 公共 catalog，AI 域名 / 国内银行/运营商 / OEM 连通性 / ECH/Secure-DNS 等清单的**单一真源**。dns_transformer 和 rules_transformer 都从这里读，避免私有常量 + 测试访问问题。
2. `lib/core/kernel/config/dns_transformer.dart` — 主逻辑（含 P1-2a 前置去重 fix），AI / 银行 / 连通性域名清单全从 catalog 读
3. `lib/core/kernel/config/rules_transformer.dart` — 把私有常量 `_browserSecureDnsDomains`（测试不可访问）替换为从 catalog 读，与 DNS policy 完全同源
4. `assets/default_config.yaml` — fallback 模板同步评估（避免 transformer 行为与静态模板漂移）
5. `CLAUDE.md` — 第 70 行 MTU 注释加 **iOS only** 限定
6. `test/core/kernel/config/dns_transformer_test.dart` + `test/core/kernel/config/dns_policy_catalog_test.dart` + `test/goldens/dns/*.yaml` — 8 个测试 + golden 文件，包括"两边引用同一份 catalog"的零差异断言

> ⚠️ **关键前置坑**（P1-2/P1-4 不修就"看似做了实际没生效"）
>
> `dns_transformer.dart:429` 现行 `final existingFilter = dnsSection;` 然后 `existingFilter.contains(domain)` —— **拿整个 dns 段做 contains**。一旦 nameserver-policy 子段已含 `geosite:cn:` 或 `+.openai.com:`，注入 fake-ip-filter 时会误判已存在并跳过。**这不是假设：`assets/default_config.yaml:139` 就含 `geosite:cn:`，line 142 还有 `+.openai.com:`。**
>
> 同样的坑在 `_appendRelayFakeIpFilter`（line 466-498）：用 `dnsSection.contains('"$trimmed"')`，policy key 也用引号写域名时会撞。
>
> 修正：截 fake-ip-filter 子段（`fake-ip-filter:` 到下一个同级 key 或 EOF），只在子段内 contains。这是 **P1-2a**，是 **P1-2b/P1-4 能否真正生效的前提**。

### 3.1 改动清单

| ID | 项 | 改动位置 | 工作量 |
|----|----|---------|--------|
| **P1-1** | nameserver-policy 显式枚举 30+ AI 域名 → 海外 DoH（避免 geosite 滞后泄漏 AI 域名给 CN DoH）。**实现方式**：清单写到新文件 `dns_policy_catalog.dart::aiDomains`，dns_transformer 和 rules_transformer 都从这一份读。**不走** P1-2a 去重路径（注入到 nameserver-policy 子段，不是 fake-ip-filter 子段），但要同步 `default_config.yaml:135-150` | 新建 `dns_policy_catalog.dart` + `dns_transformer.dart:268-330` + `rules_transformer.dart` 改私有常量为 catalog 引用 + `default_config.yaml` | M（含 catalog 抽取 + 两处引用迁移）|
| **P1-2a** | **前置 fix**：fake-ip-filter 注入去重作用域改为只扫子段（`fake-ip-filter:` 到下一个同级 key 或 EOF），不再用整 dns 段 `contains`。同时修 `_appendRelayFakeIpFilter` 同款问题 | `dns_transformer.dart:417-443` + `dns_transformer.dart:460-498` | S（20 行 + golden test）|
| **P1-2b** | fake-ip-filter 追加 `"geosite:cn"`（**前置：P1-2a 必须先合**；防订阅 nameserver-policy 没覆盖的 CN 子域被 DST-PORT/IP-CIDR 规则误判）| `dns_transformer.dart:35-118` + `default_config.yaml:80-116` | XS（2 行 + 同步 yaml）|
| **P1-3** | `direct-nameserver-follow-policy: true`（mihomo 1.18+，让 DIRECT 流量也遵守 DNS policy，不走 direct-nameserver 的 alidns/doh.pub 泄露内网域名）| `dns_transformer.dart` 两路径 + `default_config.yaml`（如 fallback 没有则加）| XS（5 行）|
| **P1-4** | fake-ip-filter 加中国本土关键服务段（cmpassport / cmbchina / pingan / wosms / jegotrip / icitymobile / blzstatic / 10010 / 10099 / microdone / id6.me + 企业内网 _msDCS）。**前置：P1-2a** | `dns_transformer.dart:35-118` + `default_config.yaml:80-116` | S（25 行）|
| **P1-5** | 保持 `respect-rules: true` + `proxy-server-nameserver` 启动解析兜底（已有，仅加 test 覆盖）| 测试 | XS |
| **P1-6** | CLAUDE.md 第 70 行 `mtu: 1500` 加 **iOS only** 限定（防下次 LLM/contributor 误读 — Android+Desktop 实际 9000）| `CLAUDE.md` | XS |

注：P1-2 拆成 a / b 两步是为了让 review 一眼看清"先修 bug 才能加内容"。**同一个 PR 提交**，但 commit 分开（先 P1-2a fix + golden test，后 P1-2b 加内容），方便 cherry-pick / revert。改动总数仍记 P1 = 6 项。

### 3.2 测试覆盖（**重点**）

新增测试组（`test/core/kernel/config/dns_transformer_test.dart`）：

| 测试 | 目标 |
|------|------|
| YAML validity | 注入后 `loadYaml()` 不抛异常 |
| 幂等性 | 同一份 config 注入 N 次 = 注入 1 次 |
| 不重复插入（fake-ip-filter）| **fixture 用 default_config.yaml 实状态**：`nameserver-policy` 子段已含 `geosite:cn:` 时，注入 `geosite:cn` 到 fake-ip-filter **必须仍然成功**（验 P1-2a 去重作用域修对了）|
| 不重复插入（nameserver-policy）| 已含 AI 域名 → 跳过 |
| 不覆盖订阅 | 订阅自带 `nameserver-policy` block-style → 仅追加 `geosite:geolocation-!cn` 兜底，不动其它 |
| 不覆盖订阅 flow-style | 订阅自带 `nameserver-policy: { 'a': [...] }` flow style → 在 `{` 后插入兜底，不破坏语法 |
| 缩进检测 | 订阅用 2/4/6 空格缩进各一份 fixture，注入后缩进对齐 |
| direct-nameserver-follow-policy 不重复 | 订阅已有 `direct-nameserver-follow-policy: false` → 不注入（用户/订阅明确意愿优先）|
| AI 域名清单单一真源 | `dns_transformer` 和 `rules_transformer` 都从 `dns_policy_catalog.dart::aiDomains` 读取（断言两边引用同一 const，diff = 空）。**不再依赖**测试访问私有常量 |
| fallback 模板同步 | `assets/default_config.yaml` 过完 `ConfigTemplate.process()` 后再过一次 = 第一次的产出（验 default_config 与 transformer 行为一致，无 drift）|

### 3.3 验证（发版前）

| 验证 | 方法 |
|------|------|
| dnsleaktest.com | 结果中**不应**出现 AliDNS / 腾讯 DoH IP（验 P1-1 / P1-3）|
| ChatGPT / Claude 连续 10 次刷新 | 无 "Just a moment" 挑战（验 ECH 路由没回归）|
| Cursor / Codeium / Cline | 不被识别成 CN 出口（验 P1-1 AI 域名）|
| 国内 App（按 memory `feedback_yuelink_platform_priorities` Android 优先）| 手机银行 / 12306 / 移动认证 cmpassport / 滴滴 / 携程冷启动登录（验 P1-4）|

---

## 4. P2 — TUN / 系统代理治理（release **b**）

### 4.1 决策性选择（不学 Verge）

* **不默认 "TUN + 系统代理双开"**：yuelink 继续二选一。理由：
  * 双开下 DNS 解析路径不唯一（系统代理走 mixed-port，TUN 走 dns-hijack），出问题排查困难
  * 用户简单 — 一次只一个选项，行为可预测
  * Verge Rev 双开是高级用户场景，与 yuelink 傻瓜化定位冲突

* **Windows `strict-route` 默认仍 `true`**：保留更严的安全默认。
  * Verge Rev 默认 `false` 是 LAN 友好，但有路由 leak 风险
  * yuelink 选 strict 是有意取舍

### 4.2 改动清单（开工顺序：**P2-2 → P2-1 → P2-3**）

> **顺序原因**：P2-2 抽公共 `buildTunSection(...)`，P2-1 的 `lanCompatMode` 直接成为该 builder 的参数。先做 P2-1 会先改一遍硬编码再被 P2-2 重构掉。

| ID | 项 | 文件 | 工作量 |
|----|----|------|--------|
| **P2-2**（先）| TUN **热切换** 与启动配置一致性。热切换实际入口是 `lib/core/managers/core_lifecycle_manager.dart:466` `hotSwitchConnectionMode` → `patchConfig({'tun': ...})`，那里直接拼简化版 TUN 段，**缺 `inet6-address` / `dns-hijack 双协议` / `route-exclude-address`**；冷启动走 `TunTransformer.ensureDesktopTun` 是完整的，长期分裂。重构：抽 `buildTunSection({stack, bypassAddresses, bypassProcesses, lanCompatMode, ...})` 纯函数，热切换 + 冷启动共享 | `core_lifecycle_manager.dart:466` patch 路径调 `buildTunSection` + `tun_transformer.dart` 抽 builder | M |
| **P2-1**（后）| Windows "局域网兼容模式" 高级开关（默认 OFF，开启后等价 `strict-route: false`，方便 NAS / 共享文件夹 / 远程桌面到内网 / 网络打印机）。**transformer 保持纯函数** —— 不直接读 `SettingsService`，从 provider/CoreManager 把 `windowsLanCompatibilityMode` 经 `ConfigTemplate.process(...)` 透传给 `TunTransformer.ensureDesktopTun(..., lanCompatMode)`（同一参数喂给 P2-2 抽出的 builder）| `settings_service.dart` 加 setting + `settings_providers.dart` provider + `core_manager.dart` 读取并透传 + `config_template.dart::process(...)` 加参数 + `tun_transformer.dart` builder 接参数 + `lib/modules/settings/` UI | M |
| **P2-3**（实验任务）| sniffer `parse-pure-ip + force-dns-mapping` 重测台架。OpenClash + Verge Rev 都开，yuelink 因 v1.0.21 30% 回归（32→20 MB/s）关闭。**结果分两路交付**：<br>(a) 回归 ≤ 5% → 改 `static_sections_transformer.dart:27` 启用 + golden regen + 注释更新历史<br>(b) 回归仍 > 5% → **不改代码**，交付 `governance/sniffer-pure-ip-benchmark-<date>.md` 含数据 + 决策"维持 false"<br>**预设结果可能是 (b)** —— 这是实验任务，不是必落代码 | benchmark 脚本 + `static_sections_transformer.dart:27`（条件改）+ governance 文档 | M |

### 4.3 Windows 检查项（实施 P2-1/P2-2 时一并验证）

| 检查 | 命令 / 方法 |
|------|------------|
| Wintun 驱动加载 | `pnputil /enum-drivers` 看 `wintun.inf` |
| Meta / YueLink 网卡存在 | `Get-NetAdapter \| Where-Object Name -match "Meta\|YueLink"` |
| 默认路由指向 TUN | `route print 0.0.0.0` 看 metric / interface |
| 系统 DNS 指向 TUN | `Get-DnsClientServerAddress` 看 NIC 0 的 server |
| Firewall 不阻断 TUN | `Get-NetFirewallProfile` |
| 系统代理无残留 | `Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" \| Select ProxyEnable, ProxyServer` |
| Service Mode helper 存在且 isReady | `sc query YueLinkServiceHelper` + ping helper IPC |
| mihomo external-controller 响应 | `curl http://127.0.0.1:9090/configs` |
| Wi-Fi/Ethernet underlying | `route print` 看默认路由 metric |

输出：单条 PowerShell 脚本，dump 上面 8 项到一份 markdown 报告（接 P4.2 一键诊断）。

### 4.4 测试

| 测试 | 目标 | 层级 |
|------|------|------|
| TUN 热切换 vs 重启一致 | 启动后切到 systemProxy，再切回 TUN — 切换后 mihomo config 与初次启动 TUN 完全一致（diff = 空）| `CoreLifecycleManager.hotSwitchConnectionMode` 集成测试 + `buildTunSection` 单测 |
| LAN 兼容模式 OFF | `strict-route: true` 出现在最终 mihomo YAML | **`ConfigTemplate.process` 端到端** —— 验 setting → provider → process → 最终 YAML，防"参数没透传到底"漏 |
| LAN 兼容模式 ON | `strict-route: false`，但 IPv6 ULA 仍存在 | 同上 `ConfigTemplate.process` 端到端 |
| LAN 兼容模式 — transformer 纯函数 | `TunTransformer.ensureDesktopTun(..., lanCompatMode: bool)` 单测，验明无 `SettingsService` 依赖 | transformer 单测 |
| Wintun 缺失 | TUN 启动失败时返回 E004 + 提示安装驱动 | E2E |
| Service Mode 不健康 | helper 死掉时 `isReady()` 返回 false，UI 提示重装 | E2E |

---

## 5. P3 — 移动端治理（release **c**）

### 5.1 Android（保留 + 加 UI 提示）

* **保留**当前 `PUBLIC_IPV4_ROUTES` 公网 IPv4 split-route — 不照搬 CMFA 的全默认路由（CMFA 是 0.0.0.0/0 全塞）。yuelink 现状对 LAN/NAS/投屏更友好，是优势。
* **新增 P3-1**：Android Private DNS **按 mode 分级**处理（**不是统一强提示**）。
  * Android Private DNS 三种 mode 语义：
    * `off` — 完全关闭，无影响
    * `opportunistic`（默认 / 三星实测此项）— 系统**优先**尝试 DoT，但 yuelink TUN 抢先接管 53 端口时通常仍能拦下；**不强提示**，仅在诊断输出（P4-1）记录 mode + specifier
    * `hostname` — 用户**明确**指定 DoT 服务器，Android 总是强切，**会真的绕过 TUN dns-hijack**
  * 改动模型：**Dart 主动拉，不是 native 推**。MethodChannel 暴露 `getPrivateDnsState()` 返回 `{mode, specifier}`，Dart 在 `app launch / app resumed / VPN connected` 三个事件主动 invoke 一次。native 端 `logPrivateDnsState` 保留 logcat 做诊断。
  * Dashboard banner **仅在 `mode == hostname` 时**显示："系统已开启 Private DNS（hostname 模式 → `<specifier>`），将绕过 yuelink DNS 分流，建议改为 Off 或 Automatic"。`opportunistic` 不显示 banner，只在「连接信息」页 / 一键诊断（P4-1）里显示信息。
  * 不用 push 模型的原因：native 主动推需要持续状态机管理（订阅/反订阅/重发/丢消息恢复）；Dart 主动拉简单可控，三个触发点已覆盖所有用户感知场景，且失败可见。

| ID | 项 | 文件 | 工作量 |
|----|----|------|--------|
| **P3-1** | Android Private DNS getter MethodChannel + Dart 三事件主动拉 + Dashboard banner（仅 hostname 触发）+ 诊断信息（opportunistic 落 P4-1）| `YueLinkVpnService.kt` 暴露 `getPrivateDnsState` MethodChannel handler + `lib/core/system/private_dns_state.dart`（新建：拉取 + lifecycle/VPN-event listener）+ `lib/modules/dashboard/widgets/private_dns_banner.dart`（新建）| S |

### 5.2 iOS（补 LAN 排除）

| ID | 项 | 文件 | 工作量 |
|----|----|------|--------|
| **P3-2** | PacketTunnelProvider 加 `excludedRoutes`（10/8、127/8、169.254/16、172.16/12、192.168/16、224/4、255.255.255.255）— 与 Android `PUBLIC_IPV4_ROUTES` 已经做的 split-route 拉齐 | `ios/PacketTunnel/PacketTunnelProvider.swift:46` | S（10 行 Swift）|

> ⚠️ **合并门槛（release c 不可豁免）**：iOS 实机回归是 P3-2 合并的**硬门槛**。Apple 生态（AirPlay / HomeKit / AirDrop / Continuity / Sidecar）的回归无法靠单测发现，下面 6 项**全部 PASS** 才能合 release c。

**实机回归**（c 合并门槛，**必做**）：

* iPhone + Apple TV：AirPlay 投屏不卡（不再走 mihomo TUN）
* iPhone + HomePod：HomeKit 控制延迟回归正常
* iPhone + AirDrop：与 Mac 互传不超时
* iPhone + 群晖：Synology Drive 局域网 LAN 速度
* iPhone + 路由器：管理界面 192.168.x.1 直访
* iPhone + Mac：Continuity / Universal Clipboard / Sidecar 仍工作

---

## 6. P4 — 依赖 / 诊断 / 文档（release **D**，持续）

### 6.0 D 子项优先级（**先 P4-2 / P4-3 撑住 b**）

D 不按编号顺序做，而按"对前序 release 的支撑价值"排：

| 顺序 | 子项 | 对前序的支撑作用 |
|------|------|------------------|
| **D-① P4-2** | Windows 诊断 PowerShell 脚本生成器 | 立刻服务 release b 的 § 4.3 八项 Windows 检查；最小成本，先做就赚 |
| **D-② P4-3** | mihomo 跟版 cadence governance | 给 P2-3 sniffer 台架定 mihomo 基线 SHA，benchmark 才有可对照基准 |
| **D-③ P4-1** | 一键诊断报告 | 用户排错主力，需 c.P3-1 完成才能加 Private DNS 板块 |
| **D-④ P4-4** | Dashboard 连通性体检 | 与 D-③ 互补的主动排错入口 |
| **D-⑤ P4-5** | 桌面 auto-light-weight 节能 | 最后做。范围偏 UX/生命周期，容易牵出窗口状态/Tray/进程残留问题，放最稳定的版本周期处理 |

### 6.1 OpenWrt 路径不照搬

OpenClash 用 dnsmasq + iptables + tproxy/redir，是**透明代理**设计 —— 路由器场景独有，**不搬到桌面客户端**。yuelink 桌面继续走 TUN + 系统代理两条路径，与 Verge Rev / CMFA 同语义。

### 6.2 一键诊断输出

用户排错时一键导出（增强现有 `LogExportService`）：

| 板块 | 内容 |
|------|------|
| 模式 | connectionMode（systemProxy / tun） + 实际生效 |
| 核心版本 | mihomo version（编译日期 + Go 版本）|
| 端口 | mixed-port + apiPort + 实际监听 |
| DNS | nameserver / direct-nameserver / fallback 全 dump（脱敏 secret）+ fake-ip-filter 数 |
| 路由 | TUN 网卡是否存在 + 默认路由 + IPv6 ULA + DNS 指向 |
| 规则命中 | mihomo `/connections` 最近 50 条规则命中分布 |
| 系统代理 | OS 各 NIC 当前代理设置（macOS networksetup / Win 注册表 / Linux dbus）|
| TUN 网卡 | Wintun（Win）/ utun（macOS+iOS）/ tun0（Android）状态 + IP + MTU |
| 泄漏测试 | 调 dnsleaktest 标准 / extended JSON API + 连通性 8 站点 |
| Private DNS | Android only：mode + specifier |
| Service Mode | helper 存在 / isInstalled / isReady（已有的二段探测分别 dump）|

| ID | 项 | 文件 | 工作量 |
|----|----|------|--------|
| **P4-1** | 一键诊断报告（合并到现有 `LogExportService`）| `lib/shared/log_export_service.dart` + 各 manager 加 `dumpStatus()` | M |
| **P4-2** | Windows 诊断 PowerShell 脚本生成器（在 yuelink 内集成，用户复制粘贴执行）| 新文件 + 设置 UI 入口 | S |

### 6.3 mihomo 跟版 cadence

实测 mihomo 版本：

| 客户端 | mihomo 版本 | 编译日期 | 通道 |
|--------|------------|---------|------|
| OpenClash 路由 | alpha-gd801e6b | 2026-04-08 | alpha |
| Verge Rev Win | v1.19.21 stable | 2025-03-09 | stable |
| yuelink fork | Meta（rolling）+ 3 commits | 取决于上次 bump | Meta（≈ stable）|

CLAUDE.md 已写跟版 SOP 但**没定期触发机制**。

| ID | 项 | 文件 | 工作量 |
|----|----|------|--------|
| **P4-3** | mihomo 月度跟版 governance（每月第一周手动 `git fetch upstream && git rebase upstream/Meta main`，三个 yuelink commit 自动 replay；release 前必跑 P2-3 sniffer 台架）| `governance/mihomo-bump-cadence.md` 新建 | XS |

**Alpha 不进主线**（memory `feedback_no_mihomo_alpha` 锁定）。

### 6.4 Dashboard 连通性体检（用户排错）

Verge Rev 内置 4 个 test_list（Apple/GitHub/Google/YouTube），yuelink 当前 Dashboard 只有"出口 IP"卡。

| ID | 项 | 文件 | 工作量 |
|----|----|------|--------|
| **P4-4** | Dashboard 连通性体检卡（generate_204 探测 6 站点：Apple / GitHub / Google / YouTube / Cloudflare / Anthropic）| `lib/modules/dashboard/widgets/connectivity_test_card.dart` | M |

### 6.5 桌面节能（可选）

| ID | 项 | 文件 | 工作量 |
|----|----|------|--------|
| **P4-5** | 桌面 auto-light-weight（系统托盘后台 N 分钟后释放 webview，保留 Tray + mihomo 进程）| `closeBehaviorProvider` 旁加 `lightWeightAfterMinutesProvider` + `WidgetsBinding.deferFirstFrame()` + Tab content 卸载 | M |

---

## 7. 明确不做（防被对照组牵着走）

| 项 | 谁有 | 为什么不做 |
|----|------|-----------|
| 切 alpha mihomo 内核 | OpenClash | memory `feedback_no_mihomo_alpha` 锁稳定，OpenClash 跑 alpha 不是参考 |
| enhanced-script（Merge.yaml + Script.js）| Verge Rev | 与 yuelink 傻瓜化定位冲突 |
| 多订阅独立 5 类增强文件 | Verge Rev | 同上，重度用户专属 |
| TUN + 系统代理双开（Win 默认）| Verge Rev 默认 | yuelink 二选一是有意设计，避双路径排障困难 |
| Win 默认 `strict-route: false` | Verge Rev | yuelink 选 strict 是有意取舍，给开关但默认不变（P2-1）|
| DNS listen `:53` / `:1053` 暴露 | OpenClash + Verge Rev | yuelink 不是路由器/服务器场景 |
| iOS MTU 改 9000 | Android+Desktop 已 9000 | `PacketTunnelProvider.swift:50-55` 注释明确"iOS upstream sockets 1500-bound, 9000 doesn't help" — 历史经验有据 |
| PAC 文件支持 | Verge Rev | 高级用户专属 |
| 自动备份配置 | Verge Rev | 订阅是源头，本地无需备份 |
| `mode: script` | OpenClash + Verge Rev | 与傻瓜化定位冲突 |
| rules prepend/append/delete UI | Verge Rev | 同上 |
| OpenWrt dnsmasq + iptables + tproxy 透明代理路径 | OpenClash | 路由器场景独有，桌面不抄 |
| Android 全默认 0.0.0.0/0 路由 | CMFA 默认 | yuelink 公网 IP split-route 更保 LAN/NAS，**保留** |
| CMFA 同版本对齐 | n/a | yuelink 有自己 fork + 3 commit，不为对齐而对齐 |

---

## 8. 实施时间线

```
a (本周, ✅ 已发)   P1（DNS/规则）+ 测试覆盖 + CLAUDE.md
            ├─ P1-1  AI 域名 nameserver-policy
            ├─ P1-2  geosite:cn fake-ip-filter
            ├─ P1-3  direct-nameserver-follow-policy
            ├─ P1-4  国内银行/运营商/企业内网 fake-ip-filter
            ├─ P1-5  test 覆盖（YAML / 幂等 / 不覆盖订阅 / 缩进）
            └─ P1-6  CLAUDE.md MTU 注释修订（iOS only）

b (下个 sprint)    P2（TUN/系统代理） — 内部顺序：P2-2 → P2-1 → P2-3
            ├─ P2-2 (先)  TUN 热切换 vs 启动一致性 — 抽 buildTunSection 纯函数
            │             入口：lib/core/managers/core_lifecycle_manager.dart:466
            ├─ P2-1 (后)  Windows LAN 兼容模式开关 — lanCompatMode 作为 P2-2 builder 参数
            │             transformer 保持纯函数（不读 SettingsService）
            └─ P2-3 (实验) sniffer parse-pure-ip 台架重测
                          交付物分两路：(a) ≤5% 回归→落代码；(b) >5%→benchmark 文档+保持 false

c (下下 sprint)    P3（移动端 LAN）
            ├─ P3-1  Android Private DNS — Dart 主动拉（不是 native push）
            │         触发点：app launch / app resumed / VPN connected
            │         banner 仅 hostname mode 显示
            └─ P3-2  iOS PacketTunnel excludedRoutes
                     ⚠️ 合并门槛：6 项 Apple 生态实机回归全 PASS

D (持续)        P4（诊断 + 文档 + UX） — 优先级 D-① ~ D-⑤
            ├─ D-① P4-2  Windows 诊断 PowerShell 生成器 — 撑 b 的 § 4.3
            ├─ D-② P4-3  mihomo 月度跟版 governance — 给 P2-3 定基线
            ├─ D-③ P4-1  一键诊断报告 — 需 c.P3-1 完成（Private DNS 板块）
            ├─ D-④ P4-4  Dashboard 连通性体检卡（6 站点）
            └─ D-⑤ P4-5  桌面 auto-light-weight 节能 — 最后做（窗口/Tray 风险）
```

---

## 9. 验证 / 发版门槛

### 9.1 release a 发版前 ✅ 已通过

* [ ] `flutter test` 207 + 新增 8 个 DNS transformer test 全过
* [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` 0 warning
* [ ] `bash scripts/check_imports.sh` 通过
* [ ] dnsleaktest.com — 不应出现 AliDNS / 腾讯 DoH IP
* [ ] ChatGPT / Claude 10 次刷新无挑战
* [ ] 国内 App 安卓回归（手机银行 / 12306 / 移动认证 / 滴滴）
* [ ] 海外 AI 直访（cursor / claude / ChatGPT / Gemini / Sora）

### 9.2 release b 发版前

* [ ] TUN 热切换 vs 重启一致性测试通过（diff = 空）
* [ ] Windows LAN 兼容模式 ON：内网共享 / 远程桌面 / 打印机可见
* [ ] Windows LAN 兼容模式 OFF：行为与 release a 一致
* [ ] sniffer 台架：parse-pure-ip 启用后 throughput 回归 ≤ 5%
* [ ] Windows 诊断输出 8 项全部显示

### 9.3 release c 发版前

* [ ] iPhone AirPlay 投屏 / HomeKit / AirDrop / 群晖 / 路由管理界面 全部回归（**必做实机**）
* [ ] Android Private DNS banner 在 hostname 模式触发，Off / Automatic 不触发
* [ ] iOS Continuity / Universal Clipboard / Sidecar 不受影响

---

## 10. 一手数据来源

* OpenClash：`/etc/openclash/config.yaml`（4500+ 行）、`/etc/openclash/custom/*.list`、`uci show openclash`、`/var/etc/dnsmasq.conf.cfg01411c`
* Verge Rev：`%APPDATA%/io.github.clash-verge-rev.clash-verge-rev/{verge.yaml, dns_config.yaml, profiles.yaml, profiles/}`、注册表系统代理、`route print`、进程列表
* CMFA Samsung：`adb shell pm list / dumpsys connectivity / dumpsys package / ip addr / settings get global private_dns_*`（`/Users/beita/Library/Android/sdk/platform-tools/adb`）
* YueLink 关键文件：
  * `lib/constants.dart:34` — defaultTunMtu = 9000
  * `lib/core/kernel/config_template.dart`（582 行）+ `config/*.dart` 7 个 transformer
  * `android/app/src/main/kotlin/com/yueto/yuelink/YueLinkVpnService.kt` — PUBLIC_IPV4_ROUTES + setHttpProxy + setMetered + logPrivateDnsState
  * `ios/PacketTunnel/PacketTunnelProvider.swift` — iOS MTU 1500（故意）+ includedRoutes default
  * `lib/core/managers/system_proxy_manager.dart` — verify cache + macOS 全网络服务覆盖
  * `lib/core/kernel/desktop_service_mode.dart` — 提权边界 isReady() 二段探测
* 文档参考：
  * mihomo wiki：https://wiki.metacubex.one/en/config/{dns,general,inbound/tun,rules}/
  * Clash Verge Rev：https://github.com/clash-verge-rev/clash-verge-rev
  * OpenClash：https://github.com/vernesong/OpenClash
  * MetaCubeX/mihomo Issues 1334、1567、1656、1729、1816、1842、1861、2545
  * gfw.report USENIX'23（DoT 853 RST 阻断结论）

---

## 11. 现状盘点（v3 已确认 yuelink 已落地，避免重复造轮子）

下面这些代码里**全部已经有**，只是 CLAUDE.md 个别注释 stale。新人/LLM 接手时先看这张表：

| 项 | 状态 | 关键代码位置 |
|----|------|-------------|
| TUN MTU = 9000（Android + Desktop）| ✅ | `lib/constants.dart:34` + `YueLinkVpnService.kt:24` |
| Android VPN 公网 IP split-route（46 条公网段绕 LAN）| ✅ | `YueLinkVpnService.kt:31-79 PUBLIC_IPV4_ROUTES` |
| Android VPN setHttpProxy + LAN 排除 | ✅ | `YueLinkVpnService.kt:82-104` |
| Android setMetered(false)（API Q+） | ✅ | `setMetered(false)` |
| Android setUnderlyingNetworks 跟 active | ✅ | `applyUnderlyingNetworks` + NetworkCallback |
| Android Wi-Fi/Cellular 切换 → fake-ip flush | ✅ | `onTransportChanged` 通知 Dart |
| Android Private DNS 状态日志 | ✅ | `logPrivateDnsState`（**待加 UI 提示，P3-1**）|
| Android 多用户限制（Samsung Secure Folder）| ✅ | CLAUDE.md 已记录验证方法 |
| iOS MTU = 1500（**故意**保守）| ✅ | `PacketTunnelProvider.swift:50-56`（注释明确解释为什么不跟 9000）|
| iOS DNS 全交给 Dart（避免双语言 drift）| ✅ | `PacketTunnelProvider.swift:131-142` |
| iOS App Group geo 文件每次启动同步 | ✅ | `AppDelegate.writeConfigToAppGroup` |
| iOS includedRoutes = default（**待加 excludedRoutes，P3-2**）| ⚠️ | `PacketTunnelProvider.swift:46` |
| 桌面 TUN IPv6 ULA + dns-hijack 双协议 | ✅ | `tun_transformer.dart` `fdfe:dcba:9876::1/126` + `tcp://any:53` |
| 桌面 service mode 提权边界 isReady | ✅ | `desktop_service_mode.dart` |
| 桌面 mode/Win strict-route（待加用户开关 P2-1）| ⚠️ | `tun_transformer.dart:81` 当前硬 true |
| ECH/Secure-DNS 5 域名智能路由 + AI 组定位 | ✅ | `rules_transformer.dart _browserSecureDnsDomains` |
| QUIC reject 三档（off/googlevideo/all）| ✅ | `rules_transformer.dart ensureQuicReject` |
| 13 OEM 厂商连通性 fake-ip-filter | ✅ | `dns_transformer.dart`（**待加 AI 域名 + geosite:cn + 国内银行 P1-1/P1-2/P1-4**）|
| 链式代理 + 上游 dialer-proxy | ✅ | `config_template.dart injectProxyChain / injectUpstreamProxy` |
| 8-step StartupReport + E002–E009 | ✅ | `startup_diagnostics.dart` |
| RecoveryManager.resetCoreToStopped 单点重置 | ✅ | `recovery_manager.dart` |
| port 冲突自动重映射（mixed-port + apiPort 各扫 20 端口）| ✅ | `core_manager.dart` |
| Telemetry opt-in + anonymous + PII redaction | ✅ | `lib/shared/telemetry.dart` |
| CloudFront fallback（订阅/API 502/503 自动重试）| ✅ | `_buildClient + fallbackUrl` |
| iOS TrollStore 越狱适配（ldid + executable name）| ✅ | `ios/PacketTunnel/Info.plist` |

**总结**：架构级缺口 = 0；待补 **16 项**（P1×6 + P2×3 + P3×2 + P4×5）全部是边角对齐 + UI/诊断增强 + 测试覆盖。其中**真正的技术坑**只有 1 个：`dns_transformer.dart:429` 的 fake-ip-filter 去重作用域（用整 dns 段 contains 会被 nameserver-policy 撞），由 P1-2a 修。其余 15 项都是增量内容/UI/文档/重测，无架构调整。
