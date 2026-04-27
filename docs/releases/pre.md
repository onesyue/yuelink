# YueLink v1.0.22-pre

预发布版，发布日期 2026-04-27。基于 v1.0.21 之后的一轮 P0-P3 修复，重点覆盖启动兜底、恢复链路、Windows 行为、诊断导出与托盘 / Dashboard 状态可见性。

### 发布亮点

- **启动不再被本地存储 IO 卡死**：启动阶段的 settings / secure storage 读取加超时保护，即使本地存储异常阻塞也会继续 `runApp()`，避免白屏停在进程启动早期。(`74a4511`)
- **认证初始化有明确兜底**：Auth 初始化增加超时与 bootstrap-uncertain 信号，未知状态会显示轻量 fallback，不再让入口长期停在空白状态。(`16a8371`、`a397fd7`)
- **恢复链路更稳**：resume 健康检查与状态写入之间的 TOCTOU 被收紧；启动重试会等待代理图和 healthcheck provider 就绪，减少“刚恢复就误判失败”的情况。(`948056f`、`d5aacca`)
- **Windows 连接中关闭窗口改为真正退出**：Windows 下处于运行状态时，关闭窗口不再 hide-to-tray，而是按退出路径结束应用，符合用户对桌面窗口关闭的直觉。(`ec9ad67`)
- **托盘和主页状态更清楚**：托盘状态行显示路由模式与连接模式；Dashboard 的路由 / 连接 pill 增加 tooltip，减少只看图标时的歧义。(`3dc3393`、`16b366f`)

### 修复

- **桌面 TUN 服务模式心跳**：当 mihomo API 已确认可用时，桌面 TUN service mode 不再被外层状态误判为异常。(`e5d9ff1`)
- **系统代理恢复**：resume 检测到代理被第三方篡改后，恢复动作会重试一次，降低 Windows / macOS 系统设置短暂拒写造成的误失败。(`d5989ea`)
- **Windows 默认进程识别更保守**：默认 `find-process-mode` 调整为 strict，避免 Windows 上过度探测进程信息带来的兼容性风险。(`01f58f8`)
- **心跳事件日志更可诊断**：心跳失败现在按失败原因分类写入事件日志，便于区分 API 不通、服务状态异常、代理恢复失败等路径。(`2acce55`)
- **诊断导出补全 rotated core.log**：导出诊断包时会包含轮转后的 core 日志 sidecar，不再只带当前 `core.log`。(`4592002`)
- **crash.log 控制体积并去重上报**：本地 crash 日志增加容量上限，远端 reporter 对重复错误做去重，避免同一问题刷屏。(`0beb6f4`)

### 内部工程改进

- **lint 收口**：清理 `main.dart` 中 `unnecessary_underscores`，并补回归测试，降低后续 analyze 噪声。(`7c3336c`)
- **文档对齐**：v1.0.21 release notes 已按 2026 版本格式重新整理，产物说明与实际 release 命名保持一致。(`6c66cc3`、`e740065`、`5e3d8be`)
- **注释修正**：修正代理工具引用里的 `vr2` → `Clash Verge` 拼写。(`46efaa2`)

### 产物与说明

| 文件 | 适用平台 | 说明 |
|------|----------|------|
| `YueLink-1.0.22-pre-android-universal.apk` | Android | 通用安装包，适合绝大多数用户直接下载安装。 |
| `YueLink-1.0.22-pre-android-arm64-v8a.apk` | Android | 64 位 ARM 设备专用包，体积更小。 |
| `YueLink-1.0.22-pre-android-armeabi-v7a.apk` | Android | 32 位 ARM 设备专用包。 |
| `YueLink-1.0.22-pre-android-x86_64.apk` | Android | x86_64 Android 模拟器或少量 x86_64 设备使用。 |
| `YueLink-1.0.22-pre-ios.ipa` | iOS | 侧载安装包，适用于 TrollStore / AltStore / SideStore。 |
| `YueLink-1.0.22-pre-macos-universal.dmg` | macOS | Intel + Apple Silicon 通用 DMG，内含 `修复无法打开.command`。 |
| `YueLink-1.0.22-pre-windows-amd64-setup.exe` | Windows | 标准安装版，自带 VC++ 2015-2022 Redistributable。 |
| `YueLink-1.0.22-pre-windows-amd64-portable.zip` | Windows | 免安装便携版，解压后即可运行。 |
| `YueLink-1.0.22-pre-linux-amd64.AppImage` | Linux | x86_64 AppImage，赋予执行权限后可直接运行。 |

### 校验说明

- 每个预发布产物都会附带一个同名 `.sha256` 文件，用于校验下载完整性。
- Android 用户优先下载 `android-universal.apk`；只有明确知道设备架构时，才建议改下分 ABI 包。
- Windows 默认推荐 `setup.exe`；只有不方便安装或需要绿色版时，再使用 `portable.zip`。
- iOS 包为侧载用途，不走 App Store 分发。

### 版本一致性

本次预发布完成版本号、tag、产物命名三者对齐：

- `pubspec.yaml`：`1.0.22+122`
- Git tag：`pre`（浮动预发布 tag，指向本次 release bump commit）
- 产物命名：`YueLink-1.0.22-pre-*`

### 升级提示

- **预发布定位**：建议先给能反馈问题的用户安装，重点验证启动白屏兜底、resume 自动恢复、Windows 关闭窗口、托盘状态显示和诊断导出。
- **已登录用户**无需重登，订阅与设置自动保留。
- **Windows 用户**：连接中点窗口关闭会直接退出；需要最小化到托盘时请用窗口最小化或托盘路径。
- **rollback**：若出现非预期行为，可回退到 v1.0.21 正式版，数据兼容。

### 已知问题

- **CHANGELOG.md 仍停留在 v1.0.14**：历史欠账，v1.0.15 之后的 release notes 实际都在 `docs/releases/` 下，`CHANGELOG.md` 本身暂不补齐（独立清理项）。
- **win32 5 → 6 联动升级延后**：仍受 `file_picker` / `launch_at_startup` 上游约束，详见 `docs/dependency-upgrade-plan-win32-v6.md`。

### 相关提交

完整提交列表见 `git log v1.0.21..HEAD`。关键用户面修复：

- `e5d9ff1` fix(heartbeat): trust apiOk in desktop TUN service mode
- `948056f` fix(resume): close TOCTOU between health-check and state mutation
- `d5aacca` fix(startup): wait for proxy graph + healthcheck providers on retry
- `ec9ad67` fix(window-close): Windows + running quits instead of hide-to-tray
- `74a4511` fix(bootstrap): timeout-guard storage IO so runApp() always fires
- `16a8371` fix(auth): bootstrap-uncertain signal + AuthNotifier._init timeout
- `a397fd7` feat(auth-gate): render loading fallback for unknown state
- `d5989ea` fix(system-proxy): retry restore on resume tamper detection
- `01f58f8` fix(config): default find-process-mode to strict on Windows
- `3dc3393` feat(tray): show routing + connection mode in status line
- `4592002` fix(diagnostics): include rotated core.log sidecars in export
- `0beb6f4` fix(error-logger): cap crash.log + dedup remote reporter
