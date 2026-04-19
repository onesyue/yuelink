# yue_auth

悦通账号认证模块。

## 职责
- 登录 / 登出（走 `infrastructure/datasources/xboard`）
- 令牌持久化与自动刷新（`AuthTokenService`）
- `authProvider` 暴露会话态给其他业务模块
- 订阅首次同步、401/403 自动登出

## 布局
- `providers/yue_auth_providers.dart` — `authProvider`、用户资料缓存、订阅同步入口。也是对 `XBoardApi` / `UserProfile` / `XBoardApiException` 的 re-export 面。
- `presentation/yue_auth_page.dart` — 登录页 UI。

## 与 Core 的边界
- 不直接操作 mihomo core lifecycle
- 不直接接管代理运行主链路
- 认证成功后仅通过 provider 暴露会话态
- `syncSubscription()` 下载 YAML 后交给 `ProfileService`
