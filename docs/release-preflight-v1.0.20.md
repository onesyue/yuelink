# Release Preflight — v1.0.20(-pre)

Internal checklist before打 `v1.0.20-pre` tag / 推送预发布。逐项勾选。

## 1. 版本号一致性

- [ ] `pubspec.yaml` = `1.0.20+120`（`git show HEAD:pubspec.yaml | head -5` 验证）
- [ ] iOS `ios/Runner/Info.plist` 使用 `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` 占位符（Flutter 自动注入，**无需手工改**）
- [ ] macOS `macos/Runner/Info.plist` 同上
- [ ] Android `android/app/build.gradle` 使用 `flutter.versionCode` / `flutter.versionName`（**无需手工改**）
- [ ] Windows `windows/installer.iss` 从 `/DMyAppVersion=<version>` 编译期注入（**CI 打包时传入，无需改文件**）
- [ ] 如果本地 build，CI 的 `--build-name` 会自动加 `-pre` 后缀给 prerelease tag

## 2. analyze / test / import

- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` → 14 issues，全部在 `main.dart:543/546/1479/1480/1939`、`nodes_page.dart:89/136/282/641/973`、`service_manager.dart:226/231`、`test/manual/store_real_env_regression_test.dart:10/90` 这四个红线/不动区
- [ ] `flutter test` → 324 pass / 1 skip
- [ ] `bash scripts/check_imports.sh` → `✅ All import rules passed`

## 3. 构建验证（每平台至少一次）

- [ ] **Android**: `flutter build apk --split-per-abi` 成功；产物 4 个 APK（universal / arm64-v8a / armeabi-v7a / x86_64）
- [ ] **iOS**: `flutter build ios --no-codesign` 成功
- [ ] **macOS universal**: `dart setup.dart build -p macos -a arm64` + `-a x86_64` + `install` 合并 → `flutter build macos --release` 成功
- [ ] **Windows amd64**: `dart setup.dart build -p windows` + `install` → `flutter build windows --release` 成功
- [ ] **Linux amd64**（若发 AppImage）: `scripts/build_linux.sh` 成功

## 4. 平台 smoke checklist

每个可用平台至少过一遍以下路径。失败即阻塞 prerelease。

### 4.1 冷启动
- [ ] 清安装 → 启动 → 首屏能加载（不白屏、不 crash、不弹 FATAL）
- [ ] 已登录用户首启：缓存 profile 先展示，后台 refresh 生效
- [ ] 未登录用户首启：onboarding / 登录页正常

### 4.2 登录 / 订阅
- [ ] 登录成功，订阅自动拉取并命名为 `悦通`
- [ ] 订阅更新按钮能强制刷新；更新后节点数量合理
- [ ] 手动导入 URL / 文件订阅（`file_picker` 路径）OK
- [ ] CloudFront 掉线模拟：手动断主域名，登录能切到备用域名

### 4.3 连接 / 节点
- [ ] 默认启动 → 自动连接（若 `autoConnect=true`）
- [ ] 手动切换节点 → 连接跟随切换
- [ ] 测速 long-press → 单节点测速；group 测速按钮 → 批量测速
- [ ] 切换代理模式（rule / global / direct）：**主页徽章点击** + 节点页 full pill 两条路径行为一致
- [ ] 连接模式切换（TUN ↔ systemProxy）：**主页徽章点击** + 设置页切换两条路径行为一致
- [ ] 桌面 TUN：外观仍是靛蓝主题
- [ ] **perf(config) 验证**：日常 HTTPS / YouTube / Google Docs / Cloudflare 网站吞吐对比 v1.0.19 不低于；高流量网速测试（例：fast.com）达到节点标称带宽 80% 以上

### 4.4 前后台 / 恢复
- [ ] 桌面：窗口最小化 → 恢复，连接状态保留
- [ ] 桌面：切到 tray → 左键（Windows）/ 菜单（macOS）恢复窗口
- [ ] 移动：切后台 30s 再回 → **连接状态不翻转**（即：停止态仍是停止，连接态仍是连接）
- [ ] 长时间后台（例 ≥ 5 min）后回到前台 → coreHeartbeat 能重新同步，流量曲线能续上

### 4.5 日志 / 诊断
- [ ] 日志页：实时流渲染正常，过滤级别切换立即生效
- [ ] 日志页：500 行滚动窗口正常（滚动底部 tail follow）
- [ ] 连接页：实时连接列表刷新正常，搜索有效，关闭按钮工作

### 4.6 悦视频 / 商店 / 签到
- [ ] 悦视频：首页加载所有库（Movie / TVShow / Music / BoxSet），海报显示，点击进详情
- [ ] 悦视频：播放 → 字幕 / 进度 / 音量 / 亮度手势工作；断点续播
- [ ] 商店页：套餐列表加载，点击购买 → PaymentMethod 弹出 → 跳转支付
- [ ] 签到：每日一次，奖励按类型显示（traffic / 余额）

### 4.7 状态页 / Dashboard
- [ ] 仪表盘：流量曲线（1m / 5m / 30m 三档），锁定切换正常
- [ ] 出口 IP 卡：能显示 flag + 位置；tap 强制刷新
- [ ] **主页模式徽章点击**：
  - [ ] routing mode 徽章：点一次轮转 rule → global → direct → rule，AppNotifier 反馈有节操
  - [ ] connection mode 徽章：点一次 TUN ↔ systemProxy 热切换（仅桌面），success notifier 正常
- [ ] `profileName` 徽章：保持不可点（无 ripple）

### 4.8 退出
- [ ] **Windows 退出关键验证**：核心**连接中**状态，右键 tray → 退出 → 进程在 3 秒内完全消失（任务管理器无残留）
- [ ] macOS 退出：菜单栏 → 退出，窗口 + 进程一起关
- [ ] Linux 退出：窗口关即退（无 tray）

### 4.9 更新器
- [ ] 设置 → 检查更新：能识别 prerelease tag 为新版本
- [ ] 手动 legacy check 失败时能报错，后台自动 check 失败**不弹窗**
- [ ] 下载进度条正确显示

## 5. 已知问题确认

- [x] **14 条 analyze info 留在红线 / 不动区**：接受
- [x] **`SecureStorageMigration` 未在启动链启用**：接受（内部准备）
- [x] **win32 5 → 6 升级延后**：接受（上游阻塞）
- [x] **CHANGELOG.md 停留在 v1.0.14**：接受（独立历史清理项）

## 6. 回滚方式

- 本地回滚：`git reset --hard v1.0.19` 即回上一个正式版
- 远端回滚：删除 `v1.0.20-pre` 或 `pre` tag + 删除对应 GitHub prerelease
- 用户端回滚：从 GitHub Release 下载 v1.0.19 产物安装，数据兼容
- **不涉及**：数据迁移、配置破坏、订阅失效

## 7. 发布前最后确认

- [ ] dev 分支已经 push 到 `origin/dev`
- [ ] CI 在 dev 最新 commit 上的 smoke build 通过（artifacts 产出）
- [ ] `docs/releases/v1.0.20-pre.md` release notes 最终化
- [ ] `pubspec.yaml` 版本确实是 `1.0.20+120`
- [ ] 没有任何 uncommitted 改动（`git status` clean）
- [ ] 没有遗漏的未 push commit（`git log origin/dev..HEAD` 为空或预期）

## 8. 打 tag 流程（确认后执行，不在本 checklist 范围内自动做）

按 `CLAUDE.md` 的 release flow：

```bash
# A) 复用或移动 pre tag（推荐：持续预发布通道）
git tag -d pre 2>/dev/null; git push origin :refs/tags/pre 2>/dev/null
git tag pre && git push origin pre

# 或 B) 版本化 pre tag（推荐：和特定版本绑定）
git tag -a v1.0.20-pre -m "YueLink v1.0.20-pre" && git push origin v1.0.20-pre
```

CI 的 build workflow 会识别 `pre` 或 `*-pre` 并把 GitHub release 标记为 prerelease，`--build-name` 自动加 `-pre` 后缀。
