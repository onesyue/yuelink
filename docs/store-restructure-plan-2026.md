# store 三层切片 Plan 2026

评估日期：2026-04-20 · 范围：`lib/modules/store/` + `lib/infrastructure/store/` + `lib/domain/store/` · 状态：**仅计划，无代码改动**

## 一句话结论

store 模块已完成三层骨架，**问题在边界不干净不在缺层**。主要漏点集中在 2 个 UI 文件越过 Repository 直取数据源、XBoard 异常从 infra re-export 到 modules、以及 `PurchaseNotifier` 把状态机、轮询锁、cross-module 写回全部扛在一个 404 行文件里。拆成 6 个可独立 commit 的小批次，顺序是 **异常收口 → 状态机域化 → CheckoutResult 解耦 → order_history 瘦身 → 遥测补齐 → 文件重组**，每批都能独立回滚，手工回归面固定在"购买 / 轮询 / 取消 / 复用 / 登出"五条黄金路径。

---

## 0. 方法与范围

- **输入**：三路 agent 只读调研 + 现有 `docs/architecture-alignment-2026.md`、`docs/code-quality-audit-2026.md`、`CLAUDE.md` 中的 store 相关 gotcha。
- **输出**：本文档。不动代码；不改 commit；不调 `analysis_options.yaml`。
- **验收标准**：plan 每一节可审 / 可拒 / 可局部接受；拆分顺序不依赖隐藏假设；每个可独立 commit。
- **非目标**：不谈 nodes（按你指令 store 先动，nodes 留到 store 收口后单独立 plan）。不谈 settings（边界太广）。不动 `CheckoutResult` 的字段含义，只动它的所在层。不动 XBoard endpoint 路径。

---

## 1. 现状问题清单

### 1.1 文件分布与热点

```
lib/modules/store/                                3187 行
├── order_history_page.dart                        807   ← 最重，内含 _OrderItem / _OrderDetailSheet
├── widgets/purchase_confirm_sheet.dart            567   ← 混入 Repository 直取
├── store_providers.dart                           404   ← 状态机 + 轮询锁 + 跨模块写回
├── widgets/order_result_view.dart                 400
├── widgets/plan_detail_sheet.dart                 247
├── store_page.dart                                220
├── widgets/plan_card.dart                         213
├── widgets/payment_method_selector.dart           203
├── widgets/period_selector.dart                    86
└── state/purchase_state.dart                       40

lib/infrastructure/store/store_repository.dart      52   ← 干净薄壳，但泄漏 re-export
lib/domain/store/                                  ~400
├── store_plan.dart                                145
├── store_order.dart                                99   ← CheckoutResult 住在这里（错误）
├── payment_method.dart                             56
├── coupon_result.dart                              57
└── order_list_result.dart                           8
```

**迁移起点评估**：3239 行，但真正痛的是那 4 个 >400 行的文件。目标不是"让每个文件 <200 行"——目标是让每个文件只承担一层职责。

### 1.2 分层混合实例（全部有行号）

1. **[`lib/infrastructure/store/store_repository.dart:10`](../lib/infrastructure/store/store_repository.dart)** — `export '../datasources/xboard/index.dart' show XBoardApiException, UserProfile;`  
   这条 re-export 是所有 modules 层 `catch (XBoardApiException)` 的源头。它让 UI 可以合法 catch 一个 infra exception，破坏了"repo 承担异常翻译"的单向契约。
2. **[`lib/modules/store/order_history_page.dart:5`](../lib/modules/store/order_history_page.dart)** — `import '../../infrastructure/store/store_repository.dart';` 加 `ref.read(storeRepositoryProvider)` 直接取 repo 对象绕过 notifier；`:620` 调用 `repo.cancelOrder(tradeNo)`；`:76` catch `XBoardApiException`。
3. **[`lib/modules/store/widgets/purchase_confirm_sheet.dart:4`](../lib/modules/store/widgets/purchase_confirm_sheet.dart)** — 同样 import repo；`:99` catch `XBoardApiException`。
4. **[`lib/modules/store/store_providers.dart:318`](../lib/modules/store/store_providers.dart)** — `ref.read(authProvider.notifier).syncSubscription().ignore();` 购买成功后单向写回 auth，做得对（必须刷 UserProfile 的流量/到期），但是隐式耦合。
5. **[`lib/domain/store/store_plan.dart:159-175`](../lib/domain/store/store_plan.dart)** — `PlanPeriod.apiKey` 硬编码 XBoard 字段名（`month_price`、`quarter_price` 等）住在 domain。这是"domain 知道 infra schema"。
6. **[`lib/domain/store/store_order.dart:104-127`](../lib/domain/store/store_order.dart)** — `CheckoutResult` 是 XBoard `/checkout` 响应的直接贴图，`type ∈ {-1,0,1}` 这三个魔数只在 XBoard 语境下成立，它不该住 domain。

### 1.3 跨模块耦合

- **入站**（外部 import store）：只有 `lib/modules/settings/settings_page.dart:15-16`（导 StorePage / OrderHistoryPage）和 `lib/modules/dashboard/widgets/hero_banner.dart:13`（导 StorePage）。**都是 page 入口，没有任何外部模块消费 store 的 provider**——这是结构治理的礼物，可以大胆重构内部。
- **出站 → yue_auth**：读 `authProvider.token`（repo 初始化）、读 `userProfileProvider`（page 显示当前套餐徽章）、写 `authProvider.notifier.syncSubscription()`（购买后刷订阅）、调 `authProvider.notifier.logout()`（store_page 登出按钮）。
- **出站 → shared**：`AppNotifier`、`friendlyError`、`rich_content`、`YLEmptyState`、`YLLoading`、`theme`、`app_strings`——全部是 UI/文案/通知层的共享能力，不构成分层问题。
- **出站 → url_launcher**：`store_providers.dart:6`、`order_result_view.dart:6`。PurchaseNotifier 直接 import url_launcher 打开支付 URL——"业务 provider 调用 IO 副作用"——可重构到一个 `PaymentLauncher` 端口。

### 1.4 状态机 / 轮询 / 去重的隐性约束

切片时必须原封保住这些契约（agent B 实测）：

| 契约 | 证据 | 必须保住的原因 |
|---|---|---|
| 购买状态机 6 态：`PurchaseIdle → Loading → AwaitingPayment/Polling → Success/Failed` | [`state/purchase_state.dart:1-40`](../lib/modules/store/state/purchase_state.dart) | UI 的 switch 分支全部锚在这 6 个类型上 |
| 轮询并发锁 `_polling` bool | [`store_providers.dart:79-80, 183-184`](../lib/modules/store/store_providers.dart) | 防止 resumed 触发 + 手动按钮 + 免费短轮询三路同时打 API |
| 免费订单短轮询 3 次 × 2s | [`store_providers.dart:153-158`](../lib/modules/store/store_providers.dart) | `CheckoutResult.type == -1` 专属分支，用户无感知激活 |
| 轮询默认 6 × 3s = 18s | [`store_providers.dart:178-230`](../lib/modules/store/store_providers.dart) | 超时回 `PurchaseAwaitingPayment` 保留原 URL 让用户重试 |
| 去重用 `orderHistoryProvider.value` 快照匹配 `planId + pending` | [`store_providers.dart:105-123`](../lib/modules/store/store_providers.dart) | 读 `.value` 不 await——历史还没加载完就会跳过去重（已知脆弱点，列进 §4.3） |
| 购买成功 → `syncSubscription().ignore()` | [`store_providers.dart:318`](../lib/modules/store/store_providers.dart) | 不刷订阅 UserProfile 就不更新，用户看到"已付款"但流量/到期日不变 |
| cancel 成功 → `orderHistoryProvider.notifier.refresh()` + `Navigator.pop()` | [`order_history_page.dart:617-632`](../lib/modules/store/order_history_page.dart) | 列表不刷新会出现"取消后订单仍显示待支付" |
| `OrderStatus.isSuccess` 含 processing(1) / completed(3) / discounted(4) | [`store_order.dart:95-98`](../lib/domain/store/store_order.dart) | `processing` 认成功是 XBoard 特有语义，不是 `completed-only` |

---

## 2. 目标边界

### 2.1 `lib/domain/store/` — 只放纯数据 + 业务计算

**该留 / 已经对**：
- `StorePlan` + `PlanPeriod`（enum）——**但 `apiKey` 映射挪走**（见 §2.2）
- `StoreOrder` + `OrderStatus`（含 `isSuccess` / `isTerminal`）
- `PaymentMethod`（dataclass，`payment: String "alipay"`，附 `handlingFeeLabel` 计算）
- `CouponResult`（含 `discountFor` / `finalAmountFor` / `discountLabel`）
- `OrderListResult`（分页容器）

**应该落过来**：
- `PurchaseState`（sealed union / 6 态）——**从 `modules/store/state/` 迁到 `domain/store/`**。它没有任何 UI 依赖，只是业务状态快照；迁过去之后 domain 也可以测。

**应该迁走**：
- `CheckoutResult`（含 `-1/0/1` 魔数）——**迁到 `infrastructure/store/` 作为 DTO**。domain 不需要知道支付后端的三枝分支。

**约束**：domain 层禁止 import `http` / `package:url_launcher` / `../infrastructure/...`；`fromJson` 可以保留（DDD 常见折衷），但每个 fromJson 禁止 throw `XBoardApiException`。

### 2.2 `lib/infrastructure/store/` — 数据源适配 + 异常翻译 + DTO

**该留**：
- `StoreRepository` 薄壳，每方法 1-3 行，调 `XBoardApi`。

**应该加**：
- `CheckoutResult`（从 domain 迁来），作为 XBoard `/checkout` 响应的 DTO，附一个 `toXxx()` 方法或直接在 Repository 里翻译成 domain 层的一个新结构（见下）。
- `PaymentOutcome`（新，domain 侧 sealed union：`FreeActivated` / `AwaitingExternalPayment(url: String)` / `PaymentDeclined(reason)`）——这是"翻译后的业务结果"，取代 `CheckoutResult.type == -1 ? ... : ...` 的魔数判断。Repository 负责翻译。
- `PlanPeriodApiMapping`（新）——持有 `PlanPeriod → String apiKey` 的映射表，把 domain 的那段硬编码搬过来。

**应该删**：
- [`store_repository.dart:10`](../lib/infrastructure/store/store_repository.dart) 的 re-export `show XBoardApiException, UserProfile`——删了之后 UI 无法直接 catch infra 异常，被迫经 Repository。
- Repository 方法统一改成 `Result<T, StoreError>` 或直接 throw 一个 domain 层的 `StoreError`（新建，见下）。

**应该加**：
- `StoreError` sealed union（住 `domain/store/`）：`StoreErrorNetwork` / `StoreErrorUnauthorized` / `StoreErrorInvalidCoupon` / `StoreErrorPaymentDeclined` / `StoreErrorUnknown(raw)`。Repository 内部 catch `XBoardApiException` 映射成这些；UI 只 catch `StoreError`。

### 2.3 `lib/modules/store/` — UI + Notifier（薄），0 infra 知识

**该留**：
- 所有 widgets（`plan_card`、`period_selector`、`payment_method_selector` 等）——它们本来就是 UI，边界干净。
- `store_page.dart`、`order_history_page.dart`、各 sheet。

**应该瘦**：
- `store_providers.dart` 拆成 3 个文件：
  - `store_providers.dart`（保留，~100 行）：只含 `storeRepositoryProvider` + `storePlansProvider` + `paymentMethodsProvider` + `orderHistoryProvider` 这种纯读 provider。
  - `purchase_notifier.dart`（新，~200 行）：`PurchaseNotifier` + 状态机。只 depend on `StoreRepository` 接口 + `PaymentLauncher` 端口。
  - `purchase_launcher.dart`（新，~30 行）：`PaymentLauncher` 抽象接口（`Future<bool> open(url)`）+ 一个默认 `UrlLauncherImpl`，让 PurchaseNotifier 不直接 import url_launcher。

- `order_history_page.dart` 的 `_OrderDetailSheet`（531 行）拆出独立文件 `widgets/order_detail_sheet.dart`。
- cancel order 逻辑从 `_OrderDetailSheet` 迁到 `PurchaseNotifier.cancelFromHistory(tradeNo)`，UI 只调 notifier。
- `purchase_confirm_sheet.dart` 删掉 `import store_repository`——券码校验改成调 notifier。

### 2.4 保留桥接（过渡期）

这些可以暂留，迁完后再清理（§6）：

- `modules/store/store_providers.dart` 在拆分期间继续 `export 'purchase_notifier.dart'` + `export 'state/purchase_state.dart'`——让 `settings_page.dart:15-16` 和 `hero_banner.dart:13` 的现有 import 不用跟着动。
- `state/purchase_state.dart` 在 `PurchaseState` 搬到 domain 的期间，保留一个 re-export 兼容一个版本；拆分完成后删除。

---

## 3. 拆分顺序

6 个独立 commit，每个能单独 review / 单独 revert / 单独通过 analyze + test。**顺序不可颠倒**——后面的依赖前面的抽象。

### S1 — 异常边界收口（最小风险，最大收益）

- 新建 `lib/domain/store/store_error.dart` 定义 sealed union。
- `store_repository.dart` 每个方法 catch `XBoardApiException` 映射成 `StoreError`；删掉 `:10` 的 re-export。
- `order_history_page.dart:76` 和 `purchase_confirm_sheet.dart:99` 的 catch 从 `XBoardApiException` 改为 `StoreError`。
- `PurchaseNotifier._extractMessage(e)` 改成 pattern match on `StoreError`。

**commit msg**：`refactor(store): funnel XBoard exceptions through StoreError`  
**验收**：analyze 0 warn / 0 err；308 tests pass；grep `XBoardApiException` 在 `lib/modules/store/` 应为 0。

### S2 — PurchaseState 域化 + Notifier 解耦 url_launcher

- `PurchaseState` 迁到 `lib/domain/store/purchase_state.dart`。`modules/store/state/purchase_state.dart` 留一个 `export` 兼容层（会在 S6 删）。
- 新建 `lib/infrastructure/store/payment_launcher.dart` 定义 `PaymentLauncher` 接口 + `UrlLauncherPaymentLauncher` 默认实现。
- `PurchaseNotifier` 构造时接收 `PaymentLauncher`；`store_providers.dart` 建一个 `paymentLauncherProvider`。
- 删掉 `store_providers.dart:6` 的 `import 'package:url_launcher/...`。

**commit msg**：`refactor(store): lift PurchaseState to domain, inject PaymentLauncher`  
**验收**：analyze + test；grep `package:url_launcher` 在 `lib/modules/store/` 应该只剩 `order_result_view.dart`（UI 层用一次，保留）。

### S3 — `CheckoutResult` 迁走 + `PaymentOutcome` 域化

- `CheckoutResult` 从 `domain/store/store_order.dart` 挪到 `infrastructure/store/checkout_result.dart`，改为 `@internal` or private to the library。
- 新建 `lib/domain/store/payment_outcome.dart` 定义 `PaymentOutcome` sealed union（`FreeActivated` / `AwaitingExternalPayment(url)` / `Declined(StoreError)`）。
- `StoreRepository.checkoutOrder(...)` 的返回类型从 `Future<CheckoutResult>` 改成 `Future<PaymentOutcome>`，内部做 `type == -1 → FreeActivated`、`paymentUrl 非空 → AwaitingExternalPayment` 的翻译。
- `PurchaseNotifier.purchase` / `payExistingOrder` 里的 `if (checkout.paymentUrl.isEmpty) { 短轮询 } else { 打开 URL }` 分支改成 `switch (outcome) { ... }`——**魔数 -1/0/1 不再泄漏到 notifier**。
- 保留免费订单的 3 次 × 2s 短轮询行为（§1.4 契约），现在由 `FreeActivated` 分支触发，不再看 `type`。

**commit msg**：`refactor(store): move CheckoutResult to infra, expose PaymentOutcome to notifier`  
**验收**：analyze + test；grep `type == -1` / `type == 0` 在 `lib/modules/` 应为 0；手工跑一次免费订单路径确认短轮询仍触发。

### S4 — `order_history_page` 拆分 + cancel 改 notifier

- `_OrderDetailSheet`（531 行）迁到 `lib/modules/store/widgets/order_detail_sheet.dart`。
- cancel order 的 UI 回调改成 `ref.read(purchaseProvider.notifier).cancelOrderFromHistory(tradeNo)`。新方法内部：`repo.cancelOrder(tradeNo)` + `ref.invalidate(orderHistoryProvider)` + 返回 bool。UI 只负责关 sheet + toast。
- 删掉 `order_history_page.dart:5` 的 `import store_repository`。

**commit msg**：`refactor(store): extract OrderDetailSheet and route cancel through notifier`  
**验收**：analyze + test；grep `storeRepositoryProvider` 在 `lib/modules/store/` 应该只剩 `store_providers.dart`（定义点本身）+ purchase_notifier 内部；手工跑取消订单路径。

### S5 — 遥测补齐

store 模块当前**零 Telemetry.event**（agent C 确认）。auth 有 `loginSuccess` / `subscriptionSync`，store 应该至少有：

- `TelemetryEvents.purchaseStart` —— 在 `PurchaseNotifier.purchase` 入口。
- `TelemetryEvents.purchaseSuccess` —— `PurchaseSuccess` 状态到达时，带 planId + period。
- `TelemetryEvents.purchaseFail` —— `PurchaseFailed` 时，带 StoreError 类型。
- `TelemetryEvents.orderCancel` —— `cancelOrderFromHistory` / `cancelCurrentOrder` 成功时。
- `TelemetryEvents.pendingOrderReuse` —— 去重命中的时候。

新增 event 常量到 `lib/shared/telemetry.dart` 的 `TelemetryEvents` class。遥测默认 opt-in OFF（CLAUDE.md 已有约束，不改默认）。

**commit msg**：`feat(store): emit telemetry on purchase lifecycle`  
**验收**：`TelemetryPreviewPage`（Settings 里）跑一次完整购买能看到 5 类事件。

### S6 — 文件重组 + 桥接清理

前 5 批全绿之后再做：

- 删掉 `modules/store/state/purchase_state.dart` 的 re-export 兼容层。
- 删掉 `modules/store/store_providers.dart` 的过渡 re-export（PurchaseState 已经走 domain 直接导入了）。
- `modules/store/store_providers.dart` 和新拆的 `purchase_notifier.dart` / `payment_launcher_provider.dart` 都可以缩到 <150 行。
- `PlanPeriod.apiKey` 从 `domain/store/store_plan.dart` 迁到 `infrastructure/store/plan_period_mapping.dart`。Repository 在调 API 时查这个 mapping，不再访问 domain 的硬编码。

**commit msg**：`refactor(store): finalize module layout and drop transitional bridges`  
**验收**：`scripts/check_imports.sh` 通过；文件结构与 §2 目标一致；grep `apiKey` 在 `lib/domain/store/` 应为 0。

---

## 4. 风险点

每条标"怎么检测到发生了"。

### 4.1 支付流时序（最高风险）

- **购买成功后 `syncSubscription()` 异步 fire-and-forget**（`store_providers.dart:318`）。如果 syncSubscription 在用户关 sheet 前还没返回，`userProfileProvider` 的流量/到期日就是旧的，Dashboard 显示"已付款但没加时长"。
- **S3 切面里改 Repository 返回类型会动到这条路径**——翻译错了会让 `FreeActivated` 漏触发 syncSubscription。
- 检测：手工买一个免费促销或 1 元试用，立刻返回 Dashboard 看流量/到期是否更新；`event.log` 看 `[Auth] subscription_synced`。

### 4.2 轮询并发锁

- `_polling` bool 是 Notifier 的成员变量，S2 拆 Notifier 时如果意外把它变成方法局部变量，resumed + manual button + 免费短轮询三路会同时打 `fetchOrderDetail` 导致 rate limit。
- 检测：handler 里 `debugPrint`；灰度期手动触发 App 回前台 + 立刻点"查询支付结果"。

### 4.3 去重的快照读（已知脆弱）

- `ref.read(orderHistoryProvider).value` 是快照，首次打开 store 时历史还没加载完就返回 `null`，走新创建订单的路径——用户在 XBoard 就有了两单同 planId pending。
- 这是**现状 bug，不要在本轮修**——但 S4 改 notifier 时要显式在 comment 里标记这行的不变量，避免无意识把它从 `.value` 改成 `.requireValue`（后者会 throw）。
- 长期修：把去重改成 Repository 侧 `Future` 查询（`repo.findPendingOrder(planId)`），单独一轮再动。

### 4.4 auth 耦合方向

- store 写 auth 只有一处：`syncSubscription()`。切片期间必须保住这条线。
- store 读 auth 有三处（token / userProfileProvider / logout）——都是"读 session"性质，不改。
- 检测：登出期间不应 crash（`storeRepositoryProvider` 跟 token 的 null 传播已有保护，见 `store_providers.dart:22`）；grep `authProvider.notifier` 在 store 内应只出现 2 次（logout 按钮 + syncSubscription）。

### 4.5 免费订单 `type == -1` 短路

- §1.4 契约 + S3 切面交叉——`FreeActivated` 分支必须触发 3×2s 短轮询，不是跳过。如果跳过，用户会看到"购买成功"但 `userProfileProvider` 还没刷，返回 Dashboard 一看流量没加又怀疑是不是真买了。
- 检测：S3 完成后跑一次免费订单，`_polling` debugPrint 应出现。

### 4.6 cancel 的级联刷新

- 当前 cancel 在 UI 层直接 `ref.read(orderHistoryProvider.notifier).refresh()`（`order_history_page.dart:625`）。S4 把 cancel 迁到 notifier 时，必须在 notifier 内部 `ref.invalidate(orderHistoryProvider)` 或 `notifier.refresh()`，不能丢。
- 检测：UI 跑取消 → 列表立刻更新，不需要下拉刷新。

---

## 5. 验证矩阵

### 5.1 自动化（每批必过）

- `flutter analyze --no-fatal-infos --no-fatal-warnings` — 0 warn / 0 err，info 不允许超过 115（当前基线 114，允许 +1 新规）
- `flutter test` — ≥ 308 tests pass（S5 补遥测可能再 +2-3 个单测）
- `bash scripts/check_imports.sh` — 通过
- 每批结束后跑 `git grep -l "XBoardApiException" lib/modules/store/` 应为空（S1 之后）、`git grep "type == -1" lib/modules/` 应为空（S3 之后）等硬断言
- 可选：`flutter test integration_test/ -d macos` 的 smoke 每两批跑一次

### 5.2 手工回归（每批结束都跑，顺序固定）

五条黄金路径——这些是 store 模块的验收锚点，plan 里每一批都得过。

| # | 场景 | 起点 | 期望 | 负面信号 |
|---|---|---|---|---|
| R1 | **购买（redirect）** | 登录态 → Store 页 → 选任意 plan → 选季付 → 支付宝 → 确认 | 浏览器打开支付页；回 app 轮询 3-6 次后显示"已完成"；Dashboard 到期日更新 | 状态卡 AwaitingPayment 不走；or 显示成功但 Profile 不更新 |
| R2 | **轮询（app 回前台）** | 已 AwaitingPayment → app 切后台去完成支付 → 回前台 | `didChangeAppLifecycleState(resumed)` 触发 pollOrderResult；显示"已完成" | 回前台不自动查；或 concurrent 轮询产生 rate limit |
| R3 | **取消订单** | 订单历史 → 点一条 pending → 点"取消订单" | 弹确认 → 成功 toast → 列表里消失 | 列表不刷新；或取消后重复点击二次崩溃 |
| R4 | **已有 pending 复用** | 创建订单后不支付 → 关 sheet → 重新进 Store → 选同 plan 同 period | debugPrint `[Store] Found pending order`；不新建订单；跳直接支付 URL | 产生第二笔 pending |
| R5 | **登出** | 任意状态下 → Settings → 登出 | store 所有 provider 回初始态；重登后订单历史正确加载 | 登出过程 throw；重登后 history 空或混入他人数据 |

- 免费订单链路（R1 的变体）：选 0 元 plan 或 coupon 100% 折扣 → checkout → `FreeActivated` 短轮询 3×2s → 立刻成功。**S3 做完必须跑**。

### 5.3 mock 与真环境

- 单测以 mock repo 为主，handwrite fakes——不引入 mockito 这类元编程依赖。
- R1-R5 手工回归**必须在真 XBoard 环境**跑一次；用 mock 太容易错过 `tinyint(1)` bool 语义和 `status == 1` 认成功这类约束。
- 跑完整五条耗时约 15 分钟。

---

## 6. 删除策略

### 6.1 迁完后可删

- `lib/modules/store/state/purchase_state.dart`（整个文件，S6 批删除——文件已迁 domain）。
- `lib/infrastructure/store/store_repository.dart:10` 的 `export show XBoardApiException, UserProfile;`（S1 批删除）。
- `lib/modules/store/order_history_page.dart:5` 的 `import store_repository`（S4 批删除）。
- `lib/modules/store/widgets/purchase_confirm_sheet.dart:4` 的 `import store_repository`（S1 批就能删——S1 之后 UI 没有 catch XBoardApiException 的理由）。
- `store_providers.dart` 的过渡 `export` 语句（S6 批删除）。
- `PlanPeriod.apiKey` 硬编码（S6 批迁到 infrastructure，删除 domain 侧）。

### 6.2 必须保留（即使看起来可以删）

- `store_plan.dart` / `store_order.dart` 等所有 `fromJson` 工厂——这是 domain 层 DTO 解析的标准做法，不因"domain 不该知道 JSON"就删掉（CLAUDE.md 的 `_toInt`/`_toBool` 约束明确要求这层防御）。
- `OrderStatus.processing` 认成功的语义（[`store_order.dart:95-98`](../lib/domain/store/store_order.dart)）——XBoard 特殊，删了会把"支付成功但服务器还在处理"误认失败。
- `_polling` bool 并发锁——看似可以用 `ref.watch(purchaseProvider)` 检查状态来替代，但现有 lock 覆盖到"状态刚翻 Success 但 UI 还没 rebuild"的窗口期，不能动。
- `AppNotifier` / `friendlyError` 跨切面引用——这些是正确的共享能力，不属于耦合。
- `debugPrint` 行（尤其 `store_providers.dart:115-116/122/215`）——开发期定位 bug 必需，release 模式自动 strip，不进生产噪声。

---

## 附录 A — 候选类型的层级决定

| 类型 | 当前位置 | 目标位置 | 切面 |
|---|---|---|---|
| `StorePlan` | `domain/store/store_plan.dart` | 保持 domain（apiKey 除外） | S6 |
| `PlanPeriod` enum | `domain/store/store_plan.dart` | 保持 domain | — |
| `PlanPeriod.apiKey` 映射 | `domain/store/store_plan.dart:159-175` | 迁 `infrastructure/store/plan_period_mapping.dart` | S6 |
| `StoreOrder` | `domain/store/store_order.dart` | 保持 domain | — |
| `OrderStatus` | `domain/store/store_order.dart` | 保持 domain | — |
| `CheckoutResult` | `domain/store/store_order.dart:104-127` | 迁 `infrastructure/store/checkout_result.dart` | S3 |
| `PaymentMethod` | `domain/store/payment_method.dart` | 保持 domain | — |
| `CouponResult` | `domain/store/coupon_result.dart` | 保持 domain | — |
| `OrderListResult` | `domain/store/order_list_result.dart` | 保持 domain | — |
| `PurchaseState` sealed | `modules/store/state/purchase_state.dart` | 迁 `domain/store/purchase_state.dart` | S2 |
| `PaymentOutcome` sealed（新） | — | 新建 `domain/store/payment_outcome.dart` | S3 |
| `StoreError` sealed（新） | — | 新建 `domain/store/store_error.dart` | S1 |
| `PaymentLauncher` 接口（新） | — | 新建 `infrastructure/store/payment_launcher.dart` | S2 |
| `PurchaseNotifier` | `modules/store/store_providers.dart:78-331` | 拆出 `modules/store/purchase_notifier.dart` | S6 |

---

## 附录 B — 本 plan 不做的事

- 不动 XBoard endpoint 路径或 JSON 字段名。
- 不改 `tinyint(1)` bool 转换的 `_toInt`/`_toBool` 防御层（`CLAUDE.md` 已有明确要求）。
- 不新增依赖（`mockito` / `freezed` / `riverpod_generator` 等一概不引）。
- 不改支付流程的用户体验（轮询次数 / 间隔 / 成功定义）。
- 不动 `orderHistoryProvider` 的分页逻辑和 `loadMore`。
- 不修 §4.3 的去重快照 bug——留单独一轮。
- 不升级 `url_launcher` 版本，只是在 S2 之后把 import 收到 launcher 层。
- 不拆 nodes。等 store 全批次绿了再开 nodes 的 plan。

---

## 附录 C — 相关参考

- [`docs/architecture-alignment-2026.md`](architecture-alignment-2026.md) — 三层迁移总纲
- [`docs/code-quality-audit-2026.md`](code-quality-audit-2026.md) — 质量现状，store 被列为模块总量第 5（3187 行）
- [`docs/mihomo-upgrade-evaluation-2026.md`](mihomo-upgrade-evaluation-2026.md) — 同批次的文档风格先例
- [`CLAUDE.md`](../CLAUDE.md) — store 模块的 gotcha：`auth_data` 双 token、XBoard `tinyint(1)` bool、CheckoutResult.type 语义、CloudFront fallback 等

---

## 下一步

本 plan 等你审。审过之后按 §3 顺序推进：S1 →（analyze + test + R1-R5）→ S2 → … → S6。我不会合并批次，不会调顺序，每批独立 commit 独立回滚。回归红灯停推，不打 tag 不推 master。