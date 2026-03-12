# yue_store

悦通商店模块。

## 职责
- 套餐列表展示
- 购买入口（跳转 WebView 或外部链接）
- 订单状态查询
- 订阅到期提醒

## 未来依赖
- `YueApi`
- `AuthRepository`（依赖 yue_auth 会话态）
- `StoreRepository`

## 与 Core 的边界
- 不直接操作 mihomo core lifecycle
- 购买完成后仅通过 ProfileRepository 触发订阅刷新

## 当前状态
Phase 6 仅建立骨架，不实现真实业务逻辑。
