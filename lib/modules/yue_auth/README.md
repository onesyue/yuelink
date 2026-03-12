# yue_auth

悦通认证模块。

## 职责
- 登录 / 登出
- 令牌管理与自动刷新
- 会话态持久化
- 第三方登录入口预留

## 未来依赖
- `YueApi`（Yue.to 后端 REST 客户端）
- `AuthRepository`（令牌存储 + 刷新逻辑）

## 与 Core 的边界
- 不直接操作 mihomo core lifecycle
- 不直接接管代理运行主链路
- 认证成功后仅通过 repository/provider 向其他业务模块暴露会话态

## 当前状态
Phase 6 仅建立骨架，不实现真实业务逻辑。
