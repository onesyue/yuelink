# mihomo 核心升级评估 2026

评估日期：2026-04-20 · 当前基线：**v1.19.23** · 评估对象：v1.19.24 / Prerelease-Alpha

## 一句话结论

**v1.19.24 属"可升级"但需一次 Android 14 真机 TUN 回归冒烟后再 merge；
Prerelease-Alpha 保持不进主线；暂无"需实验验证"项。**
本文档用于固化该结论以及后续每次 mihomo 相关决策的核对标准，使结构治理和
其它阶段工作不再被内核方向讨论反复打断。

---

## 1. 当前基线

### 1.1 子模块定位

| 项 | 值 |
|---|---|
| 子模块路径 | `core/mihomo` |
| 锁定标签 | `v1.19.23`（HEAD 精确命中该 tag） |
| 上游 URL | `https://github.com/MetaCubeX/mihomo.git` |
| 上游分支策略 | 跟 `Meta` 分支的 stable tag，不跟 `Prerelease-Alpha`（滚动 tag） |

### 1.2 本地补丁

两份补丁仅守"非致命化"边界，未引入功能差异，可 forward-apply 幂等。

| 补丁 | 修改 | 保留理由 |
|---|---|---|
| [`core/patches/0001-non-fatal-buildAndroidRules.patch`](../core/patches/0001-non-fatal-buildAndroidRules.patch) | `listener/sing_tun/server_android.go` 中 `buildAndroidRules()` 的 PackageManager 失败：`log.Fatalln` → `log.Errorln` + 继续 | Android 某些 ROM 无法初始化 PackageManager（影响按应用路由），但 TUN 本身能工作；不应为此杀整个 Flutter 进程 |
| [`core/patches/0002-non-fatal-mmdb-and-iptables.patch`](../core/patches/0002-non-fatal-mmdb-and-iptables.patch) | `component/mmdb/mmdb.go` 的 MMDB/ASN 加载失败 `log.Fatalln` → `log.Errorln` + `return`；`hub/executor/executor.go` 删除 iptables 失败时的 `os.Exit(2)` | MMDB / iptables 在移动端常缺失或无权限；静默降级比整个 VPN 进程退出更合理 |

补丁在 CI 应用：[`.github/workflows/build.yml:110-114`](../.github/workflows/build.yml) 的 `git apply ../patches/*.patch`；本地应用同由 [`setup.dart:188-256`](../setup.dart) 的 `applyMihomoPatches()` 负责，幂等，已 apply 不重复 apply。

### 1.3 构建链

- 输出产物（[`setup.dart:45-67`](../setup.dart) outputNames）：
  - Android：`libclash.so`（`c-shared`）× arm64/arm/amd64
  - iOS：`libclash.a + libclash.h`（`c-archive`，arm64 only）
  - macOS：`libclash.dylib`（`c-shared`）arm64/amd64，通过 `lipo -create` 合并为 universal（[`setup.dart:579-603`](../setup.dart)）
  - Windows：`libclash.dll`（`c-shared`）× amd64/arm64，交叉编译 via mingw32
  - Linux：`libclash.so`（`c-shared`）× amd64/arm64
- 强制 build tag：`-tags with_gvisor`，Android + iOS 均必需，`setup.dart:342/345/376/380/568`
- 公共 ldflags：`-ldflags="-s -w -X github.com/metacubex/mihomo/constant.Version=yuelink"`
- 安装路径：[`setup.dart:625-702`](../setup.dart) `installLibraries()`

### 1.4 CI / 工具链锁定

| 锁定项 | 值 | 出处 |
|---|---|---|
| Go | `1.26.2` | [`build.yml:32`](../.github/workflows/build.yml) + 注释声明与 mihomo v1.19.23 上游 Makefile 对齐 |
| Flutter | `3.41.7` | [`build.yml:26`](../.github/workflows/build.yml) · [`ci.yml:20`](../.github/workflows/ci.yml) |
| Android NDK | r27（`27.2.12479018`） | [`build.yml:85-91`](../.github/workflows/build.yml) |
| iOS 部署目标 | 15.5 | `ios/Runner.xcodeproj/project.pbxproj`（6 处全部对齐，Podfile 15.5 锁） |
| macOS 部署目标 | 10.15 | `macos/Runner.xcodeproj/project.pbxproj` |

### 1.5 Flutter ↔ mihomo 接触面

- FFI 绑定：[`lib/core/ffi/core_bindings.dart`](../lib/core/ffi/core_bindings.dart)。所有 failable 导出返回 `Pointer<Utf8>`：空字符串 = 成功、非空 = 错误信息、NULL = panic 恢复也视为成功。
- 三大入口：`InitCore` / `StartCore` / `StopCore`。`InitCore` ~1s、`StartCore` ~2s，**在主 isolate 同步跑**（曾尝试 `Isolate.run()`，会让 Android/macOS 的 `DynamicLibrary` re-open 挂死）。
- REST 控制器：默认 `127.0.0.1:9090`，端口由 `CoreManager._findAvailablePort()` 动态探测（桌面端避免占用冲突）。
- 数据流（traffic / connections / logs）走 WebSocket，不通过 FFI；见 [`lib/infrastructure/datasources/mihomo_stream.dart`](../lib/infrastructure/datasources/mihomo_stream.dart)。

### 1.6 包 / Bundle 约束

- Android 包名 / iOS Bundle ID：`com.yueto.yuelink`
- iOS Extension：`com.yueto.yuelink.PacketTunnel`
- iOS App Group：`group.com.yueto.yuelink`（共享 geodata + config.yaml 到 Extension 进程）

---

## 2. 上游态势

### 2.1 稳定版

- **v1.19.23**：2026-04-08 发布，当前锁定版本
- **v1.19.24**：2026-04-20 发布（评估当天凌晨）
- 其它更高 stable tag：**无**

来源：<https://github.com/MetaCubeX/mihomo/releases>

### 2.2 预发布

- 唯一的 pre-release tag 是滚动 `Prerelease-Alpha`（2024-08-12 初始创建，持续覆盖）。
- 当前 `Prerelease-Alpha` 内容 ≈ `v1.19.23..Meta`，即已等同 v1.19.24 打标之前的 HEAD。

### 2.3 v1.19.23 → v1.19.24 delta

76 commits，`behind_by=0`（v1.19.24 即为 Meta HEAD 的打标快照）。
完整 compare：<https://github.com/MetaCubeX/mihomo/compare/v1.19.23...v1.19.24>

**与 YueLink 直接相关的改动只有 1 条 + 1 条 CVE：**

1. **[e38aa82](https://github.com/MetaCubeX/mihomo/commit/e38aa82a)** — `chore: don't force bind interface when using fd for tun`（`listener/sing_tun/server.go`）。
   fd 模式下不再强制绑定接口。YueLink 已 `auto-detect-interface: false`，方向一致，但仍需一次 Android 14 真机 TUN 建立冒烟。
2. **[4f927ca](https://github.com/MetaCubeX/mihomo/commit/4f927ca1)** — `fix: CVE-2026-33814 for net/http`（仅 go.mod/go.sum 升 Go stdlib）。

剩余约 60 条集中在 xhttp / hysteria2 / tuic / masque / trusttunnel / quic / BBR / vmess / ss 等传输层新功能与竞态修复。**订阅若不使用这些协议，代码路径不被触发**。

**明确未触及**的区域：
- GEO 加载（GeoIP/GeoSite/country/ASN.mmdb）
- DNS pipeline / nameserver-policy / direct-nameserver
- mixed-port / 外部控制器 / MITM
- process-finding / auto-route / auto-detect-interface 的逻辑
- CGO / c-archive / c-shared 构建模式
- 外部控制器 JSON shape（`/traffic`、`/connections`、`/logs`、`/proxies`）

### 2.4 `with_gvisor` build tag 要求

仍需要。Meta HEAD 源码 `constant/features/with_gvisor.go` 与 `with_gvisor_stub.go` 通过 `//go:build with_gvisor` / `//go:build !with_gvisor` 控制 `WithGVisor` 常量；Makefile 的 `GOBUILD` 仍硬编码 `-tags with_gvisor`；`v1.19.23..Meta` 未触及这两个文件。

### 2.5 下游回归报告

- FlClash / Clash Verge Rev：截至 2026-04-20 无 v1.19.24 的公开回归报告（tag 仅数小时大）。
- mihomo 仓库 2026-04 开启的 TUN bug（#2591 / #2624 / #2605 / #2544）均早于 v1.19.24，不是 v1.19.24 引入。

---

## 3. 升级分类结论

### 3.1 可升级 — v1.19.24

**判据**：
- delta 极小（1 条相关代码改动 + 1 条 CVE fix），且方向与 YueLink 现有配置一致；
- 两份本地补丁 apply 路径未被上游触及，可无修改 forward；
- 工具链 CI 锁与上游 Makefile 保持对齐（Go 1.26.2、`with_gvisor`）；
- 未触及 external-controller JSON shape，Flutter/Dart 侧 WebSocket/REST 调用无需改动。

**合并前必做**：
- Android 14 真机 TUN 建立冒烟（§5.1）——验证 `e38aa82` 的 fd 绑定行为变更不破坏 `auto-detect-interface: false` 路径；
- 跑完整 §5 回归清单。

### 3.2 暂不升级 — Prerelease-Alpha

**判据**（对齐记忆中"跟稳定版，Alpha 不进主线、不开实验、不预研"的标准指令）：
- Alpha 在 YueLink 场景下收益为零——当前 alpha 里新增的传输层功能与 YueLink 订阅协议无交集；
- 滚动 tag 缺少版本锚点，无法做断言式回归；
- 历史 alpha 的 TUN / DNS bug 曾多次被发现并在后续 stable 修正。

### 3.3 需实验验证 — 无

当前没有任何"必须先实验才能决策"的候选。若上游未来某个 stable 同时修改 TUN fd 契约、mmdb loader、外部控制器 JSON 中两个以上区域，将此条升级为必要实验。

---

## 4. 风险点

升级 mihomo 最可能崩的四个区域。每条标注"Flutter 层可见症状"以便回归期间定位。

### 4.1 Android TUN / VpnService fd 模式

- fd 传递契约：`YueLinkVpnService.kt:188` `pfd.detachFd()` → MethodChannel 返回 → `VpnService.startAndroidVpn()` → `ConfigTemplate._injectTunFd()` 把 fd 写进 YAML。
- fd 关闭权只属 Go core（`executor.Shutdown()` → sing-tun close）；Dart 端重复 close 会 SIGABRT。
- 注入 YAML 关键字（[`config_template.dart`](../lib/core/kernel/config_template.dart) `_injectTunFd`）：`enable: true`、`stack: gvisor`、`file-descriptor: <fd>`、`inet4-address: [172.19.0.1/30]`（必须与 Kotlin `addAddress("172.19.0.1", 30)` 完全一致）、`auto-route: false`、`auto-detect-interface: false`、`find-process-mode: off`、`dns-hijack: [any:53]`、`mtu: 1500`（与 Kotlin `setMtu(1500)` 一致）。
- **Flutter 可见症状**：启动到 E006/E007 报错、APP 整进程崩溃、或 VPN "已连接"但所有流量出不去。
- v1.19.24 的 `e38aa82` 命中此区，但方向一致。仍列为 P0 冒烟。

### 4.2 MMDB / IPTables 补丁（patch 0002）

- 补丁作用：`mmdb.go` 加载失败从 `log.Fatalln` 改为 `Errorln + return`；`executor.go` 删除 iptables 失败的 `os.Exit(2)`。
- **若 mihomo 升级同时改了这两个文件 → apply 冲突 → 需 rebase 补丁 → 若遗漏 → 失败回到 Fatalln**。
- **Flutter 可见症状**：首次启动或切订阅后 Go 进程被 OS 杀死、APP 退出。macOS/Linux 表现为 `flutter run` 立即退出，无错误弹窗；iOS 表现为 Extension 立即死，主 app 看到 `vpnRevoked`；Android 表现为 VpnService.stop。
- 回归必检点：看 `git apply` 在 CI 是否抛错，以及 `core.log` 是否出现 Errorln（而不是没有任何信息后直接 crash）。

### 4.3 桌面 Service Mode（特权 helper）

- helper 是独立 Go 二进制，位于 `service/`，通过 Unix socket（macOS/Linux）或 HTTP loopback（Windows）与主 app IPC。
- 它 _不_ 直接依赖 mihomo 的 Go API，仅负责生成/启动 mihomo 子进程；但 helper 自己的 go.mod 在 CI 构建时也使用 `GO_VERSION=1.26.2`。
- `ServiceManager.isReady()`（`service_manager.dart:142-152`）契约：安装 **且** IPC 监听器在 3 秒 deadline 内应答；任何启动路径应先 `isReady()` 再 `start`（CLAUDE.md 明确列为"Privilege boundary probing"通用原则）。
- **Flutter 可见症状**：桌面端 system proxy 配置成功但 core 起不来、或 tray 显示"服务未启动"但 SCM/launchctl/systemctl 说已起。
- 升级 mihomo 若要求更高 Go 版本，helper 的 go.mod `go 1.22` 指令保留不变；若上游开始要求 `go 1.23+`，需同时 bump helper 的 directive。

### 4.4 Geodata / 配置模板

- mihomo 加载 geodata 的 keys（`ConfigTemplate._ensureGeodata`）：`geodata-mode: true`、`geodata-loader: memconservative`（iOS 15MB 内存上限下必须）、`geo-auto-update: true`、`geo-update-interval: 24`、`geox-url`。
- 文件格式：`.dat` 是 protobuf（geoip/geosite），`.mmdb` 是 MaxMind binary。**跨 mihomo 版本未承诺 schema 稳定**——极端情况下上游改动 protobuf / reader 接口会导致 silent parse error。
- 已固化的 fail-soft（[P1-B2B commit `84ce9a1`](../lib/core/kernel/geodata_service.dart)）：CI 侧严格校验 sidecar；运行时侧缺 sidecar → 接受、bytes 不匹配 → 换下一个镜像。这套保护不会被 mihomo 升级影响，但 loader 格式变了它保护不了。
- **Flutter 可见症状**：启动 E009 失败、启动成功但 GEOIP/GEOSITE 规则全部走兜底（connections 页面大量 DIRECT 记录）。

---

## 5. 回归清单

升级前**必须**全部过。每条列"验收点 → 失败信号"。

### 5.1 启动

- [ ] 8 步 pipeline（[`core_manager.dart:165-273`](../lib/core/kernel/core_manager.dart) 附近）：`ensureGeo(E009)` → `initCore(E002)` → `vpnPermission(E003, Android)` → `startVpn(E004, Android)` → `buildConfig(E005)` → `startCore(E006)` → `waitApi(E007)` → `verify(E008)`。**失败信号**：Dashboard `_StartupErrorBanner` 出现 `[Exx]`；`startup_report.json` 在 applicationSupport 目录里 errorCode 非 null。
- [ ] `InitCore` 耗时 ≤ 1s、`StartCore` ≤ 2s、`waitApi` ≤ 5 轮（≈200ms）。**失败信号**：waitApi 轮数 > 20 表示 external-controller 启动变慢。
- [ ] 纯 Dart 配置处理 < 10ms（不跑 isolate）。**失败信号**：startup_report 里 `buildConfig` 段 durationMs 异常上涨。
- [ ] Android 14 真机：VPN 服务授权 → fd 建立 → core 起。**失败信号**：`startVpn` 拿到的 fd 为 -1；或 `core.log` 出现 `listener bind failed`。

### 5.2 连接黄金路径

- [ ] Login → `auth_data` token 就绪。**失败信号**：EventLog `[Auth] login_failed`。
- [ ] `AuthNotifier.syncSubscription()` → `ProfileService.addProfile` 写入 `'悦通'` profile。**失败信号**：Dashboard 订阅列表为空。
- [ ] `ConfigTemplate.process()` 合成 YAML → `CoreManager.start()` 成功。**失败信号**：E005，core.log `parse error: invalid yaml`。
- [ ] 首次 HTTPS 请求走 mixedPort 成功（dashboard 出口 IP 卡片命中）。**失败信号**：`exitIpInfoProvider` 返回 null，或地理位置为本机。
- [ ] `/proxies` WebSocket 订阅到全量节点。**失败信号**：Proxy 页空列表。
- [ ] 延迟测速返回非 timeout。**失败信号**：全组节点全 timeout（[commit `910e9ea`](../.) 的自动恢复会触发重连）。

### 5.3 恢复

- [ ] `RecoveryManager.resetCoreToStopped` 主路径清 4 个 provider：`coreStatusProvider`、`trafficProvider`、`TrafficHistory`、stream subscriptions。
- [ ] `CoreHeartbeatManager` 10s 前台 / 60s 后台心跳：失败 3 次 → 尝试重启 → 再失败 3 次 → `resetCoreToStopped`。
- [ ] Android VPN 撤销（Settings → VPN → 断开）触发 `vpnRevoked`，dashboard 状态立即跟随。
- [ ] iOS Extension 被 OS 杀死（模拟：打开大量 tab 耗内存）→ 主 app 心跳检测到 → 恢复。
- [ ] Android OS SIGKILL VpnService → 下次启动 `cleanupIfDirty()` 清系统代理脏位。**失败信号**：系统代理卡在指向旧 mihomo 端口但 core 未起，浏览器全红叉。

### 5.4 日志 / 诊断

- [ ] `core.log`（mihomo 侧 logrus）在 applicationSupport 目录完整、不截断；`[BOOT]` / `[CORE]` tag 齐全。
- [ ] `event.log` 含本次升级新验证点的各 tag：`[SysProxy]`、`[Geodata]`、`[Updater]`、`[Service]`、`[ProxyGuard]`。
- [ ] `crash.log`：若 core 崩，`ErrorLogger.scanAndroidNativeCrashes()` 把 `[Android/<thread>]` 条目扫成遥测。
- [ ] `startup_report.json` 每步 durationMs + errorCode + detail 都在。
- [ ] Settings → "导出日志"产出的 zip 含 4 份日志 + PII 脱敏生效（11 条正则，见 [`log_export_service.dart`](../lib/shared/log_export_service.dart)）。

### 5.5 更新 / 发布

- [ ] 自更新：`UpdateChecker.check()` 拉清单 → `UpdateChecker.download()` → SHA-256 校验（commit `84ce9a1` 之前就存在的链路，不受本次评估影响）。
- [ ] Geodata：新 mihomo 版本对 `.dat` / `.mmdb` 格式能解码。**失败信号**：`core.log` `geodata load failed: proto: unknown field` 或 `mmdb: invalid metadata`。
- [ ] Android APK FileProvider 安装（`com.yueto.yuelink.fileprovider`）。**失败信号**：应用无法安装（签名或 FileProvider 权限）。
- [ ] iOS：`AppDelegate.writeConfigToAppGroup()` 在 `startVpn` 时把 `config.yaml` + 4 个 geo 文件写入 App Group。**失败信号**：Extension `core.log` `geodata not found in appgroup/mihomo/`。

### 5.6 桌面系统代理

- [ ] macOS：`networksetup -setwebproxy` / `-setsecurewebproxy` / `-setsocksfirewallproxy` 全部接口；`SystemProxyManager.verify()` 返回 true。**失败信号**：verify 返回 false（被第三方客户端覆盖）时 ProxyGuard 3 次恢复后停核。
- [ ] Windows：`ProxyEnable=1` + `ProxyServer=127.0.0.1:<port>`；`WinINet.InternetSetOption(37)` 通知 CP 刷新。**失败信号**：Chrome/Edge 不走代理。
- [ ] Linux：gsettings（GNOME）或 kwriteconfig（KDE）；`verify` 三态之后（[commit `f9fad31`](../lib/core/managers/system_proxy_manager.dart)）gsettings 缺失返 null，ProxyGuard 跳过 restore。
- [ ] `setTunDns()` / `restoreTunDns()`（macOS）：TUN 开启后所有网络服务 DNS 指向 127.0.0.1，关闭后恢复。**失败信号**：停 core 后浏览器仍 DNS 走 127.0.0.1（残留）。
- [ ] `waitApi` 的渐进 backoff 上限 ≈14s 以内 ready。**失败信号**：ProxyGuard 在 `waitApi` 尚未完成时就 verify → 假阳性 tamper 循环。

---

## 6. 配套约束 / 后续

### 6.1 升级执行时的 checklist

升级时按下面顺序推进，每一步过了再进下一步：

1. `cd core/mihomo && git fetch --tags && git checkout v1.19.24`
2. `cd core/mihomo && git apply --check ../../core/patches/*.patch` — 补丁 forward apply 冒烟，有冲突先 rebase 补丁
3. 本地 `dart setup.dart clean && dart setup.dart build -p <platform> && dart setup.dart install -p <platform>`
4. 跑 §5 全部回归（尤其是 Android 14 真机 TUN 冒烟）
5. 独立 commit `chore(core): bump mihomo v1.19.23 → v1.19.24`，不夹带补丁改动
6. 若补丁需 rebase，单独一个 commit `fix(core/patches): rebase 000x onto mihomo vX.Y.Z`

### 6.2 本地补丁维护原则

- **补丁只守"非致命化"**——如果将来想要修改 mihomo 功能，优先向上游提 PR 而不是扩补丁集
- 若某次 upstream release 把补丁覆盖的 `Fatalln` / `os.Exit` 自己改了：删除对应补丁，不在 YueLink 留死码
- 补丁命名规则保持：`00XX-<scope>-<short-description>.patch`

### 6.3 不做

按记忆中的长期指令：

- **不做 mihomo Alpha 实验**——不跟 `Prerelease-Alpha` 滚动 tag，不在主线开 alpha 分支，不做 alpha 专项预研
- **不为了追新破坏现有容错行为**——任何"上游 clean 了某个 Fatalln" 的诱惑都要先确认该路径的 Flutter 层回归面
- **不在 mihomo 升级 commit 里捆绑其它改动**——subscription / config / UI 的修改单独 PR

### 6.4 这份文档的下一次更新触发条件

- 上游发 v1.19.25+ stable 时追加一节"上游态势 / §2.6 X.Y.Z delta"
- 本地补丁 rebase 时追加"§1.2 补丁历史 / rebase 记录"
- 新增需实验验证类候选时追加 §3.3
- §4 / §5 发现了未覆盖的 Flutter 层症状时补进去

---

## 附录 A — 外部基线

- mihomo release / tags：<https://github.com/MetaCubeX/mihomo/releases> · <https://github.com/MetaCubeX/mihomo/tags>
- v1.19.23 → v1.19.24 compare：<https://github.com/MetaCubeX/mihomo/compare/v1.19.23...v1.19.24>
- mihomo FAQ：<https://github.com/MetaCubeX/mihomo/wiki/FAQ>
- 关键 commit：
  - [e38aa82a（TUN fd bind）](https://github.com/MetaCubeX/mihomo/commit/e38aa82a)
  - [4f927ca1（CVE-2026-33814）](https://github.com/MetaCubeX/mihomo/commit/4f927ca1)
- 下游参考：
  - [FlClash](https://github.com/chen08209/FlClash/releases)
  - [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev/releases)

## 附录 B — 相关内部文档 / 决策点

- [`CLAUDE.md`](../CLAUDE.md) — 仓库级 gotchas，包含 TUN / FFI / iOS c-archive / Android `with_gvisor` 等强约束
- [`DEVELOPMENT.md`](../DEVELOPMENT.md) — 构建/工具链文档
- [`docs/architecture-alignment-2026.md`](architecture-alignment-2026.md) — 三层迁移对齐
- [`docs/code-quality-audit-2026.md`](code-quality-audit-2026.md) — 质量/分层现状
- P1 全批次 commits（本文档写入前刚落）：`6c7f9d0..f9fad31`
