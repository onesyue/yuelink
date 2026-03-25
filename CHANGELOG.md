# Changelog

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
