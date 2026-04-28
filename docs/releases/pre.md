# YueLink v1.0.23-pre

预发布版，2026-04-28。覆盖一轮启动稳定性、UI 状态一致性、Linux AppImage 兼容、Emby 体验，以及 iOS / macOS FTUE。

## What's New

- **Linux AppImage 内置 libmpv** — Ubuntu 20.04 / Debian 11 / 旧版 Fedora 不用再手动装 `libmpv2`，AppImage 解压即跑（Issue #3）。
- **Emby 标签页冷启动即时显示** — 上次的服务器地址 / 用户 ID / Token 在登录后被本地缓存（24h TTL），再开 app 时 Emby tab 不再先白屏一两秒等远程 sync。
- **iOS 首次启动 VPN 权限提示更清楚** — 系统弹「YueLink 想添加 VPN 配置」之前先解释为什么需要、点同意后会发生什么。
- **macOS Gatekeeper 自动放行** — 从 DMG 拖到应用程序后，下次启动若仍被 quarantine flag 拦下，app 自检并静默修复，不再要用户手动跑 `xattr -d`。
- **新用户默认进入访客模式** — 没账号也能先看 Dashboard / 节点页 / 设置；想用付费功能时再从顶部 CTA 登录。
- **首次连接成功有显式提示** — 连上后顶部弹一次「已连接 · 流量已通过节点」，避免「明明连上了但没反馈」的盲区。
- **Emby 用户首次启动有引导卡** — 订阅自带 Emby 账号的用户在 Dashboard 看到激活按钮，不用翻设置。

## Performance

- **心跳按网络类型分档** — Wi-Fi 15 秒 / 蜂窝 30 秒，前台 / 后台再分一档（60 秒 / 120 秒）。手机端在地铁、移动热点、长时间挂后台时电量明显改善。
- **代理组结构性比较 + 列表短路** — `/proxies` 轮询返回相同内容时整条 UI rebuild 链短路，节点页在大订阅下滚动更顺。
- **大响应解码下沉到 isolate 阈值降到 20 KB** — 主线程更少卡 frame，订阅有几百节点时尤其明显。

## Bug Fixes

- **启动 5 秒超时不再误报 E007** — `waitProxies` 预算从 5 秒放到 15 秒，且超时改为软着陆（启动报告里显示 `slow`）。订阅含 `proxy-providers` / `rule-providers` 第一次拉网络资源时不会再被红 banner 吓到。
- **CDN 提供方拉不动的死循环** — `jsdelivr.net` / `githubusercontent.com` 自动注入 DIRECT 规则，避免 rule-providers 走兜底分流绕回到自己（用户日志里 `[Provider] proxy pull error: ... EOF` 这一类）。
- **macOS 端口冲突时启动不再 verify 失败** — 9090 被占自动改 9091 后，恢复路径不会再把内存里的 9091 用旧持久化值 9090 覆盖回去（之前 E008_CORE_DIED_AFTER_START 的根因）。
- **连接成功后 UI 不再显示「未连接」** — 三个并发路径合修：手动停止标志的写盘改即时刷盘、resume handler 在 `start()` 进行中整体 defer、Dashboard hero card 在节点列表还在加载时显示「处理中」而不是骗用户的「未连接」。
- **节点列表在 graph 还没就绪时自动重试** — 进 Dashboard 后即使 mihomo 还没把代理图组装好，每 3 秒静默 retry 一次直到拿到，无需手动下拉刷新。
- **Emby 首页推荐拉取「Client is already closed」** — Provider 被父级失效瞬间 close 了正在飞的请求；改为在请求自身 finally 中关闭。
- **iOS / Android 原生 MethodChannel 调用加超时** — VPN 启停、托盘、QS Tile 不再有一定概率永久挂起 await。
- **Emby 库类型支持 STRM 服务器** — 视频 / 影集库能正确识别 `Movie,Video` / `Series,Video`，搬运服 Emby 节目数不再为 0。

## Upgrade Notes

- 已登录用户无需重登，订阅与设置自动保留。
- macOS：DMG 直接覆盖即可；之前因为没签名要手动跑命令解隔离的，这版会自动处理。
- Linux：AppImage 已自带 libmpv，不再需要 `apt install libmpv2`；旧版可以直接覆盖 1.0.23-pre 二进制。
- Windows：本版还未变更核心 Windows 行为；从 1.0.22 升级正常进行。
- iOS：TrollStore / AltStore / SideStore 重装新 IPA 即可。

## Downloads

| 平台 | 文件 | 说明 |
|---|---|---|
| Windows | `YueLink-1.0.23-pre-windows-amd64-setup.exe` | 安装版 |
| Windows | `YueLink-1.0.23-pre-windows-amd64-portable.zip` | 便携版 |
| macOS | `YueLink-1.0.23-pre-macos-universal.dmg` | Universal（Apple Silicon + Intel） |
| Android | `YueLink-1.0.23-pre-android-universal.apk` | 通用 |
| Android | `YueLink-1.0.23-pre-android-arm64-v8a.apk` | arm64 |
| Android | `YueLink-1.0.23-pre-android-armeabi-v7a.apk` | armv7 |
| Android | `YueLink-1.0.23-pre-android-x86_64.apk` | x86_64 |
| iOS | `YueLink-1.0.23-pre-ios.ipa` | 侧载，iOS 15+（TrollStore / AltStore / SideStore） |
| Linux | `YueLink-1.0.23-pre-linux-amd64.AppImage` | x86_64 |

每个产物附同名 `.sha256`，汇总见 `YueLink-1.0.23-pre-SHA256SUMS`。

**Full Changelog**: https://github.com/onesyue/yuelink/compare/v1.0.22...pre
