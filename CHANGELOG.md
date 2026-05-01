# Changelog

## v1.1.3 (2026-05-01)

### 新功能
- 设计系统统一：12 个二级页面迁移到 inset-grouped + 大标题 scaffold；Material icons 全部 rounded
- iOS 26 风格底栏：玻璃材质 + 图标切换动画；Android 侧规避了带玻璃模糊的 ANR 路径
- macOS 任务栏图标随连接状态切色
- Wintun 打包闭环：Windows 安装包从 wintun.net 下载并 sha256 校验再打包

### 修复 / 增强
- 桌面 TUN 诊断更严格：controller / TUN 网卡 / 路由 / DNS / 基础连通性五项全过才显示"已连接"
- 桌面 TUN 缺驱动时 UI 显示"Wintun 驱动缺失"，不再"假已连接"

### 服务端
- 节点状态机持久化（RUM + 主动探测），人工 gate 才能将节点 quarantined
- 主动探测服务端骨架（runs / results / dead-letter）+ 单 region 参考 runner
- Telemetry release-gate CI：synthetic ingest + privacy 断言 + 端点 schema 校验
- Admin synthetic-cleanup endpoint，避免 release-gate 数据污染生产 stats

### 隐私 / 安全
- 提交前敏感字段扫描器，覆盖 DSN / 订阅 token / Reality 公钥 / shortId 等
- 凭据轮换 SOP + git history 扫描报告
- 既有节点遥测白名单保持不变：服务器地址 / 端口 / UUID / 密码 / SNI / publicKey / shortId 永不离开本机

## v1.1.2 (2026-05-01)

### 新功能
- 节点测速遥测：开启匿名遥测的用户，App 自动测速时上报每节点响应数据（成功标志 / 延迟 / 错误类型 / 状态码 / 协议 / 目标站点）

### 隐私
- 节点遥测字段白名单锁死，服务器地址 / 端口 / UUID / 密码 / SNI / Reality public-key / short-id 永不离开本机；单元测试硬断言保护

## v1.1.1 (2026-04-30)

### 修复
- 桌面端 TUN / Service Mode 首次使用时固定显示安装入口，连接修复页补充安装 / 更新操作
- 修复 Android Wi-Fi 与蜂窝网络互切后需要手动重开代理的问题，并覆盖同类型网络切换场景
- iOS / macOS 接入系统网络路径监听，网络切换后自动触发代理恢复
- Windows / Linux / macOS 增加桌面网络变化轮询与应用恢复时即时检查
- macOS TUN 网络切换后自动重应用 DNS，停止代理时保留正确 DNS 还原能力
- mihomo 本地控制 API / WebSocket 强制直连，避免系统代理回环导致状态不稳

### 稳定性
- Android VPN 会根据当前默认网络重新排序 underlying networks，并在主网络变化时刷新 DNS
- 桌面系统代理在网络切换后自动校验并修复代理配置
- 代理恢复改为多次尝试，失败时回退到轻量重启，减少手动干预

## v1.0.14 (2026-04-12)

### 新功能
- 应用内更新支持稳定版 / 预发布双通道、manifest 多源拉取与 SHA-256 校验
- 桌面端发布形态补齐：Windows 安装包 + 便携包、Linux AppImage、macOS 通用 DMG
- 全平台桌面图标与安装体验升级：squircle 图标、Windows 安装向导图、macOS DMG 背景与修复脚本

### 修复
- 桌面 Service Mode 辅助进程鉴权边界加固：macOS / Linux 改为 Unix socket + peer credential + 路径白名单
- macOS / Linux 原生二进制缺失时增加自愈式补齐，降低打包遗漏导致的启动失败
- 修复 Linux Service Mode 与 CI 端到端发布链路
- 优化连接列表热点路径，降低大量连接时的刷新开销
- 修复 Windows CI UTF-8 输出与 Windows / Linux 核心打包架构问题

### 架构 / 发布
- 引入统一 `ClashCore` 接口，拆分 `CoreManager` 为多管理器，降低核心生命周期与数据访问耦合
- XBoard API 重构为 5 文件模块，国际化迁移到 slang JSON 资源
- GitHub Actions 发布流程重构为单矩阵全平台构建，正式版自动生成 Release 与 updater manifest

## v1.0.8 (2026-03-25)

### 新功能
- 悦视频（Emby）全面升级为 Netflix 风格原生 UI：海报横排、Hero Banner、详情页、剧集列表
- 悦视频原生播放器：字幕控制、播放进度记录、断点续播、音量/亮度手势
- 悦视频支持全库搜索、下拉刷新、HiDPI 海报、代理感知图片缓存
- 商店页：支持购买套餐、优惠券、订单历史
- 每日签到：流量 / 余额奖励，避免重复签到检测
- 订阅管理支持多文件 YAML 导入 / 导出
- iOS VPN 隧道修复：with_gvisor、地理数据、会话恢复与撤销处理
- 链式代理配置支持
- 公告模块：从服务端拉取并本地缓存已读状态
- ToS / 隐私政策页面全平台原生渲染，移除 WebView 依赖

### 修复
- 登录失败：CloudFront CDN 502/503 时自动切换直连回源地址
- 签到 API 401：改用邮箱查询用户 ID，兼容 XBoard 接口
- 悦视频内容为空：STRM 搬运服务器的条目类型为 Video，补充过滤器
- 暗黑模式订阅列表选中图标不可见（主题色为黑色）
- Android 文件选择器无法打开 YAML 文件
- 桌面端 Emby 响应式布局
- 登录后订阅数据拉取失败时后台重试
- 重复 import 警告（7 处）清理

### 架构 / 性能
- 迁移至 DDD 三层架构（domain / infrastructure / modules）
- Flutter 3.27 升级，Dart 3.6
- Android 启动速度优化，滚动流畅度提升（懒加载 + RepaintBoundary）
- 测试覆盖率提升至 207 个单元测试，全部通过
- 后台电池优化，减少不必要的 Provider rebuild

## 1.0.0 (Unreleased)

### Features
- Cross-platform proxy client (Android, iOS, macOS, Windows, Linux)
- mihomo (Clash.Meta) Go core integration via dart:ffi
- Subscription management with traffic usage and expiry tracking
- Proxy node selection with search, filter, and sort-by-delay
- Connection monitor with search and detail view
- Speed test for individual nodes (long-press) or entire groups
- Settings persistence (theme, active profile, auto-connect)
- Mock mode for UI development without Go core
- Responsive layout (NavigationBar on mobile, NavigationRail on tablet/desktop)
- Pull-to-refresh on profile and proxy pages
- Clipboard import for subscription URLs
- Profile edit (rename, change URL) and copy URL
- Stale subscription warning
- System proxy support (macOS via networksetup, Windows via registry)
- TUN mode support (Android VpnService, iOS NetworkExtension)
- Material 3 design with light/dark theme
- Haptic feedback on connect/disconnect

### Infrastructure
- CI/CD pipeline with multi-platform builds
- Automated testing (49 unit tests)
- Go core build orchestrator (`setup.dart`)
- Custom app icon generation script
