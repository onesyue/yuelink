# announcements

公告与运营消息模块。

## 职责
- 运营公告拉取与展示
- 活动消息
- 未读公告角标
- 公告已读状态持久化

## 未来依赖
- `YueApi`
- `AnnouncementRepository`

## 与 Core 的边界
- 与代理 Core 完全解耦
- 只负责展示类功能，不影响代理运行

## 当前状态
Phase 6 仅建立骨架，不实现真实业务逻辑。
