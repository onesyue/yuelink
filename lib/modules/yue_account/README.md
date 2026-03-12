# yue_account

悦通账户模块。

## 职责
- 账户资料展示
- 会员状态与有效期
- 设备列表管理
- 权益详情展示

## 未来依赖
- `YueApi`
- `AuthRepository`（依赖 yue_auth 会话态）
- `AccountRepository`

## 与 Core 的边界
- 不直接操作 mihomo core lifecycle
- 订阅同步仅通过 ProfileRepository 触发，不直接写代理配置

## 当前状态
Phase 6 仅建立骨架，不实现真实业务逻辑。
