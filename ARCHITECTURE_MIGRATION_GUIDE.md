# YueLink 架构迁移规范

## 背景与目标

YueLink v1.0 采用扁平的 MVC 结构：`lib/pages/` 放页面，`lib/services/` 放业务逻辑，`lib/models/` 放数据模型。随着功能增长（16 个模块、30,800+ 行 Dart），这套结构暴露出三个核心问题：

1. **Model 寄生在 API 文件中** — `xboard_api.dart` 同时承载 20+ 个数据模型和所有 HTTP 方法，单文件超过 800 行。Model 无法独立测试，修改一个模型需要重新编译整个 API 层。
2. **Provider 越权** — Provider 直接构造 HTTP 客户端、拼装 API host、处理 401 重定向。状态管理层承担了本该由 Repository 负责的数据编排工作。
3. **跨层耦合** — UI 组件为了获取一个类型定义，不得不 `import` 基础设施层的 API 文件，形成 `Presentation → Infrastructure` 的反向依赖。

**迁移目标**：将代码逐步迁移到 DDD 三层架构（Domain / Infrastructure / Modules），实现关注点分离和单向依赖流。

```
依赖方向（单向，禁止反向）:

  Modules (UI + Provider)
      ↓ 依赖
  Infrastructure (Repository + Datasource)
      ↓ 依赖
  Domain (Entity / Value Object)
```

---

## 目录结构规范

以 `announcements` 模块为样板：

```
lib/
├── domain/
│   └── announcements/
│       └── announcement_entity.dart        # 纯 Dart 数据类
│
├── infrastructure/
│   └── announcements/
│       ├── announcements_repository.dart   # 封装 API 调用，接收 XBoardApi 依赖
│       └── announcements_local_datasource.dart  # 本地持久化（JSON 文件读写）
│
└── modules/
    └── announcements/
        ├── providers/
        │   └── announcements_providers.dart  # Riverpod Provider + DI 组装
        └── presentation/
            └── announcements_page.dart       # UI 页面
```

### 各层职责定义

| 层 | 路径 | 职责 | 禁止 |
|----|------|------|------|
| **Domain** | `lib/domain/<module>/` | 定义 Entity（纯 Dart class，含 `fromJson`）。表达业务概念，不依赖任何框架。 | 禁止 import Flutter、HTTP、Riverpod、path_provider 等任何非 Dart 核心库 |
| **Infrastructure** | `lib/infrastructure/<module>/` | Repository：封装远程 API 调用，将 JSON 映射为 Entity。Datasource：封装本地持久化（文件、数据库）。通过构造函数接收依赖（XBoardApi、MihomoApi 等）。 | 禁止持有状态（state），禁止引用 Riverpod Provider，禁止包含 UI 逻辑 |
| **Modules** | `lib/modules/<module>/` | Provider：通过 Riverpod 注入 Repository/Datasource 实例，管理状态流转。Presentation：UI 页面和组件，只能 `ref.watch`/`ref.read` Provider。 | Provider 禁止直接构造 HTTP 客户端。UI 禁止直接调用 Repository。禁止 import infrastructure 层的 API 文件（除非是获取 Exception 类型） |

### 迁移后的标准调用链路

```
UI (ref.watch)
  → announcementsProvider (FutureProvider)
    → ref.watch(announcementsRepositoryProvider) → Repository
      → XBoardApi.getAnnouncements(token)     ← 复用共享 API 实例
        → Announcement.fromJson()              ← Domain Entity

UI (ref.read)
  → readAnnouncementIdsProvider (Notifier)
    → ref.read(announcementsLocalDatasourceProvider) → LocalDatasource
      → read_announcement_ids.json             ← 本地文件
```

### Provider 层 DI 组装模式

```dart
// 标准写法：Provider 负责"组装"，不负责"实现"
final announcementsRepositoryProvider = Provider<AnnouncementsRepository>((ref) {
  final api = ref.watch(xboardApiProvider);  // 复用共享实例
  return AnnouncementsRepository(api: api);
});

final announcementsLocalDatasourceProvider = Provider<AnnouncementsLocalDatasource>((ref) {
  return AnnouncementsLocalDatasource();      // 无外部依赖时直接构造
});

// 业务 Provider 只依赖上面的抽象，不直接碰 XBoardApi
final announcementsProvider = FutureProvider<List<Announcement>>((ref) async {
  final token = ref.watch(authProvider).token;
  if (token == null) return [];
  final repo = ref.watch(announcementsRepositoryProvider);
  return repo.getAnnouncements(token);
});
```

---

## 4 条硬性红线

### 红线 1：禁止旧增

> **绝对禁止**向以下旧目录新增任何代码：
> - `lib/pages/`
> - `lib/services/`
> - `lib/models/`（旧 models 目录，区别于 `lib/domain/models/`）
> - `lib/ffi/`（旧 FFI 目录）
>
> 所有新增代码必须遵循 `domain/` + `infrastructure/` + `modules/` 三层结构。
> 旧目录中的既有代码允许做 bug fix，但不允许新增 class、function 或 file。

### 红线 2：职责铁律

> | 层 | 可以做 | 绝对不可以做 |
> |----|--------|-------------|
> | **Entity** | 定义字段、fromJson、computed getter | import Flutter/HTTP/Riverpod |
> | **Repository** | 调 API、映射 JSON → Entity、封装异常 | 持有 state、引用 Provider、构造 UI widget |
> | **Provider** | 注入 Repository、管理 state、处理 auth 逻辑 | 直接 `new XBoardApi()`、直接读写文件、包含 UI |
> | **UI** | `ref.watch`/`ref.read` Provider、渲染 | 直接调 Repository、直接 import infrastructure API 文件 |
>
> **单向依赖铁律**：`UI → Provider → Repository → Entity`。任何反向箭头都是违规。

### 红线 3：迁一删一

> 每迁移完一个模块，**必须同步删除**所有关联的旧文件：
> - 旧 Model（如 xboard_api.dart 中内嵌的 class）
> - 旧 Service（如 singleton 的 `XxxService.instance`）
> - 旧 re-export（如 yue_auth_repository.dart 中的 show 列表）
> - 空壳文件和空目录
>
> 绝不容忍新旧两份代码并存。迁移 PR 的 diff 中，删除行数应当接近新增行数。
> 验收标准：`flutter analyze` 零 warning，`flutter test` 全绿。

### 红线 4：特性冻结

> 在以下核心旧模块完成迁移之前，**冻结所有大型新功能的开发**：
> - `nodes`（代理节点）
> - `store`（商店/订单）
> - `profiles`（订阅管理）
> - `connections`（活跃连接）
> - `logs`（日志）
>
> 允许的例外：紧急 bug fix、不涉及架构变更的 UI 微调。
> 原因：在旧架构上堆叠新功能会加深技术债，使后续迁移成本指数增长。

---

## 迁移模板

YueLink 模块分为两种典型模式，迁移时选用对应模板。

### 模板 A：无状态查询型（样板：announcements）

**适用场景**：模块只做数据查询和展示，无用户写操作，无复杂状态流转。典型特征：`FutureProvider` + 只读列表。

**目录结构**：

```
lib/domain/<module>/
  └── <entity>.dart                  # 纯 Dart Entity

lib/infrastructure/<module>/
  ├── <module>_repository.dart       # 封装 API 调用
  └── <module>_local_datasource.dart # 本地持久化（如有）

lib/modules/<module>/
  ├── providers/
  │   └── <module>_providers.dart    # DI Provider + FutureProvider
  └── presentation/
      └── <module>_page.dart         # UI
```

**关键规则**：
- Provider 用 `FutureProvider`，无自定义 State 类
- Repository Provider 通过 `ref.watch(xboardApiProvider)` 注入共享 API 客户端
- LocalDatasource Provider 直接构造实例

### 模板 B：有状态 + 副作用型（样板：checkin）

**适用场景**：模块有用户写操作（签到、购买、提交）、需要 loading/error 状态流转、有 toast/跳转等副作用、有本地与远程状态的对账逻辑。典型特征：`NotifierProvider` + `copyWith` + `AppNotifier`。

**目录结构**：

```
lib/domain/<module>/
  └── <entity>.dart                  # 纯 Dart Entity（API 返回的数据）

lib/infrastructure/<module>/
  ├── <module>_repository.dart       # 封装 API 调用（可以有独立 HTTP 客户端）
  └── <module>_local_datasource.dart # 封装本地持久化调用

lib/modules/<module>/
  ├── state/
  │   └── <module>_state.dart        # State 类（copyWith，UI 驱动的状态集合）
  ├── providers/
  │   └── <module>_provider.dart     # DI Provider + Notifier
  └── presentation/
      └── <module>_card.dart         # UI
```

**State 放置规则**：
- State 类放在 `modules/<module>/state/`，**不是** domain 层
- 原因：State 是 UI 驱动的状态集合（loading、error、checkedInOnOtherDevice），不是业务实体
- Entity 放在 domain 层，State 引用 Entity（`lastResult: CheckinResult?`）
- State 必须有 `copyWith` 方法，字段默认值要合理（`const` 构造函数）

**LocalDatasource 职责**：
- 封装所有对 `SettingsService`、文件系统、SharedPreferences 的直接调用
- Provider 通过 `ref.read(localDatasourceProvider)` 访问，**禁止**直接调用 `SettingsService.get/set`
- 如果模块使用独立服务器（非 XBoard），Repository 保留自己的 HTTP 客户端是合理的，不要强行复用 `XBoardApi`

**Provider / Notifier 的副作用边界**：

| 允许 | 禁止 |
|------|------|
| `AppNotifier.success/warning/error()` — toast 通知 | `Navigator.push()` — 页面跳转由 UI 层处理 |
| `ref.read(authProvider.notifier).refreshUserInfo()` — 联动刷新 | `new CheckinRepository()` — 直接构造依赖 |
| `ref.listen(authProvider)` — 监听登录状态变化 | `SettingsService.get/set()` — 直接调基建 |
| 在 `catch` 中设置 `state.error` | `showDialog()` — UI 操作 |

**Notifier 标准结构**：

```dart
class XxxNotifier extends Notifier<XxxState> {
  // 1. DI — 通过 getter 延迟读取，不在构造函数中
  XxxRepository get _repo => ref.read(xxxRepositoryProvider);
  XxxLocalDatasource get _local => ref.read(xxxLocalDatasourceProvider);

  // 2. build() — 初始化 + 监听
  @override
  XxxState build() {
    ref.listen(authProvider, ...);  // 监听登录状态
    _init();                        // 异步初始化
    return const XxxState();        // 同步返回默认值
  }

  // 3. 公开方法 — UI 调用入口
  Future<void> doAction() async { ... }
  Future<void> refresh() async { ... }
}
```

**独立 HTTP 客户端的合理场景**：
- 模块对接的 API 服务器不是 XBoard（如 checkin 的 `yue.yuebao.website`）
- 此时 Repository 保留自己的 `_get`/`_post`/`_assertSuccess`
- 仍然可以复用 `XBoardApiException` 异常类型（统一错误处理）
- **不要**为了"统一"把独立 API 塞进 `XBoardApi` 类

---

## 迁移优先级建议

基于模块复杂度和依赖关系，建议按以下顺序迁移：

| 优先级 | 模块 | 复杂度 | 说明 |
|--------|------|--------|------|
| ✅ 已完成 | announcements | 低 | 样板工程（模板 A：无状态查询型） |
| ✅ 已完成 | checkin | 低 | 样板工程（模板 B：有状态 + 副作用型） |
| 1 | emby | 极低 | 只有一个 FutureProvider，最简单的练手 |
| 3 | logs | 低 | WebSocket stream + 简单 UI |
| 4 | connections | 低 | WebSocket stream + 简单 UI |
| ✅ 已完成 | profiles | 中 | 依赖反转 + shim 降级 + 外部调用收口（main.dart 保留 shim） |
| ✅ 已完成 | nodes / proxy | 高 | 审计确认：Repository + DI 已就位 |
| ✅ 已完成 | store | 高 | 模板 B+：Model 下沉 + Repository 下沉 + PurchaseState 拆分 |
| ✅ 已完成 | mine / settings | 中 | 审计确认：读取型展示模块，无需 Repository 层 |

---

## 迁移 Checklist 模板

每个模块迁移时，复制此清单并逐项打勾：

```markdown
### [模块名] 迁移 Checklist

- [ ] **分析**：梳理现有字段、API、调用链路
- [ ] **Domain**：Entity 抽至 `lib/domain/<module>/`，纯 Dart，零外部依赖
- [ ] **Infrastructure**：Repository 创建于 `lib/infrastructure/<module>/`，构造函数注入 API 客户端
- [ ] **Infrastructure**：LocalDatasource（如有本地持久化）去除单例，支持 DI
- [ ] **Modules/Provider**：重构为 DI 模式，ref.watch Repository Provider
- [ ] **Modules/UI**：import 路径从 infrastructure → domain
- [ ] **清理旧文件**：删除旧 Model、旧 Service、旧 re-export、空目录
- [ ] **编译验证**：`flutter analyze` 零 error 零 warning
- [ ] **测试验证**：`flutter test` 全绿
- [ ] **手工 QA**：按验证清单在模拟器/真机上点按验证
```
