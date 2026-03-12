import 'package:flutter/material.dart';

/// Lightweight i18n helper — no code generation required.
///
/// Usage in widgets: `S.of(context).navHome`
/// Usage outside widget tree (tray, services): `S.current.navHome`
class S {
  static S _instance = S._('zh');
  static final S _zh = S._('zh');
  static final S _en = S._('en');

  final String _lang;
  S._(this._lang);

  bool get _e => _lang == 'en';

  /// Locale-aware lookup from a BuildContext.
  static S of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return (locale?.languageCode ?? 'zh') == 'en' ? _en : _zh;
  }

  /// Global singleton — kept in sync with [languageProvider].
  static S get current => _instance;

  static void setLanguage(String langCode) {
    _instance = langCode == 'en' ? _en : _zh;
  }

  // ── Navigation ──────────────────────────────────────────────────
  String get navHome => _e ? 'Dashboard' : '仪表盘';
  String get navProxies => _e ? 'Proxies' : '代理';
  String get navProfile => _e ? 'Subscriptions' : '订阅';
  String get navConnections => _e ? 'Connections' : '连接';
  String get navLog => _e ? 'Logs' : '日志';
  String get navSettings => _e ? 'Settings' : '设置';

  // ── Tray ─────────────────────────────────────────────────────────
  String get trayConnect => _e ? 'Connect' : '连接';
  String get trayDisconnect => _e ? 'Disconnect' : '断开连接';
  String get trayShowWindow => _e ? 'Show Window' : '显示窗口';
  String get trayQuit => _e ? 'Quit' : '退出';
  String get trayProxies => _e ? 'Quick Switch' : '快速切换';

  // ── Common ────────────────────────────────────────────────────────
  String get cancel => _e ? 'Cancel' : '取消';
  String get confirm => _e ? 'OK' : '确定';
  String get save => _e ? 'Save' : '保存';
  String get delete => _e ? 'Delete' : '删除';
  String get edit => _e ? 'Edit' : '编辑';
  String get add => _e ? 'Add' : '添加';
  String get retry => _e ? 'Retry' : '重试';
  String get saved => _e ? 'Saved' : '已保存';
  String get upload => _e ? 'Upload' : '上传';
  String get download => _e ? 'Download' : '下载';
  String get operationFailed => _e ? 'Operation failed' : '操作失败';
  String get noData => _e ? 'No data' : '无数据';

  // ── Disconnect notification ───────────────────────────────────────
  String get disconnectedUnexpected =>
      _e ? 'Connection dropped' : '连接已断开';

  // ── Subscription expiry ───────────────────────────────────────────
  String subExpired(String name) =>
      _e ? 'Subscription "$name" has expired' : '订阅「$name」已过期';
  String subExpiringSoon(String name, int days) => _e
      ? 'Subscription "$name" expires in $days day(s)'
      : '订阅「$name」将在 $days 天后到期';

  // ── Daily traffic ─────────────────────────────────────────────────
  String get todayUsage => _e ? 'Today' : '今日用量';

  // ── Connection status ─────────────────────────────────────────────
  String get statusConnected => _e ? 'Connected' : '已连接';
  String get statusDisconnected => _e ? 'Disconnected' : '未连接';
  String get statusConnecting => _e ? 'Connecting...' : '连接中...';
  String get statusProcessing => _e ? 'Processing...' : '处理中...';
  String get statusDisconnecting => _e ? 'Disconnecting...' : '断开中...';
  String get btnConnect => _e ? 'Connect' : '连接';
  String get btnDisconnect => _e ? 'Disconnect' : '断开连接';
  String get btnConnecting => _e ? 'Connecting' : '连接中';
  String get btnDisconnecting => _e ? 'Disconnecting' : '断开中';

  // ── Routing modes ─────────────────────────────────────────────────
  String get routeModeRule => _e ? 'Rule' : '规则';
  String get routeModeGlobal => _e ? 'Global' : '全局';
  String get routeModeDirect => _e ? 'Direct' : '直连';
  String get routingModeSetting => _e ? 'Routing Mode' : '路由模式';
  String get modeSwitched => _e ? 'Mode switched' : '模式已切换';
  String get directModeDesc => _e
      ? 'All traffic connects directly without proxy'
      : '所有流量直接连接，不经过代理节点';
  String get globalModeDesc => _e
      ? 'All traffic routes through the selected node below'
      : '所有流量通过下方选择的节点转发';

  // ── Traffic ───────────────────────────────────────────────────────
  String get trafficUpload => _e ? 'Upload' : '上传';
  String get trafficDownload => _e ? 'Download' : '下载';
  String get trafficMemory => _e ? 'Memory' : '内存';
  String get activeConns => _e ? 'Connections' : '活跃连接';

  // ── Mock mode ─────────────────────────────────────────────────────
  String get mockModeBanner => _e ? 'Dev Mode · Mock Data' : '开发模式 · 模拟数据';
  String get mockModeLabel => _e ? 'Mock Mode' : '模拟模式';
  String get mockHint => _e ? 'Click Connect to start mock mode' : '点击连接启动模拟模式';

  // ── Home / Dashboard ──────────────────────────────────────────────
  String get dashboardLabel => _e ? 'DASHBOARD' : '仪表盘';
  String get dashboardTitle => _e ? 'Calm network control.' : '从容掌控网络。';
  String get switchNode => _e ? 'Switch node' : '切换节点';
  String get liveConnection => _e ? 'Live connection' : '实时连接';
  String get dashConnectedDesc => _e
      ? 'Your traffic is routed through a healthy node with low latency.'
      : '流量正通过低延迟节点转发，运行正常。';
  String get dashDisconnectedTitle => _e ? 'Not connected' : '未连接';
  String get dashDisconnectedDesc => _e
      ? 'Click Connect to start routing traffic through a proxy node.'
      : '点击连接以开始通过代理节点转发流量。';
  String get realtimeTraffic => _e ? 'Realtime traffic' : '实时流量';
  String get nodeLabel => _e ? 'Current Node' : '当前节点';
  String get exitIpLabel => _e ? 'Outbound IP' : '出口 IP';
  String get routingLabel => _e ? 'Routing Mode' : '路由模式';
  String get exitIpTapToQuery => _e ? 'Tap to query' : '点击查询';
  String get exitIpQuerying => _e ? 'Querying...' : '查询中...';
  String get exitIpFailed => _e ? 'Query failed' : '查询失败';
  String get systemProxy => _e ? 'System Proxy' : '系统代理';
  String get systemProxyOn => _e ? 'System proxy enabled' : '系统代理已启用';
  String get systemProxyOff => _e ? 'System proxy off' : '系统代理未启用';
  String get trafficActivity => _e ? 'Traffic activity' : '流量活动';
  String get last60s => _e ? 'Last 60 seconds' : '最近 60 秒';
  String get dashReadyHint => _e
      ? 'Ready to connect. Tap the power button to start.'
      : '已就绪，点击电源按钮开始连接。';
  String get dashNoProfileHint => _e
      ? 'No profile selected. Add one in Profiles first.'
      : '尚未选择配置，请先在「配置」页面添加。';
  String get dashAutoConnectOn => _e ? 'Auto-connect: On' : '自动连接：开启';
  String get dashAutoConnectOff => _e ? 'Auto-connect: Off' : '自动连接：关闭';
  String get noProfileHint =>
      _e ? 'Add a subscription in the Profiles page first' : '请先在「配置」页面添加订阅';
  String get snackNoProfile =>
      _e ? 'Please add a subscription first' : '请先在「配置」页面添加订阅';
  String get snackConfigMissing =>
      _e ? 'Config not found, please update subscription' : '配置文件不存在，请更新订阅';
  String get snackStartFailed =>
      _e ? 'Start failed, please check config' : '启动失败，请检查配置';

  // ── Proxy page ────────────────────────────────────────────────────
  String get notConnectedHintProxy =>
      _e ? 'Connect first to view proxy nodes' : '请先连接以查看代理节点';
  String get connectToViewProxiesDesc =>
      _e ? 'Connect to the core to view and manage proxies.' : '连接内核以查看和管理代理节点。';
  String nodesCountLabel(int n) => _e ? '$n Nodes' : '$n 个节点';
  String switchedTo(String name) => _e ? 'Switched to $name' : '已切换至 $name';
  String get switchFailed => _e ? 'Failed to switch node' : '切换节点失败';
  String testingGroup(String name) =>
      _e ? 'Testing $name...' : '正在测试 $name...';
  String get directAuto => _e ? 'Direct / Auto' : '直连 / 自动';
  String get searchNodesHint => _e ? 'Search nodes...' : '搜索节点...';
  String get sortByDelay => _e ? 'Sort by delay' : '按延迟排序';
  String get cancelSort => _e ? 'Cancel sort' : '取消排序';
  String get testUrlSettings => _e ? 'Speed Test URL' : '测速 URL';
  String get resetDefault => _e ? 'Reset to Default' : '恢复默认';
  String get unsavedChanges => _e ? 'Unsaved Changes' : '有未保存的修改';
  String get unsavedChangesBody =>
      _e ? 'Leave and discard unsaved changes?' : '有未保存的修改，确定要离开并放弃吗？';
  String get discardAndLeave => _e ? 'Discard & Leave' : '放弃并离开';
  String get stayOnPage => _e ? 'Stay' : '留在当前页';
  String get noMatchingNodes => _e ? 'No matching nodes' : '未找到匹配的节点';
  String get testUrlDialogTitle => _e ? 'Speed Test URL' : '测速 URL';
  String get customUrlLabel => _e ? 'Custom URL' : '自定义 URL';
  String get typeManual => _e ? 'Manual' : '手动选择';
  String get typeAuto => _e ? 'Auto' : '自动测速';
  String get typeFallback => _e ? 'Fallback' : '故障转移';
  String get typeLoadBalance => _e ? 'Load Balance' : '负载均衡';
  String get testAll => _e ? 'Test All' : '测速全部';
  String testingCount(int n) => _e ? 'Testing ($n)' : '测速中 ($n)';
  String nodesCount(int visible, int total) =>
      _e ? '$visible/$total nodes' : '$visible/$total 节点';

  // ── Profile page ──────────────────────────────────────────────────
  String loadFailed(String error) =>
      _e ? 'Load failed: $error' : '加载失败: $error';
  String get noProfiles => _e ? 'No subscriptions' : '暂无订阅';
  String get addSubscriptionHint =>
      _e ? 'Click the button below to add a subscription' : '点击下方按钮添加机场订阅';
  String get pasteFromClipboard =>
      _e ? 'Paste from clipboard' : '从剪贴板粘贴';
  String get addSubscription => _e ? 'Add Subscription' : '添加订阅';
  String get downloadingSubscription =>
      _e ? 'Downloading subscription...' : '正在下载订阅...';
  String get updatingSubscription =>
      _e ? 'Updating subscription...' : '正在更新订阅...';
  String get updateSuccess => _e ? 'Updated successfully' : '更新成功';
  String updateFailed(String error) =>
      _e ? 'Update failed: $error' : '更新失败: $error';
  String get confirmDelete => _e ? 'Confirm Delete' : '确认删除';
  String confirmDeleteMessage(String name) =>
      _e ? 'Are you sure to delete "$name"?' : '确定要删除「$name」吗？';
  String get addSubscriptionDialogTitle =>
      _e ? 'Add Subscription' : '添加订阅';
  String get editSubscriptionDialogTitle =>
      _e ? 'Edit Subscription' : '编辑订阅';
  String get nameLabel => _e ? 'Name' : '名称';
  String get nameHint => _e ? 'My Subscription' : '我的机场';
  String get urlLabel => _e ? 'Subscription URL' : '订阅链接';
  String get updateInterval => _e ? 'Update Interval' : '更新间隔';
  String get followGlobal => _e ? 'Follow Global' : '跟随全局';
  String get days7 => _e ? '7 days' : '7 天';
  String get hours6 => _e ? '6 hours' : '6 小时';
  String get hours12 => _e ? '12 hours' : '12 小时';
  String get hours24 => _e ? '24 hours' : '24 小时';
  String get hours48 => _e ? '48 hours' : '48 小时';
  String usageLabel(String used, String total) =>
      _e ? 'Used $used / $total' : '已用 $used / $total';
  String get expired => _e ? 'Expired' : '已过期';
  String daysRemaining(int days) =>
      _e ? '$days days left' : '剩余 $days 天';
  String get needsUpdate => _e ? 'Needs update' : '需要更新';
  String updatedAt(String time) =>
      _e ? 'Updated at $time' : '更新于 $time';
  String get noConfig => _e ? 'Config file not found' : '配置文件不存在';
  String get copyConfig => _e ? 'Copy config' : '复制配置';
  String get copiedConfig => _e ? 'Config copied' : '已复制配置内容';
  String get copyLink => _e ? 'Copy link' : '复制链接';
  String get copiedLink =>
      _e ? 'Subscription link copied' : '已复制订阅链接';
  String get viewConfig => _e ? 'View config' : '查看配置';
  String get updateSubscription =>
      _e ? 'Update subscription' : '更新订阅';
  String get clipboardNoUrl =>
      _e ? 'No valid subscription URL in clipboard' : '剪贴板中没有有效的订阅链接';
  String get addSuccess => _e ? 'Added successfully' : '添加成功';
  String addFailed(String error) =>
      _e ? 'Failed to add: $error' : '添加失败: $error';
  String get importLocalFile => _e ? 'Import local file' : '从本地文件导入';
  String get importLocalFileSuccess =>
      _e ? 'Imported successfully' : '导入成功';
  String get importLocalFileFailed =>
      _e ? 'Import failed: no valid YAML file selected' : '导入失败：未选择有效的 YAML 文件';
  String get importLocalNameHint => _e ? 'My Config' : '我的配置';

  // ── Split tunneling (Android) ─────────────────────────────────────
  String get sectionSplitTunnel =>
      _e ? 'Split Tunneling' : '分应用代理';
  String get splitTunnelMode => _e ? 'Mode' : '代理模式';
  String get splitTunnelModeAll => _e ? 'All apps' : '全部应用';
  String get splitTunnelModeWhitelist =>
      _e ? 'Proxy listed apps only' : '仅代理选定应用';
  String get splitTunnelModeBlacklist =>
      _e ? 'Bypass listed apps' : '绕过选定应用';
  String get splitTunnelApps => _e ? 'App List' : '应用列表';
  String get splitTunnelManage => _e ? 'Manage Apps' : '管理应用';
  String get splitTunnelSearchHint =>
      _e ? 'Search apps...' : '搜索应用...';
  String get splitTunnelEffectHint =>
      _e ? 'Changes take effect on next connect' : '下次连接时生效';

  // ── Geo resources ─────────────────────────────────────────────────
  String get sectionGeoResources => _e ? 'Geo Resources' : 'GeoIP/GeoSite 资源';
  String get geoResourcesHint =>
      _e ? 'mihomo uses these files for rule-based routing'
         : 'mihomo 路由分流所需的地理数据库文件';
  String get geoUpdateAll => _e ? 'Update All' : '一键更新';
  String get geoUpdateSuccess => _e ? 'Geo resources updated' : 'Geo 资源更新成功';
  String get geoUpdateFailed => _e ? 'Update failed' : '更新失败';
  String get geoNotFound => _e ? 'Not found' : '文件不存在';
  String geoFileSize(String size) => size;

  // ── Config rollback ───────────────────────────────────────────────
  String get rollbackTitle => _e ? 'Start Failed' : '启动失败';
  String get rollbackContent =>
      _e ? 'The configuration failed to start. Rollback to the last known-good config?'
         : '配置启动失败，是否回退到上一次可用的配置？';
  String get rollbackConfirm => _e ? 'Rollback' : '回退';
  String get rollbackSuccess => _e ? 'Rolled back successfully' : '已回退到上次可用配置';
  String get rollbackFailed => _e ? 'Rollback failed' : '回退也失败了，请检查配置';

  // ── Update checker ────────────────────────────────────────────────
  String get checkUpdate => _e ? 'Check for Updates' : '检查更新';
  String get updateAvailable => _e ? 'New version available' : '发现新版本';
  String get updateDownload => _e ? 'Download' : '下载';
  String get alreadyLatest => _e ? 'Already up to date' : '已是最新版本';
  String get updateCheckFailed => _e ? 'Failed to check for updates' : '检查更新失败';

  // ── YAML validation ───────────────────────────────────────────────
  String get yamlInvalid => _e ? 'Invalid YAML syntax' : 'YAML 语法错误';

  // ── Global hotkey ─────────────────────────────────────────────────
  String get sectionHotkeys => _e ? 'Global Hotkeys' : '全局热键';
  String get hotkeyToggle =>
      _e ? 'Toggle connection (Ctrl+Alt+C)' : '切换连接 (Ctrl+Alt+C)';
  String get hotkeyHint =>
      _e ? 'Available on macOS and Windows' : '仅在 macOS / Windows 上生效';

  // ── Connections page ──────────────────────────────────────────────
  String get notConnectedHintConnections =>
      _e ? 'Connect first to view active connections' : '请先连接以查看活跃连接';
  String get searchConnHint =>
      _e ? 'Search target, process, rule...' : '搜索目标、进程、规则...';
  String get closeAll => _e ? 'Close All' : '断开全部';
  String connectionsCount(int count) =>
      _e ? '$count connections' : '$count 个连接';
  String connectionsCountFiltered(int count) =>
      _e ? '$count connections (filtered)' : '$count 个连接（已过滤）';
  String get noActiveConnections =>
      _e ? 'No active connections' : '暂无活跃连接';
  String get noMatchingConnections =>
      _e ? 'No matching results' : '无匹配结果';
  String get closeAllDialogTitle =>
      _e ? 'Close All Connections' : '断开所有连接';
  String get closeAllDialogMessage =>
      _e ? 'Are you sure to close all active connections?' : '确定要断开所有活跃连接吗？';
  String get statConnections => _e ? 'Connections' : '连接数';
  String get statTotalDownload => _e ? 'Total Download' : '累计下载';
  String get statTotalUpload => _e ? 'Total Upload' : '累计上传';
  String get connectionDetailTitle =>
      _e ? 'Connection Details' : '连接详情';
  String get detailTarget => _e ? 'Target' : '目标';
  String get detailProtocol => _e ? 'Protocol' : '协议';
  String get detailSource => _e ? 'Source' : '来源';
  String get detailTargetIp => _e ? 'Target IP' : '目标 IP';
  String get detailProxyChain => _e ? 'Proxy Chain' : '代理链';
  String get detailRule => _e ? 'Rule' : '规则';
  String get detailProcess => _e ? 'Process' : '进程';
  String get detailDuration => _e ? 'Duration' : '持续时间';
  String get detailDownload => _e ? 'Download' : '下载';
  String get detailUpload => _e ? 'Upload' : '上传';
  String get detailConnectTime => _e ? 'Connect Time' : '连接时间';

  // ── Log page ──────────────────────────────────────────────────────
  String get notConnectedHintLog =>
      _e ? 'Connect first to view logs' : '请先连接以查看日志';
  String get tabLogs => _e ? 'Logs' : '日志';
  String get tabRules => _e ? 'Rules' : '规则';
  String get searchLogsHint => _e ? 'Search logs...' : '搜索日志...';
  String get searchLogsRegexHint => _e ? 'Regex pattern...' : '正则表达式...';
  String get regexSearch => _e ? 'Toggle regex search' : '切换正则搜索';
  String get clearLogs => _e ? 'Clear logs' : '清空日志';
  String get noLogs => _e ? 'No logs' : '暂无日志';
  String logsCount(int count) => _e ? '$count logs' : '$count 条日志';
  String logLevelLabel(String level) =>
      _e ? 'Level: $level' : '级别: $level';
  String rulesCount(int count) =>
      _e ? '$count rules' : '共 $count 条规则';
  String matchedRulesCount(int count) =>
      _e ? '$count matched' : '匹配 $count 条';
  String get searchRulesHint => _e ? 'Search rules...' : '搜索规则...';
  String get noMatchingRules =>
      _e ? 'No matching rules' : '未找到匹配的规则';

  // ── Overwrite page ────────────────────────────────────────────────
  String get overwriteTitle => _e ? 'Config Overwrite' : '配置覆写';
  String get overwriteRulesTitle => _e ? 'Overwrite Rules' : '覆写规则';
  String get overwriteRulesDescription => _e
      ? '• Scalar keys (mode, log-level, etc.) replace values in the subscription config\n'
          '• rules list is prepended before subscription rules\n'
          '• proxies / proxy-groups lists are appended after the subscription'
      : '• 标量键（mode, log-level 等）会替换订阅中的对应值\n'
          '• rules 列表会插入到订阅规则之前\n'
          '• proxies / proxy-groups 列表会追加到订阅之后';
  String get overwriteHintText => _e
      ? '# Example:\n# mode: rule\n# rules:\n#   - DOMAIN-SUFFIX,example.com,DIRECT'
      : '# 示例:\n# mode: rule\n# rules:\n#   - DOMAIN-SUFFIX,example.com,DIRECT';
  String get savedNextConnect =>
      _e ? 'Saved, will take effect on next connect' : '已保存，下次连接时生效';

  // ── Settings page ─────────────────────────────────────────────────
  String get sectionConnection => _e ? 'Connection' : '连接';
  String get sectionCore => _e ? 'Core' : '内核';
  String get sectionSubscription => _e ? 'Subscription' : '订阅';
  String get sectionWebDav => _e ? 'WebDAV Sync' : 'WebDAV 同步';
  String get sectionAppearance => _e ? 'Appearance' : '外观';
  String get sectionStatus => _e ? 'Status' : '状态';
  String get sectionTools => _e ? 'Tools' : '工具';
  String get sectionAbout => _e ? 'About' : '关于';
  String get sectionDesktop => _e ? 'Desktop' : '桌面端';
  String get sectionNetwork => _e ? 'Network' : '网络';
  // Close window
  String get closeWindowBehavior => _e ? 'Close Window' : '关闭窗口';
  String get closeBehaviorTray => _e ? 'Minimize to tray' : '最小化到托盘';
  String get closeBehaviorExit => _e ? 'Exit application' : '退出应用';
  // Hotkey
  String get toggleConnectionHotkey => _e ? 'Toggle Connection Hotkey' : '连接快捷键';
  String get hotkeyEdit => _e ? 'Edit' : '编辑';
  String get hotkeyListening => _e ? 'Press a key combination...' : '请按下组合键...';
  String get hotkeySaved => _e ? 'Hotkey saved' : '快捷键已保存';
  String get hotkeyFailed => _e ? 'Failed to register hotkey' : '快捷键注册失败';
  // Geo database
  String get geoDatabase => _e ? 'Geo Database' : '地理数据库';
  String get geoUpdateNow => _e ? 'Update Now' : '立即更新';
  String get geoUpdated => _e ? 'Geo database updated' : '地理数据库已更新';
  String geoLastUpdated(String date) => _e ? 'Updated: $date' : '更新于 $date';
  // Linux-specific
  String get linuxProxyNotice =>
      _e ? 'System proxy not managed automatically on Linux' : 'Linux 不自动管理系统代理';
  String get linuxProxyManual => _e ? 'Manual proxy: 127.0.0.1:7890' : '手动代理: 127.0.0.1:7890';
  String get hotkeyLinuxNotice =>
      _e ? 'Not supported on all Linux desktops' : '部分 Linux 桌面不支持全局快捷键';
  // Diagnostics
  String get diagnostics => _e ? 'Diagnostics' : '诊断';
  String get viewStartupReport => _e ? 'View startup report' : '查看启动报告';
  String get copiedToClipboard => _e ? 'Copied to clipboard' : '已复制到剪贴板';
  String get sectionLanguage => _e ? 'Language' : '语言';
  String get connectionMode => _e ? 'Connection Mode' : '接入方式';
  String get modeTun => _e ? 'TUN Mode' : 'TUN 模式';
  String get modeSystemProxy => _e ? 'System Proxy' : '系统代理';
  String get setSystemProxyOnConnect =>
      _e ? 'Set system proxy on connect' : '连接时设置系统代理';
  String get setSystemProxyOnConnectSub =>
      _e ? 'Auto-configure HTTP/SOCKS system proxy' : '连接后自动配置 HTTP/SOCKS 系统代理';
  String get autoConnect => _e ? 'Auto connect on startup' : '启动时自动连接';
  String get launchAtStartupLabel => _e ? 'Launch at startup' : '开机自启动';
  String get launchAtStartupSub =>
      _e ? 'Auto start YueLink at login' : '登录时自动启动 YueLink';
  String get logLevelSetting => _e ? 'Log Level' : '日志级别';
  String get configOverwrite => _e ? 'Config Overwrite' : '配置覆写';
  String get configOverwriteSub =>
      _e ? 'Add custom rules on top of subscription config' : '在订阅配置之上叠加自定义规则';
  String get updateAllNow =>
      _e ? 'Update all subscriptions now' : '立即更新所有订阅';
  String get webdavUrl => _e ? 'WebDAV URL' : 'WebDAV 地址';
  String get username => _e ? 'Username' : '用户名';
  String get password => _e ? 'Password' : '密码';
  String get testConnection => _e ? 'Test Connection' : '测试连接';
  String get themeLabel => _e ? 'Theme' : '主题';
  String get themeSystem => _e ? 'System' : '跟随系统';
  String get themeLight => _e ? 'Light' : '浅色';
  String get themeDark => _e ? 'Dark' : '深色';
  String get languageChinese => '中文';
  String get languageEnglish => 'English';
  String get coreStatus => _e ? 'Core Status' : '内核状态';
  String get coreRunning => _e ? 'Running' : '运行中';
  String get coreStopped => _e ? 'Stopped' : '已停止';
  String get runMode => _e ? 'Run Mode' : '运行模式';
  String get mixedPort => _e ? 'Mixed Port' : 'Mixed 端口';
  String get apiPort => _e ? 'API Port' : 'API 端口';
  String get dnsQuery => _e ? 'DNS Query' : 'DNS 查询';
  String get runningConfig => _e ? 'Running Config' : '运行配置';
  String get flushDnsCache => _e ? 'Flush DNS Cache' : '清除 DNS 缓存';
  String get flushFakeIpCache =>
      _e ? 'Flush Fake-IP Cache' : '清除 Fake-IP 缓存';
  String get versionLabel => _e ? 'Version' : '版本';
  String get coreLabel => _e ? 'Core' : '内核';
  String get projectHome => _e ? 'Project Home' : '项目主页';
  String get openSourceLicense =>
      _e ? 'Open Source License' : '开源许可';
  String get updatingAll =>
      _e ? 'Updating subscriptions...' : '正在更新订阅...';
  String updateAllResult(int updated, int failed) => _e
      ? 'Update done: $updated succeeded, $failed failed'
      : '更新完成：成功 $updated 个，失败 $failed 个';
  String get dnsCacheCleared =>
      _e ? 'DNS cache cleared' : 'DNS 缓存已清除';
  String get fakeIpCacheCleared =>
      _e ? 'Fake-IP cache cleared' : 'Fake-IP 缓存已清除';
  String get connectionSuccess =>
      _e ? 'Connection successful' : '连接成功';
  String get connectionFailed =>
      _e ? 'Connection failed, check URL and credentials' : '连接失败，请检查地址和凭据';
  String get uploadSuccess => _e ? 'Upload successful' : '上传成功';
  String uploadFailed(String error) =>
      _e ? 'Upload failed: $error' : '上传失败: $error';
  String get downloadSuccess =>
      _e ? 'Downloaded successfully, restart to apply' : '下载成功，重启后生效';
  String downloadFailed(String error) =>
      _e ? 'Download failed: $error' : '下载失败: $error';

  // ── Error helpers ─────────────────────────────────────────────────
  String get errorTimeout => _e ? 'Request timed out, check your network' : '请求超时，请检查网络连接';
  String get errorNetwork => _e ? 'Network error, check your connection' : '网络错误，请检查网络连接';
  String get overwritePortInvalid => _e ? 'Port must be between 1 and 65535' : '端口号必须在 1 到 65535 之间';
  String get proxyTypeAll => _e ? 'All' : '全部';

  // ── Sub-Store ─────────────────────────────────────────────────────
  String get sectionSubStore => _e ? 'Sub-Store Conversion' : 'Sub-Store 订阅转换';
  String get subStoreUrlLabel => _e ? 'Sub-Store Server URL' : 'Sub-Store 服务地址';
  String get subStoreUrlHint => _e ? 'http://127.0.0.1:25500' : 'http://127.0.0.1:25500';
  String get subStoreUrlSub =>
      _e ? 'Convert V2Ray/SS links to Clash format automatically' : '自动将 V2Ray/SS 订阅转换为 Clash 格式';
  String get subStoreUrlSaved => _e ? 'Sub-Store URL saved' : 'Sub-Store 地址已保存';

  // ── Overwrite tabs ────────────────────────────────────────────────
  String get overwriteTabBasic => _e ? 'Basic' : '基础';
  String get overwriteTabRules => _e ? 'Rules' : '规则';
  String get overwriteTabAdvanced => _e ? 'Advanced' : '高级';
  String get overwriteModeLabel => _e ? 'Override Mode' : '覆写模式';
  String get overwriteModeNone => _e ? 'No override' : '不覆写';
  String get overwritePortLabel => _e ? 'Mixed Port' : 'Mixed 端口';
  String get overwritePortHint => _e ? 'e.g. 7890 (leave blank to skip)' : '如 7890，留空则不覆写';
  String get overwriteCustomRulesLabel =>
      _e ? 'Custom Rules (prepended)' : '自定义规则（插入到订阅规则前）';
  String get overwriteAddRule => _e ? 'Add Rule' : '添加规则';
  String get overwriteRuleHint =>
      _e ? 'e.g. DOMAIN-SUFFIX,example.com,DIRECT' : '如 DOMAIN-SUFFIX,example.com,DIRECT';
  String get overwriteExtraYamlLabel =>
      _e ? 'Extra YAML (appended)' : '额外 YAML（追加到覆写末尾）';

  // ── Mode chips ────────────────────────────────────────────────────
  String get modeMock => _e ? 'Mock' : '模拟';
  String get modeSubprocess => _e ? 'Subprocess' : '子进程';

  // ── DNS query page ────────────────────────────────────────────────
  String get domainHint =>
      _e ? 'Enter domain, e.g. google.com' : '输入域名，如 google.com';
  String get query => _e ? 'Query' : '查询';
  String get noRecords => _e ? 'No records' : '无记录';

  String updateAvailableV(String v) => _e ? 'v$v available' : '发现新版本 v$v';

  // ── Proxy Provider ──────────────────────────────────────────────
  String get proxyProviderTitle => _e ? 'Proxy Providers' : '代理提供者';
  String get proxyProviderEmpty =>
      _e ? 'No proxy providers' : '无代理提供者';
  String providerNodeCount(int count) =>
      _e ? '$count nodes' : '$count 个节点';
  String get providerUpdate => _e ? 'Update' : '更新';
  String get providerHealthCheck => _e ? 'Health Check' : '健康检查';
  String get providerUpdateSuccess =>
      _e ? 'Provider updated' : '提供者已更新';
  String get providerUpdateFailed =>
      _e ? 'Provider update failed' : '提供者更新失败';
  String get providerHealthCheckDone =>
      _e ? 'Health check complete' : '健康检查完成';

  // ── Connection mode display ─────────────────────────────────────
  String get connectionModeLabel => _e ? 'Mode' : '模式';

  // ── Core error messages ───────────────────────────────────────
  String get errVpnPermission =>
      _e ? 'VPN permission denied, cannot enable TUN mode' : '缺少 VPN 权限，无法开启 TUN 模式';
  String get errCoreStartFailed =>
      _e ? 'Core failed to start, check config or port conflicts' : '内核启动失败，请检查配置格式或端口占用';
  String get errVpnTunnelFailed =>
      _e ? 'VPN tunnel setup failed' : 'VPN 隧道建立失败';
  String get msgConnected => _e ? 'Connected' : '已成功连接';
  String errApiError(int code, String body) =>
      _e ? 'API error: $code - $body' : 'API 错误: $code - $body';
  String errStartFailed(String msg) =>
      _e ? 'Start failed: $msg' : '启动失败: $msg';
  String get msgDisconnected => _e ? 'Disconnected' : '已断开连接';
  String get errStopFailed =>
      _e ? 'Error while disconnecting' : '断开连接时发生错误';
  String get errSystemProxyFailed => _e
      ? 'System proxy setup failed. Configure proxy manually at 127.0.0.1'
      : '系统代理设置失败，请手动设置代理 127.0.0.1';

  // ── Download error messages ───────────────────────────────────
  String get errDownloadTimeout =>
      _e ? 'Download timed out, check your network' : '下载超时，请检查网络连接';
  String errNetworkError(String detail) =>
      _e ? 'Network error: $detail' : '网络错误: $detail';
  String errDownloadHttpFailed(int code) =>
      _e ? 'Download failed: HTTP $code' : '下载失败: HTTP $code';

  // ── Traffic chart ────────────────────────────────────────────────
  String get chartLock => _e ? 'Lock chart' : '锁定图表';
  String get chartUnlock => _e ? 'Unlock chart' : '解锁图表';

  // ── Routing mode ─────────────────────────────────────────────────
  String get switchModeFailed => _e ? 'Mode switch failed' : '切换模式失败';

  // ── Offline preview ──────────────────────────────────────────────
  String get offlinePreview =>
      _e ? 'Offline preview — connect to switch nodes' : '离线预览 — 连接后可切换节点';

  // ── Node sort / view ─────────────────────────────────────────────
  String get sortDefault => _e ? 'Default' : '默认顺序';
  String get sortLatencyAsc => _e ? 'Latency ↑' : '延迟升序';
  String get sortLatencyDesc => _e ? 'Latency ↓' : '延迟降序';
  String get sortNameAsc => _e ? 'Name A-Z' : '名称 A-Z';
  String get nodeViewCard => _e ? 'Card view' : '卡片视图';
  String get nodeViewList => _e ? 'List view' : '列表视图';
}
