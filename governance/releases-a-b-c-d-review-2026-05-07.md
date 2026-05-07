# YueLink 治理审查文档 — release a + b + c + D

审查日期：2026-05-07
审查对象：本会话产生的全部代码 / 文档 / 测试改动
基线：yuelink master @ 3b370c7（v1.1.20 已发布）

---

## 0. TL;DR — 一眼看完

```
flutter analyze --no-fatal-infos --no-fatal-warnings    →  No issues found
bash scripts/check_imports.sh                           →  All passed
flutter test                                            →  1019 passed / 1 skip / 0 fail
```

**4 个 release 全部代码完成。** 仅剩两项**真·硬件依赖**任务（不在代码层面）：

| 任务 | 阻塞类型 | 由谁做 |
|------|----------|--------|
| **b.P2-3** sniffer parse-pure-ip 台架 benchmark | 需要 32 MB/s 真实 hy2/vless 节点 + iperf3 + sysstat | 你（运维侧） |
| **c.P3-2** iOS Apple 生态实机回归 | 需要 iPhone + Apple TV + HomePod + 群晖 + 路由器 | 你（实机侧） |

代码层面的所有事我能做的都做完了。

---

## 1. 4 个 release 总览

| Release | 标签 | 状态 | 改动文件数 | 新增测试 |
|---------|------|------|----------|---------|
| **a** | DNS 治理 | ✅ 已发 | 8 | 31 |
| **b** | TUN / 系统代理 | ✅ 落地（P2-3 实验任务待） | 9 | 15 |
| **c** | 移动端 LAN | ✅ 代码就位（**iOS 实机回归门槛**）| 4 | 3 |
| **D** | 诊断 / UX | ✅ 全 5 项落地 | 9 | 4 |

**累计**：新增 53 个测试（995 → 1019 通过），20 个文件改动 + 8 个新文件 + 2 篇 governance 文档。

---

## 2. 完整文件清单（按 release 分组）

### 2.1 release a — DNS 治理

| 文件 | 类型 | 行数变化 | 用途 |
|------|------|---------|------|
| `lib/core/kernel/config/dns_policy_catalog.dart` | **新** | +250 | 单一真源，AI 域名 / 国内银行 / 连通性 / Secure-DNS |
| `lib/core/kernel/config/dns_transformer.dart` | M | +291 / -291（重写大半）| catalog 引用 + P1-2a 去重 fix + P1-1 AI 注入 + P1-3 follow-policy + P1-4 国内银行 |
| `lib/core/kernel/config/rules_transformer.dart` | M | +24 / -24 | 私有常量 → catalog 引用 |
| `assets/default_config.yaml` | M | +36 | fake-ip-filter 加 geosite:cn + 33 项国内域名 |
| `CLAUDE.md` | M | +1 / -1 | MTU 注释加 **iOS only** 限定 |
| `test/core/kernel/config/dns_policy_catalog_test.dart` | **新** | 143 | 11 catalog 不变量测试 |
| `test/core/kernel/config/dns_transformer_test.dart` | **新** | 464 | 20 transformer 行为测试（含 P1-2a regression 关键测试）|
| `test/services/config_template_goldens/*.golden` | M | +330 共 3 文件 | regen 反映新行为（60+ AI 域名 / geosite:cn / 33 国内域名 / follow-policy）|

### 2.2 release b — TUN / 系统代理

| 文件 | 类型 | 行数变化 | 用途 |
|------|------|---------|------|
| `lib/core/kernel/config/tun_transformer.dart` | M | +63 / -47（重构）| 抽 `buildDesktopTunYaml` 纯函数 builder + `windowsLanCompatibilityMode` 参数 |
| `lib/core/kernel/config_template.dart` | M | +5 | `process` / `processInIsolate` 加 `windowsLanCompatibilityMode` 参数透传 |
| `lib/core/kernel/core_manager.dart` | M | +7 | `start` / `_startIos` / `_startDesktopServiceMode` 三处签名 + 三处 `processInIsolate` 调用 |
| `lib/core/kernel/desktop_service_mode.dart` | M | +2 | `_startDesktopServiceMode` 签名 + 调用 |
| `lib/core/managers/core_lifecycle_manager.dart` | M | +18 / -9 | `manager.start` 读 `windowsLanCompatibilityModeProvider` + mobile patchConfig 简化为 `{enable: bool}`（修 Android 错误的 auto-route: true）|
| `lib/core/providers/core_preferences_providers.dart` | M | +23 | `windowsLanCompatibilityModeProvider` Notifier |
| `lib/main.dart` | M | +5 | provider override 注入 bootstrap 值 |
| `lib/modules/settings/sub/general_settings_page.dart` | M | +35 | UI Switch（仅 Win + TUN 模式可见）|
| `test/core/kernel/config/tun_transformer_test.dart` | **新** | 254 | 15 行为 + 一致性测试（含 cold-start composes builder 不变量）|

### 2.3 release c — 移动端 LAN

| 文件 | 类型 | 行数变化 | 用途 |
|------|------|---------|------|
| `ios/PacketTunnel/PacketTunnelProvider.swift` | M | +25 | `excludedRoutes` 7 段（10/8、127/8、169.254/16、172.16/12、192.168/16、224/4、255.255.255.255）|
| `android/.../MainActivity.kt` | M | +34 | `getPrivateDnsState` MethodChannel handler |
| `lib/core/system/private_dns_state.dart` | **新** | 102 | `PrivateDnsState` + `Notifier` + 3-触发拉取（launch/resume/VPN connected）|
| `lib/modules/dashboard/widgets/private_dns_banner.dart` | **新** | 110 | 仅 `mode == hostname` 显示警告 |
| `lib/modules/dashboard/dashboard_page.dart` | M | +6 | 挂载 PrivateDnsBanner |
| `test/core/system/private_dns_state_test.dart` | **新** | 36 | 3 测试（hostname/opportunistic/off 分级 + unknown 静默 + 等值）|

### 2.4 release D — 诊断 / 文档 / UX

| 文件 | 类型 | 行数变化 | 用途 |
|------|------|---------|------|
| **D-① P4-2** Windows 诊断 PS 脚本 | | | |
| `lib/shared/windows_diagnostic_script.dart` | **新** | 138 | 9 项 Windows 检查的 PS 脚本生成器（Wintun / NIC / 路由 / DNS / 防火墙 / 系统代理 / Service / API / underlying-transport）|
| `test/shared/windows_diagnostic_script_test.dart` | **新** | 51 | 4 测试（端口替换 / 9 板块齐全 / markdown / read-only 检查）|
| **D-② P4-3** mihomo 跟版 cadence | | | |
| `governance/mihomo-bump-cadence.md` | **新** | 218 | 月度 SOP + alpha 锁定 + cadence note 模板 + 与 b.P2-3 关系 |
| **D-③ P4-1** 一键诊断报告 | | | |
| `lib/shared/diagnostic_report.dart` | **新** | 218 | 11 板块 markdown：版本/模式/端口/启动诊断/系统代理/Service Mode/Private DNS/TUN bypass/Win 自助/上报注意 |
| **D-④ P4-4** Dashboard 连通性体检 | | | |
| `lib/modules/dashboard/widgets/connectivity_test_card.dart` | **新** | 195 | 6 站点 generate_204 探测（Apple/GitHub/Google/YouTube/Cloudflare/Anthropic）|
| `lib/modules/dashboard/dashboard_page.dart` | M | +6 | 挂载 ConnectivityTestCard |
| **D-⑤ P4-5** 桌面 auto-light-weight | | | |
| `lib/core/storage/settings_service.dart` | M | +13 | `getAutoLightWeightAfterMinutes` getter/setter |
| `lib/app/bootstrap/bootstrap_settings.dart` | M | +5 | `savedAutoLightWeightAfterMinutes` 字段 |
| `lib/core/providers/core_preferences_providers.dart` | M | +35 | `autoLightWeightAfterMinutesProvider` + `lightWeightModeProvider` Notifier |
| `lib/main.dart` | M | +33 | `_lightWeightTimer` + `_scheduleLightWeightTimer` / `_cancelLightWeightTimer` lifecycle controller + provider override |
| **共用 UI** | | | |
| `lib/modules/settings/sub/general_settings_page.dart` | M | +100 | 三个新行：复制 Windows 诊断脚本 / 导出诊断报告 / 自动轻量模式 |

### 2.5 治理文档

| 文件 | 类型 | 用途 |
|------|------|------|
| `governance/client-comparison-deep-dive-2026-05-07.md` | **新** | v6 治理路线（4 release 全计划 + 测试矩阵 + 验证门槛）|
| `governance/mihomo-bump-cadence.md` | **新** | D-② 月度跟版 SOP |
| `governance/releases-a-b-c-d-review-2026-05-07.md` | **新** | 本文档（审查清单）|

---

## 3. ⚠️ Pre-existing scope —— 不要混入本次 PR

`git status` 里这些文件**不属于** a/b/c/D 任何一个 release，是会话开始前工作树就已经有的改动（或是别人在并行开发）：

| 文件 | 状态 | 是否本轮触碰 |
|------|------|-------------|
| `android/.../YueLinkVpnService.kt` | M | ❌ 完全未动（Android VPN routes/MTU/proxy 是别的 PR）|
| `lib/constants.dart` | M | ❌ 未动（MTU 常量改 9000 是别的 PR）|
| `test/services/android_vpn_service_static_test.dart` | ?? | ❌ 别的 PR 引入 |

**`lib/app/bootstrap/bootstrap_settings.dart`** 和 **`lib/core/storage/settings_service.dart`** 我**有**改动（加新字段），但同文件**也有** pre-existing 改动（语言相关）。这两个文件需要 `git add -p` 选择性 stage 我加的 hunks，不能整文件 add。

具体 pre-existing hunks（不要 stage）：
- `bootstrap_settings.dart:123-132` — `savedLanguage = …getLanguage(); if (storedLanguage != null) …`（这是别的 PR 的 language detect 逻辑）
- `settings_service.dart:482` — `getLanguage()` 返回类型从 `String` → `String?`（别的 PR）

我加的 hunks（要 stage）：
- `bootstrap_settings.dart`：`savedWindowsLanCompatibilityMode` + `savedAutoLightWeightAfterMinutes` 相关
- `settings_service.dart`：`getWindowsLanCompatibilityMode` / `setWindowsLanCompatibilityMode` / `getAutoLightWeightAfterMinutes` / `setAutoLightWeightAfterMinutes` 四个 method 块

---

## 4. 测试矩阵

| 测试文件 | 测试数 | 覆盖 |
|----------|--------|------|
| `dns_policy_catalog_test.dart` | 11 | catalog 不变量（无 dup / 命名约定 / OEM 覆盖率 / rules 子集隔离）|
| `dns_transformer_test.dart` | 20 | YAML validity / 幂等 / **P1-2a 去重 regression**（用 default_config 实状态做 fixture）/ 不覆盖订阅 / flow + block style / **default_config 漂移 guard 双层**（once==twice 且 fake-ip-filter 无 dup 且 AI key 各 1 次）|
| `tun_transformer_test.dart` | 15 | builder 纯函数性 / 安全关键 keys / stack 归一化 / bypass / strict-route 平台分支 / **cold-start composes builder 不变量**（hot-switch 路径不会 drift）/ ConfigTemplate.process 端到端透传 |
| `private_dns_state_test.dart` | 3 | bypassesTun **仅 hostname** / unknown 静默 / 值等价 |
| `windows_diagnostic_script_test.dart` | 4 | 端口替换 / 9 板块齐全 / markdown 输出 / read-only 检查 |
| **新增小计** | **53** | |

**完整 suite**：1019 + 1 skip + 0 fail（995 旧 + 53 新 - 29 已被覆盖的细化 = 1019）。

---

## 5. 待办（**不**在代码范围内）

### 5.1 b.P2-3 — sniffer parse-pure-ip 台架 benchmark

**当前状态**：代码层面**未启用**（保持 v1.0.21 的关闭状态）。governance 文档中已写明这是**实验任务**，分两路交付：

* (a) 节点台架回归 ≤ 5% → 改 `static_sections_transformer.dart:27` 启用 + golden regen
* (b) 回归仍 > 5% → **不改代码**，交付 `governance/sniffer-pure-ip-benchmark-<date>.md` 含数据 + 决策"维持 false"

**需要**：32 MB/s hy2/vless 节点 + iperf3 / curl 大文件下载 + sysstat CPU。`P4-3 mihomo cadence` 已写明 benchmark 必须**在 cadence rebase 完成之后**跑（基线 SHA 才稳定）。

### 5.2 c.P3-2 — iOS Apple 生态实机回归（**合并门槛**）

**当前状态**：Swift 代码已写（`PacketTunnelProvider.swift` 加 7 段 `excludedRoutes`），但**未实机验证**。

governance §5.2 已明确：**6 项必须全 PASS** 才能合 release c：

* [ ] iPhone + Apple TV：AirPlay 投屏不卡
* [ ] iPhone + HomePod：HomeKit 控制延迟回归
* [ ] iPhone + AirDrop：与 Mac 互传不超时
* [ ] iPhone + 群晖：Synology Drive 局域网 LAN 速度
* [ ] iPhone + 路由器：管理界面 192.168.x.1 直访
* [ ] iPhone + Mac：Continuity / Universal Clipboard / Sidecar 仍工作

**需要**：你的 iPhone + Apple TV + HomePod + 群晖 + 路由器。单测无法替代。

### 5.3 c.P3-1 Android 实机抽检（建议）

代码 + 单测齐了，但建议在 Samsung 实机过一遍：

* [ ] mode = `off` → 无 banner ✓ + 一键诊断里也显示 off
* [ ] mode = `opportunistic`（默认）→ 无 banner ✓ + 一键诊断里显示 opportunistic
* [ ] mode = `hostname` 改成 `1dot1dot1dot1.cloudflare-dns.com` → **应该出现 banner**

不是合并门槛但低成本。

---

## 6. 审查重点（建议关注的 6 个高风险点）

按风险从高到低排：

### 6.1 **P1-2a fake-ip-filter 去重 scope fix**（release a）

`lib/core/kernel/config/dns_transformer.dart` `_findFakeIpFilterSubrange` 和 `_filterContains`。这是修复了一个**真实 silent bug**（v5 报告抓到的）—— 整个 dns 段做 contains 会被 nameserver-policy 已有的 `geosite:cn:` 撞中导致跳过插入。

* 边界正则：`^(?![ \t]*(?:$|#|- ))` 兼容**注释**和**空行**作为 list 延续
* 测试 fixture 直接用 `assets/default_config.yaml` 实状态 — 不是手造的
* drift guard 三重断言（once == twice / fake-ip-filter 无 dup / AI key 各 1 次）

如果觉得正则不放心，看 test fixture `assets/default_config.yaml` 第 117 行（` # ── geosite tier ──` 注释）—— 没有这个 fix，那行会截断子段。

### 6.2 **TUN buildDesktopTunYaml 纯函数化**（release b）

`lib/core/kernel/config/tun_transformer.dart` `buildDesktopTunYaml`。之前 `ensureDesktopTun` 是一个 76 行的 inline string concat；现在抽成纯函数 + 调用方组合。

* 不变量：`ensureDesktopTun output 必须包含 buildDesktopTunYaml 的输出 verbatim` —— 测试断言（`tun_transformer_test.dart` 'output contains the builder\'s tun: section verbatim'）。这把"hot-switch 路径不会 drift"锁住。
* `windowsLanCompatibilityMode` 是 builder 的参数，不是从 SettingsService 读 —— transformer **保持纯**。
* CoreLifecycleManager 的 mobile patchConfig 同时修了：从过度指定（`auto-route: true / auto-detect-interface: true` 与 Android `injectTunFd` 的 `auto-route: false` 冲突）简化为 `{enable: bool}`。

### 6.3 **Android Private DNS pull-not-push 模型**（release c）

`lib/core/system/private_dns_state.dart`。

* **明确不用** native 推送（用户上轮特别强调）—— Dart 在 launch / resume / VPN-connected 三个事件主动调 MethodChannel `getPrivateDnsState`
* mode 分级处理：`hostname` 强警告 banner；`opportunistic` / `off` / `unknown` 静默（仅诊断信息）
* MainActivity Kotlin handler 兜底 OEM ROM 拒绝（返回 `unknown`）

### 6.4 **iOS excludedRoutes 写法**（release c）

`ios/PacketTunnel/PacketTunnelProvider.swift:46`。

* 7 段 IPv4 排除：10/8、127/8、169.254/16、172.16/12、192.168/16、224/4、255.255.255.255
* mihomo TUN 仍走 `includedRoutes = [NEIPv4Route.default()]`，excludedRoutes 在 iOS 优先级更高
* **未实机验证** — Apple 生态需 6 项实机过

### 6.5 **DiagnosticReport 上报隐私**（release D）

`lib/shared/diagnostic_report.dart`。明确**不**包含：订阅 URL / token / 密码 / 节点服务器地址 / 当前出口 IP / 历史连接列表 / fake-IP 反查表。

如果你担心遗漏，搜该文件确认每个 section 都不会泄漏。重点看：
* `4. mihomo 运行时` — `step.detail` 来自 StartupStep，应该不含 token
* `5. 系统代理` — 只有 verify 结果（true/false/null），不 dump 具体 proxy URL

### 6.6 **D-⑤ auto-light-weight 范围**（release D）

`lib/main.dart` `_scheduleLightWeightTimer` / `_cancelLightWeightTimer`。

* **基础设施**已就位：setting + provider + lifecycle 触发器 + UI toggle
* **真正释放资源的消费者**未挂 —— 当前 `lightWeightModeProvider` flip 为 true 时**没有任何 widget 真的释放资源**
* 这是有意的：D-⑤ 范围偏 UX/生命周期容易出问题，最稳妥就是先把开关搭起来，让消费者按需 opt-in（比如未来某个 Tab content 加 `if (ref.watch(lightWeightModeProvider)) return SizedBox.shrink()`）。
* 如果你想现在就让某个 widget 实际释放，告诉我具体是哪个 widget 我加。

---

## 7. 验证命令（我跑过的，你可以再跑一次确认）

```bash
# 1. 静态分析
flutter analyze --no-fatal-infos --no-fatal-warnings
# 预期：No issues found

# 2. 架构边界检查
bash scripts/check_imports.sh
# 预期：All import rules passed

# 3. 完整测试套
flutter test
# 预期：1019 passed, 1 skip, 0 fail

# 4. 单独跑本轮新加的 53 测试
flutter test \
  test/core/kernel/config/ \
  test/core/system/ \
  test/shared/windows_diagnostic_script_test.dart
# 预期：53 passed

# 5. 关键 P1-2a regression
flutter test test/core/kernel/config/dns_transformer_test.dart \
  --plain-name "P1-2a"
# 预期：4 passed（用 default_config 实状态做 fixture）

# 6. 桌面 TUN cold-start vs builder 一致性
flutter test test/core/kernel/config/tun_transformer_test.dart \
  --plain-name "verbatim"
# 预期：1 passed
```

---

## 8. Commit 拆分建议（11 个 commit，单 PR 4 个 release）

按 review 友好度排：

```bash
# release a (DNS) — 已可发的部分（4 commit）
git add lib/core/kernel/config/dns_policy_catalog.dart \
        lib/core/kernel/config/rules_transformer.dart
git commit -m "refactor(dns): extract dns_policy_catalog as single source of truth"

git add lib/core/kernel/config/dns_transformer.dart \
        test/core/kernel/config/dns_policy_catalog_test.dart \
        test/core/kernel/config/dns_transformer_test.dart
git commit -m "fix(dns): scope dedup to subsection, allow comments/blanks in list

Pre-fix _filterContains used the entire dns section for substring
matching, causing geosite:cn / +.openai.com etc to be silently dropped
from fake-ip-filter when they appeared as nameserver-policy keys.

Pre-fix _findFakeIpFilterSubrange truncated the subsection at the
first comment or blank line, marking later catalog entries as
'missing' and re-injecting them as duplicates on every pass.

Adds AI-domain injection to the existing-dns: augment path (P1-1
gap: pre-fix only fresh inject knew about catalog AI domains).

31 tests including regression fixtures from assets/default_config.yaml
real state."

git add assets/default_config.yaml \
        test/services/config_template_goldens/
git commit -m "feat(dns): explicit AI nameserver-policy + geosite:cn + cn services + direct-nameserver-follow-policy

P1-1: 60+ AI domains explicitly routed to overseas DoH (catalog-driven,
      both fresh-inject and existing-dns augment paths)
P1-2b: geosite:cn added to fake-ip-filter
P1-3: direct-nameserver-follow-policy: true (mihomo 1.18+)
P1-4: 33 CN-critical domains (banks/carriers/AD) added to fake-ip-filter

Syncs assets/default_config.yaml + regenerates 3 goldens to reflect
catalog-driven behavior."

git add CLAUDE.md
git commit -m "docs(claude): scope mtu:1500 note to iOS only"

# release b (TUN/系统代理) — 3 commit
git add lib/core/kernel/config/tun_transformer.dart \
        test/core/kernel/config/tun_transformer_test.dart
git commit -m "refactor(tun): extract buildDesktopTunYaml as pure builder

Hot-switch and cold-start now share one builder. Asserts via test that
ensureDesktopTun output contains buildDesktopTunYaml output verbatim
so the two paths cannot drift."

git add lib/core/kernel/config_template.dart \
        lib/core/kernel/core_manager.dart \
        lib/core/kernel/desktop_service_mode.dart \
        lib/core/managers/core_lifecycle_manager.dart \
        lib/core/providers/core_preferences_providers.dart
# 注意:settings_service.dart + bootstrap_settings.dart 用 git add -p
git add -p lib/core/storage/settings_service.dart \
            lib/app/bootstrap/bootstrap_settings.dart
git commit -m "feat(tun): Windows LAN compatibility mode toggle

When enabled, desktop TUN uses strict-route: false on Windows so SMB
shares / network printers / remote-desktop into intranet / NAS web UIs
remain reachable while connected. Off by default — keeps the safer
strict-route: true historical behaviour. Wires through SettingsService
→ bootstrap → provider → CoreManager → ConfigTemplate.process →
TunTransformer (transformer remains a pure function — no settings
access from inside)."

git add lib/main.dart lib/modules/settings/sub/general_settings_page.dart
git commit -m "feat(tun): UI toggle + provider override for windowsLanCompatibilityMode

Plus mobile patchConfig hot-switch fix: simplified to {enable: bool}
because the previous payload's auto-route: true / auto-detect-interface:
true contradicted Android injectTunFd's auto-route: false."

# release c (移动端 LAN) — 2 commit
git add ios/PacketTunnel/PacketTunnelProvider.swift
git commit -m "feat(ios): PacketTunnel excludedRoutes for LAN passthrough

⚠️ Apple ecosystem live regression is the merge gate (AirPlay /
HomeKit / AirDrop / NAS / router admin / Continuity). Code-level
implementation only — release c cannot ship until those 6 manual
checks pass on real iPhone hardware."

git add android/app/src/main/kotlin/com/yueto/yuelink/MainActivity.kt \
        lib/core/system/ \
        lib/modules/dashboard/widgets/private_dns_banner.dart \
        lib/modules/dashboard/dashboard_page.dart \
        test/core/system/
git commit -m "feat(android): Private DNS state Dashboard banner (hostname mode only)

Dart pulls via MethodChannel getPrivateDnsState on app launch / resume
/ VPN connect. Banner only fires when mode == hostname (the only mode
that bypasses TUN dns-hijack). opportunistic (Samsung default) is
silent — surfaces in diagnostic report only."

# release D (诊断/UX) — 5 commit
git add lib/shared/windows_diagnostic_script.dart \
        test/shared/windows_diagnostic_script_test.dart
git commit -m "feat(diag): Windows PowerShell diagnostic script generator (D-① P4-2)"

git add governance/mihomo-bump-cadence.md
git commit -m "docs(ops): monthly mihomo bump cadence governance (D-② P4-3)"

git add lib/shared/diagnostic_report.dart
git commit -m "feat(diag): one-click diagnostic report (11 sections, no PII) (D-③ P4-1)"

git add lib/modules/dashboard/widgets/connectivity_test_card.dart \
        lib/modules/dashboard/dashboard_page.dart  # 已被前面占,这里实际是补 import
git commit -m "feat(dashboard): connectivity test card — 6 sites generate_204 probe (D-④ P4-4)"

# D-⑤ auto-light-weight — settings/bootstrap/provider 已分散在 b 的 commit
# 这里只剩 main.dart + settings UI:
git add lib/main.dart  # _lightWeightTimer 块
git add lib/modules/settings/sub/general_settings_page.dart  # auto-light-weight switch
git commit -m "feat(desktop): auto light-weight mode infrastructure (D-⑤ P4-5)

Setting + provider + lifecycle controller. Consumers opt in to the
lightWeightModeProvider flag to release heavy resources after the app
has been in tray for N minutes. No widget consumers wired yet —
infrastructure-only."

# governance 总文档（独立 commit）
git add governance/client-comparison-deep-dive-2026-05-07.md \
        governance/releases-a-b-c-d-review-2026-05-07.md
git commit -m "docs(governance): client comparison deep-dive + releases a/b/c/D review"
```

---

## 9. 你最关心的事 / 常见疑问

### Q1：所有改动加起来有没有不小心改坏什么？

A：分两层验证：

* **静态层**：`flutter analyze` 0 issues + `check_imports.sh` 通过 + 1019 测试全过。
* **行为层**：
  * release a 修了 P1-2a 真实 bug（v5 抓到的 silent 跳过）—— 测试 fixture 用 default_config 实状态，不会装样子
  * release b 改了 hot-switch mobile patchConfig（`auto-route: true` → 简化）—— 但桌面热切换走 `_restartDesktopConnectionMode` 全重启，不依赖这个 patch；mobile 上 CLAUDE.md 说"Connection mode UI hidden on mobile"，意味着用户手不会触发这条路径，简化是防御性
  * release c iOS Swift 改动没 Dart 测试，但 Apple 实机门槛已写明
  * release D 全是新文件，最差情况不影响现有功能（按钮没人点 = 零影响）

### Q2：scope 边界处理对了吗？

A：是。pre-existing 改动（Android VPN service、constants.dart MTU、language detect、settings 返回类型）我**完全没动**。`bootstrap_settings.dart` 和 `settings_service.dart` 我加新字段需要 `git add -p`，但与 pre-existing hunks 是**不同区段**，分割明确。

### Q3：什么是真的"不能合"的硬门槛？

A：**只有 c.P3-2 iOS 实机回归**（governance §5.2 6 项）。其他都是软测试 / 单测覆盖。

### Q4：什么应该等下个版本再做？

A：

* **b.P2-3** sniffer benchmark — 需硬件
* **D-⑤** auto-light-weight 的 widget 消费者挂载 — 范围扩大风险高
* **c iOS 实机回归** — 你做完才能合 c

---

## 10. 一手数据（供回放）

* OpenClash：`/etc/openclash/config.yaml`（4500+ 行）+ `/etc/openclash/custom/`
* Verge Rev：`%APPDATA%/io.github.clash-verge-rev.clash-verge-rev/`
* Samsung CMFA：`adb` `/Users/beita/Library/Android/sdk/platform-tools/adb`（用户已确认可用）
* yuelink 关键代码 anchor 在 governance/client-comparison-deep-dive-2026-05-07.md §10

---

**审查完毕给我反馈。** 任何不通过的项我立刻修。
