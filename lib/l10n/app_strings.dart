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

  /// Public alias — use in external files where `_e` is not accessible.
  bool get isEn => _e;

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
  String get navHome => _e ? 'Home' : '首页';
  String get navProxies => _e ? 'Lines' : '线路';
  String get navProfile => _e ? 'Subscriptions' : '订阅';
  String get navMine => _e ? 'Me' : '我的';
  String get navStore => _e ? 'Store' : '商店';
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
  String get statusConnected => _e ? 'Protected' : '保护中';
  String get statusDisconnected => _e ? 'Not Protected' : '未开启保护';
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
      _e ? 'No subscription yet — tap Sync to get started' : '暂无订阅配置，请先同步订阅';
  String get snackConfigMissing =>
      _e ? 'Config missing, please sync your subscription' : '配置文件不存在，请重新同步订阅';
  String get snackStartFailed =>
      _e ? 'Connection failed, please try again' : '连接失败，请稍后重试';

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
  String get updateDownload => _e ? 'Download & Install' : '下载安装';
  String get updateDownloading => _e ? 'Downloading...' : '正在下载...';
  String get updateDownloadComplete => _e ? 'Download complete' : '下载完成';
  String get updateDownloadFailed => _e ? 'Download failed' : '下载失败';
  String get updateInstalling => _e ? 'Opening installer...' : '正在打开安装包...';
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
  String get sectionSettings => _e ? 'General' : '通用';
  String get sectionService => _e ? 'My Subscription' : '我的订阅';
  String get sectionSupport => _e ? 'Support' : '支持';
  String get preferencesLabel => _e ? 'Preferences' : '偏好设置';
  String get sectionAccountActions => _e ? 'Account' : '账号';
  // Upstream proxy
  String get upstreamProxy => _e ? 'Upstream Proxy' : '上游代理';
  String get upstreamProxySub =>
      _e ? 'Route through a local gateway (e.g. soft router)' : '通过本地网关出站（如软路由）';
  String get upstreamProxyServer => _e ? 'Server' : '服务器地址';
  String get upstreamProxyPort => _e ? 'Port' : '端口';
  String get upstreamProxyType => _e ? 'Type' : '类型';
  String get upstreamProxySaved => _e ? 'Upstream proxy saved' : '上游代理已保存';
  String get upstreamProxyNotFound =>
      _e ? 'No proxy detected on gateway' : '未检测到网关代理';
  String get upstreamProxyHint =>
      _e ? 'Soft router IP, e.g. 192.168.1.1' : '软路由 IP，如 192.168.1.1';
  // Export logs
  String get exportLogs => _e ? 'Export Logs' : '导出日志';
  String get exportLogsCrash => _e ? 'Crash Log' : '崩溃日志';
  String get exportLogsCore => _e ? 'Core Log' : '内核日志';
  String get exportLogsEmpty => _e ? 'No log file found' : '暂无日志文件';
  String get exportLogsCopied => _e ? 'Log copied to clipboard' : '日志已复制到剪贴板';
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

  // ── Auth (悦通账号) ──────────────────────────────────────────────
  String get authLogin => _e ? 'Sign In' : '登录';
  String get authLogout => _e ? 'Sign Out' : '退出登录';
  String get authEmail => _e ? 'Email' : '邮箱';
  String get authPassword => _e ? 'Password' : '密码';
  String get authEmailHint => _e ? 'your@email.com' : '请输入邮箱';
  String get authPasswordHint => _e ? 'Enter password' : '请输入密码';
  String get authLoginSubtitle =>
      _e ? 'Sign in to your Yue.to account' : '登录悦通账号';
  String get authLoggingIn => _e ? 'Signing in...' : '登录中...';
  String get authLoginFailed => _e ? 'Login failed' : '登录失败';
  String get authLogoutConfirm =>
      _e ? 'Sign out and clear local data?' : '确定退出登录并清除本地数据？';
  String get authSyncingSubscription =>
      _e ? 'Syncing subscription...' : '正在同步订阅...';
  String get authSyncSuccess =>
      _e ? 'Subscription synced' : '订阅同步成功';
  String get authSyncFailed =>
      _e ? 'Subscription sync failed' : '订阅同步失败';
  String get authAccountInfo => _e ? 'Account' : '账号信息';
  String get authPlan => _e ? 'Plan' : '套餐';
  String get dashMyPlan => _e ? 'My Plan' : '我的套餐';
  String get authTraffic => _e ? 'Traffic' : '流量';
  String get authExpiry => _e ? 'Expiry' : '到期时间';
  String authDaysRemaining(int days) =>
      _e ? '$days days remaining' : '剩余 $days 天';
  String get authExpired => _e ? 'Expired' : '已过期';
  String get authExpiryToday => _e ? 'Expires today' : '今天到期';
  String get authRefreshInfo => _e ? 'Refresh' : '刷新';
  // Error messages — user-facing, non-technical
  String get authSessionExpired =>
      _e ? 'Session expired, please sign in again' : '登录已失效，请重新登录';
  String get authErrorBadCredentials =>
      _e ? 'Incorrect email or password' : '账号或密码错误，请重试';
  String get authErrorNetwork =>
      _e ? 'Network error, please check your connection' : '网络连接失败，请检查网络后重试';
  String get authErrorServer =>
      _e ? 'Service temporarily unavailable, please try again later' : '服务暂时不可用，请稍后重试';

  // ── Mine / Account center ────────────────────────────────────────
  String get mineTrafficTitle => _e ? 'Traffic Usage' : '流量使用';
  String get mineSpeedUp => _e ? 'Upload' : '上传';
  String get mineSpeedDown => _e ? 'Download' : '下载';
  String get mineRemaining => _e ? 'Remaining' : '剩余';
  String get mineDevices => _e ? 'Devices' : '设备在线';
  String get mineActions => _e ? 'Quick Actions' : '快捷操作';
  String get mineChangePassword => _e ? 'Change Password' : '修改密码';
  String get mineTelegramGroup => _e ? 'Join Telegram Group' : '加入 Telegram 群';
  String get mineRenew => _e ? 'Plans' : '订阅套餐';
  String get mineExpiryWarning =>
      _e ? 'Plan expiring soon — renew now' : '套餐即将到期，请及时续费';
  String get mineExpiredWarning =>
      _e ? 'Plan has expired — renew now' : '套餐已到期，请续费';
  String get mineSyncing => _e ? 'Syncing…' : '同步中…';
  String get mineSyncDone => _e ? 'Synced' : '同步成功';
  String get mineSyncFailed => _e ? 'Sync failed' : '同步失败';
  String get mineNotConnected => _e ? 'Not connected' : '未连接';
  String get mineEmby => _e ? '悦视频' : '悦视频';
  String get mineEmbyNoAccess =>
      _e ? 'No 悦视频 access for this account' : '当前账户暂无悦视频服务';
  String get mineEmbyOpening => _e ? 'Opening 悦视频…' : '正在打开悦视频…';
  String get mineEmbyOpenFailed =>
      _e ? 'Unable to open 悦视频' : '无法打开悦视频，请稍后重试';
  String get mineEmbyNeedsVpn =>
      _e ? 'Please connect first to access 悦视频' : '请先连接悦通，再访问悦视频';
  String get minePrivacyPolicy => _e ? 'Terms of Service' : '服务条款';
  String get goToHomeToProtect => _e ? 'Go to Dashboard' : '去首页开启保护';
  // First-time use
  String get syncFirstSuccess =>
      _e ? 'Subscription synced — you\'re ready to connect' : '订阅已同步，现在可以连接了';

  // ── Store / 套餐中心 ─────────────────────────────────────────────
  String get storeCurrentPlan => _e ? 'Current Plan' : '当前套餐';
  String get storeAvailablePlans => _e ? 'Available Plans' : '可购套餐';
  String get storeBuyNow => _e ? 'Buy Now' : '立即购买';
  String get storeRenew => _e ? 'Renew' : '续费';
  String get storeUpgrade => _e ? 'Upgrade' : '升级套餐';
  String get storeNoPlans => _e ? 'No plans available' : '暂无可购套餐';
  String get storeUnlimited => _e ? 'Unlimited' : '不限';
  String get storeSelectPeriod => _e ? 'Billing Period' : '计费周期';
  String get storeConfirmPurchase => _e ? 'Confirm Order' : '确认订单';
  String get storePayNow => _e ? 'Pay Now' : '前往支付';
  String get storeOrderCreating => _e ? 'Creating order...' : '创建订单中...';
  String get storeOrderSuccess => _e ? 'Payment Successful' : '购买成功';
  String get storeOrderPending => _e ? 'Awaiting Payment' : '等待支付';
  String get storeOrderFailed => _e ? 'Order Failed' : '订单失败';
  String get storeOrderCancelled => _e ? 'Order Cancelled' : '订单已取消';
  String get storeReturnToStore => _e ? 'Back to Store' : '返回套餐中心';
  String get storeRenewalReminder => _e ? 'Plan expiring soon — renew now' : '套餐即将到期，点击续费';
  String get storeExpiredReminder => _e ? 'Plan expired — buy now' : '套餐已过期，点击购买';
  String get storePlanDetail => _e ? 'Plan Details' : '套餐详情';
  String get storeCheckResult => _e ? 'Check Result' : '查询支付结果';
  String get storeCancelOrder => _e ? 'Cancel Order' : '取消订单';
  String get storeOpenPaymentPage => _e ? 'Open Payment Page' : '重新打开支付页';

  // ── Store – Coupon ────────────────────────────────────────────────
  String get storeCouponExpand => _e ? 'Have a coupon?' : '有优惠码？';
  String get storeCouponCode => _e ? 'Coupon Code' : '优惠码';
  String get storeCouponValidate => _e ? 'Apply' : '验证';
  String get storeCouponValidating => _e ? 'Validating...' : '验证中...';
  String get storeCouponValid => _e ? 'Coupon applied' : '优惠券已应用';
  String get storeCouponInvalid => _e ? 'Invalid coupon' : '优惠码无效';
  String get storeDiscount => _e ? 'Discount' : '优惠';
  String get storeActualAmount => _e ? 'You Pay' : '实付';
  String get storeCouponRemove => _e ? 'Remove' : '移除';

  // ── Store – Payment method ────────────────────────────────────────
  String get storePaymentMethod => _e ? 'Payment Method' : '支付方式';
  String get storeHandlingFee => _e ? 'Handling fee' : '手续费';

  // ── Store – Order history ─────────────────────────────────────────
  String get storeOrderHistory => _e ? 'Order History' : '订单记录';
  String get storeOrderNo => _e ? 'Order No.' : '订单号';
  String get storeOrderDate => _e ? 'Date' : '下单时间';
  String get storeNoOrders => _e ? 'No orders yet' : '暂无订单记录';
  String get storeOrderDetail => _e ? 'Order Detail' : '订单详情';
  String get storeOrderStatusPending => _e ? 'Pending' : '待支付';
  String get storeOrderStatusProcessing => _e ? 'Processing' : '处理中';
  String get storeOrderStatusCancelled => _e ? 'Cancelled' : '已取消';
  String get storeOrderStatusCompleted => _e ? 'Completed' : '已完成';

  // ── Dashboard – 悦通专属区 ────────────────────────────────────────
  String get dashSyncLabel => _e ? 'Update Lines' : '更新线路';
  String get dashAnnouncementsLabel => _e ? 'Announcements' : '最新公告';
  String get mineSyncLine => _e ? 'Sync Lines' : '同步线路';
  String get mineSubscriptionManage =>
      _e ? 'Subscription Management' : '订阅管理';
  String get dashAccountLabel => _e ? 'Account' : '账户';
  String get dashLatestAnnouncement => _e ? 'Latest Announcements' : '最新公告';
  String get noNetworkConnection => _e ? 'No network connection' : '网络连接不可用';
  String get dashGreeting => _e ? 'Hello' : '你好';
  String get dashGreetingReturning => _e ? 'Welcome back' : '欢迎回来';
  String get dashNoAnnouncements => _e ? 'No announcements' : '暂无公告';
  String get dashViewAll => _e ? 'View all' : '查看全部';
  String get dashNoPlan => _e ? 'No plan info' : '暂无套餐信息';

  // ── Change password dialog ──────────────────────────────────────
  String get oldPassword => _e ? 'Old Password' : '旧密码';
  String get newPassword => _e ? 'New Password' : '新密码';
  String get passwordChangedSuccess =>
      _e ? 'Password changed successfully' : '密码修改成功';
  String get passwordChangeFailed =>
      _e ? 'Password change failed' : '密码修改失败';

  // ── Sync subscription (nodes page) ─────────────────────────────
  String get syncing => _e ? 'Syncing...' : '同步中...';
  String get syncComplete => _e ? 'Sync complete' : '同步完成';
  String get syncFailed => _e ? 'Sync failed' : '同步失败';
  String get notConnected => _e ? 'Not connected' : '未连接';

  // ── Profile switch confirmation ──────────────────────────────
  String get switchProfileTitle => _e ? 'Switch Subscription' : '切换订阅';
  String switchProfileMessage(String name) => _e
      ? 'Switch to "$name"? This will use its nodes and rules.'
      : '切换到「$name」？将使用该订阅的节点和规则。';
  String get switchProfileReconnectHint => _e
      ? 'VPN is running. You need to reconnect after switching.'
      : 'VPN 正在运行中，切换后需要重新连接才能生效。';
  String get switchProfileConfirm => _e ? 'Switch' : '确认切换';

  // ── Onboarding ──────────────────────────────────────────────
  String get onboardingWelcome => _e ? 'Welcome to YueLink' : '欢迎使用悦通';
  String get onboardingWelcomeDesc => _e
      ? 'A modern proxy client for secure and fast internet access.'
      : '一款现代化的代理客户端，安全高速地访问互联网。';
  String get onboardingConnect => _e ? 'One-Tap Connect' : '一键连接';
  String get onboardingConnectDesc => _e
      ? 'Tap the power button on the home page to connect instantly.'
      : '在首页点击电源按钮即可快速连接。';
  String get onboardingNodes => _e ? 'Choose Your Line' : '选择线路';
  String get onboardingNodesDesc => _e
      ? 'Switch between nodes on the Lines page for the best speed.'
      : '在线路页面切换节点，选择最快的线路。';
  String get onboardingStore => _e ? 'Get a Plan' : '购买套餐';
  String get onboardingStoreDesc => _e
      ? 'Visit the Store to subscribe and start using the service.'
      : '前往商店页面订阅套餐，开始使用服务。';
  String get onboardingSkip => _e ? 'Skip' : '跳过';
  String get onboardingNext => _e ? 'Next' : '下一步';
  String get onboardingDone => _e ? 'Get Started' : '开始使用';

  // ── Chain proxy ──────────────────────────────────────────────
  String get chainProxy => _e ? 'Proxy Chain' : '链式代理';
  String get chainEntry => _e ? 'Entry' : '入口';
  String get chainExit => _e ? 'Exit' : '出口';
  String get chainConnect => _e ? 'Connect Chain' : '连接链路';
  String get chainDisconnect => _e ? 'Disconnect' : '断开链路';
  String get chainConnected => _e ? 'Proxy chain connected' : '链式代理已连接';
  String get chainDisconnected => _e ? 'Proxy chain disconnected' : '链式代理已断开';
  String get chainConnectFailed => _e ? 'Chain connect failed' : '链路连接失败';
  String get chainNeedConnect => _e ? 'Connect VPN first' : '请先连接 VPN';
  String get chainNoGroup => _e ? 'No proxy group available' : '未找到可用策略组';
  String get chainNeedTwoNodes => _e ? 'Need 2+ nodes' : '至少需要 2 个节点';
  String get chainNodeDuplicate => _e ? 'Node already in chain' : '节点已在链路中';
  String get chainClear => _e ? 'Clear' : '清空';
  String get chainEmptyHint => _e ? 'No nodes in chain' : '暂无链路节点';
  String get chainEmptyDesc => _e
      ? 'Long-press any node or group on the Lines page to add it'
      : '在线路页面长按节点或策略组即可加入链路';
  String get chainAddHint => _e ? 'Added to proxy chain' : '已添加到链式代理';
  String get chainPickerTitle => _e ? 'Add to Chain' : '添加到链路';
  String get chainPickerSearch => _e ? 'Search nodes / groups...' : '搜索节点 / 策略组…';
  String get chainSectionGroups => _e ? 'Proxy Groups' : '策略组';
  String get chainSectionNodes => _e ? 'Nodes' : '节点';
  String get msgSystemProxyConflict => _e
      ? 'Another proxy client took over — stopping YueLink proxy'
      : '检测到其他代理客户端已接管系统代理，已停止 YueLink 代理';

  // ── Checkin ──────────────────────────────────────────────────
  String get checkinTitle => _e ? 'Daily Check-in' : '每日签到';
  String get checkinDesc => _e
      ? 'Check in to get traffic or balance rewards'
      : '签到领取流量或余额奖励';
  String get checkinAction => _e ? 'Check in' : '签到';
  String get checkinDone => _e ? 'Checked in' : '已签到';
  String get checkinAlready => _e ? 'Already checked in today' : '今日已签到';
  String get checkinOtherDevice =>
      _e ? 'Checked in on another device' : '已在其他设备签到';
  String get checkinNeedLogin => _e ? 'Please login first' : '请先登录';
  String get checkinFailed => _e ? 'Check-in failed' : '签到失败';
  String get checkinReward => _e ? 'Reward' : '奖励';
  String checkinTrafficReward(String amount) =>
      _e ? 'Got $amount traffic!' : '获得 $amount 流量！';
  String checkinBalanceReward(String amount) =>
      _e ? 'Got ¥$amount balance!' : '获得 ¥$amount 余额！';
}
