# YueLink 代码质量与架构审计 2026

审计日期：2026-04-15

## 审计结论

YueLink 已完成三层迁移的关键地基：`domain / infrastructure / modules`
目录存在，`announcements` 和 `checkin` 可以作为模板 A/B 继续复用；
`scripts/check_imports.sh` 能守住当前主要 import 方向；核心启动链路、
托盘、窗口、热键等冻结区没有被本轮重排。

当前主要风险不在“目录完全不存在”，而在长期演进后形成的边界不均匀：
部分模块已经收敛到 Repository + Provider，部分模块仍是 page-heavy 或
provider-heavy；运行时流、Timer、WebSocket、缓存、登录/登出后的异步任务仍
需要系统性 guard；错误日志有统一入口，但调用点粒度和上下文不一致。

## 风险分级

### P0：必须立即修

- `logs`：`LogEntriesNotifier` 只监听 `coreStatusProvider` 后续变化；如果用户在
  core 已运行后才进入日志页，日志流不会启动。
- `checkin / auth / connections / traffic`：多个异步回调在 provider/notifier
  dispose 后仍可能写状态，长时间运行、切后台、登出重登时风险最高。
- `nodes`：单节点测速失败时 `delayTestingProvider` 可能残留 testing 状态，UI
  后续会认为该节点仍在测速。
- `MihomoStream`：WebSocket 重试 delay 不可取消，异常帧和重连缺少结构化诊断。

### P1：本轮应该完成

- `EventLog`：新增结构化 tag/event/context 格式，统一脱敏 token/secret/password
  等敏感字段，并限制长字段，避免诊断日志泄露。
- `EmbyClient`：代理端口变化时替换 cache manager，需要释放旧 manager，避免长期
  运行后资源堆积。
- `AccountRepository`：原本为 UI 稳定性吞错返回 `null/[]`，但缺诊断上下文；
  本轮保留产品行为，同时写入结构化失败事件。
- `flutter analyze`：清理现有 55 个 info，避免 lint 噪音掩盖真实问题。

### P2：后续排期

- 超长页面仍需小步拆分：`settings_page.dart`、`emby_media_page.dart`、
  `profiles_page.dart`、`connections_page.dart`、`logs_page.dart`、`nodes_page.dart`。
  本轮不拆 UI，避免视觉或交互回归。
- `surge_modules` 仍是模块内自带 `domain/infrastructure` 的局部三层结构，和顶层
  `domain/infrastructure/modules` 不完全一致；后续可按迁移窗口外移。
- `account/checkin/home/yueops` HTTP helper 有重复的 `HttpClient + jsonDecode +
  assertSuccess` 模式，可继续收敛为内部 transport，但不能改变 API contract。
- Emby 页面仍有大量局部 DTO 和 `Map<String, dynamic>` 解析，可后续下沉到
  `domain/emby` 与 `infrastructure/emby`。

### P3：观察项

- `CoreManager`、桌面托盘、热键、窗口生命周期是冻结区；本轮只审计，不重排。
- `config_template.dart` YAML 处理天然需要动态 Map/List，当前测试覆盖较好；
  后续优先增加 typed helper，而不是强行抽象。
- `main.dart` 仍较大，但属于启动和桌面集成主链路，本轮不触碰。

## 本轮处理范围

- 只做无 UI 变化的内部加固：状态 guard、Stream/Timer cleanup、结构化日志、
  analyzer 清理和测试补齐。
- 不改变页面结构、路由、文案、视觉样式、交互顺序和核心配置语义。
- 不重写 `CoreManager`、`main.dart`、`_AuthGate`、`MainShell`、托盘/热键/窗口主流程。

## 测试薄弱点

- 已有 model、core manager、config template、module runtime、purchase notifier
  测试较多。
- 生命周期类 provider 测试偏少，本轮补了日志 provider “core 已运行后创建”的
  回归测试。
- WebSocket 重连本轮以代码审计和 analyze/test 验证为主；完整 socket harness
  可后续补独立 fake server。

## 2026-04-18 Addendum — v1.0.18 pre cleanup + P0 series closure

### 审计基线

- Baseline: 2026-04-15；HEAD at write time: `8756d10`。
- 以下条目覆盖自基线至该 HEAD 之间的落地修复。

### P0 已关闭

- **P0-A** logs provider 冷启动监听 — `a82425c chore(quality): audit 2026 — EventLog.formatTagged + logs provider cold-start fix`
- **P0-B** dispose guards（4 处）：
  - checkin → `97b052a fix(checkin): avoid state writes after provider dispose`
  - auth `_init()` → `8efb445 fix(auth): avoid state writes in _init() after provider dispose`
  - connections + traffic → `43b1eaa fix(runtime): avoid state writes after provider dispose in connections and traffic`
- **P0-C** nodes `testDelay` try/finally 收尾 — `ec7a30a cleanup+fix: drop dead setting + testDelay unmark + cover secret persistence`
- **P0-D** MihomoStream 重连诊断日志 — `767eb56 fix(stream): add diagnostics for MihomoStream reconnect failures`

### 本轮 P1 小修

- carrier `_pollSni()` 的 `_disposed` guard 位置上移到 state 读写块之前 — `8756d10`
- emby player `_progressTimer` tick 回调增加 `mounted` 前置判断 — `8756d10`

### 刻意未做

- auth `login()` / `logout()` dispose guard — pending evaluation; see addendum update if commit lands.
- Telemetry `flush()` 与 `setEnabled(false)` 竞争窗口 — 仅 microtask 宽度，setEnabled 已同步清空 buffer，并非真实缺陷。
- FeatureFlags 单例 timer 架构重排 — 需要 singleton→provider 重构，超出本轮范围。
- Timer 全仓审计 — 2026-04-18 仅对 carrier / emby / telemetry / feature_flags / hero_banner / subscription_sync_service / emby_player_page 做抽样，完整扫荡延后。

### 测试与 CI 基线

- `flutter test`：`All tests passed!`，总计 280 条通过（HEAD `8756d10`）。
- `dart analyze lib/`：error/warning 计数 0。
