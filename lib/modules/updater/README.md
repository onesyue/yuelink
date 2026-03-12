# updater

版本更新模块。

## 职责
- 版本检测（对比当前版本与最新版本）
- 更新提示 UI
- 安装包元数据（版本号、更新日志、下载链接）
- 强制/可选更新策略

## 未来依赖
- `UpdateRepository`（GitHub Releases API 或 Yue.to 更新服务）
- 当前 `AutoUpdateService` / `UpdateChecker`（lib/services/）可作为实现迁移来源

## 与 Core 的边界
- 与代理 Core 完全解耦
- 不影响代理运行主链路

## 迁移说明
lib/services/update_checker.dart 和 auto_update_service.dart 的逻辑
未来应迁入本模块的 data/ 和 providers/ 层。
当前这些 service 文件保留原位，本模块仅预留接入骨架。

## 当前状态
Phase 6 仅建立骨架，不实现真实业务逻辑。
