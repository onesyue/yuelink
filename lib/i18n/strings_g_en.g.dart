///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings_g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations

	/// en: 'Home'
	String get navHome => 'Home';

	/// en: 'Lines'
	String get navProxies => 'Lines';

	/// en: 'Subscriptions'
	String get navProfile => 'Subscriptions';

	/// en: 'Me'
	String get navMine => 'Me';

	/// en: 'Store'
	String get navStore => 'Store';

	/// en: 'Media'
	String get navEmby => 'Media';

	/// en: 'Connections'
	String get navConnections => 'Connections';

	/// en: 'Logs'
	String get navLog => 'Logs';

	/// en: 'Settings'
	String get navSettings => 'Settings';

	/// en: 'Connect'
	String get trayConnect => 'Connect';

	/// en: 'Disconnect'
	String get trayDisconnect => 'Disconnect';

	/// en: 'Show Window'
	String get trayShowWindow => 'Show Window';

	/// en: 'Quit'
	String get trayQuit => 'Quit';

	/// en: 'Quick Switch'
	String get trayProxies => 'Quick Switch';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'OK'
	String get confirm => 'OK';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Add'
	String get add => 'Add';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Saved'
	String get saved => 'Saved';

	/// en: 'Upload'
	String get upload => 'Upload';

	/// en: 'Download'
	String get download => 'Download';

	/// en: 'Operation failed'
	String get operationFailed => 'Operation failed';

	/// en: 'No data'
	String get noData => 'No data';

	/// en: 'Connection dropped'
	String get disconnectedUnexpected => 'Connection dropped';

	/// en: 'Subscription "{name}" has expired'
	String subExpired({required Object name}) => 'Subscription "${name}" has expired';

	/// en: 'Subscription "{name}" expires in {days} day(s)'
	String subExpiringSoon({required Object name, required Object days}) => 'Subscription "${name}" expires in ${days} day(s)';

	/// en: 'Today'
	String get todayUsage => 'Today';

	/// en: 'Protected'
	String get statusConnected => 'Protected';

	/// en: 'Not Protected'
	String get statusDisconnected => 'Not Protected';

	/// en: 'Connecting...'
	String get statusConnecting => 'Connecting...';

	/// en: 'Processing...'
	String get statusProcessing => 'Processing...';

	/// en: 'Disconnecting...'
	String get statusDisconnecting => 'Disconnecting...';

	/// en: 'Connect'
	String get btnConnect => 'Connect';

	/// en: 'Disconnect'
	String get btnDisconnect => 'Disconnect';

	/// en: 'Connecting'
	String get btnConnecting => 'Connecting';

	/// en: 'Disconnecting'
	String get btnDisconnecting => 'Disconnecting';

	/// en: 'Rule'
	String get routeModeRule => 'Rule';

	/// en: 'Global'
	String get routeModeGlobal => 'Global';

	/// en: 'Direct'
	String get routeModeDirect => 'Direct';

	/// en: 'Routing Mode'
	String get routingModeSetting => 'Routing Mode';

	/// en: 'Tap to switch routing mode'
	String get tipTapToSwitchRouting => 'Tap to switch routing mode';

	/// en: 'Tap to switch connection mode'
	String get tipTapToSwitchConnection => 'Tap to switch connection mode';

	/// en: 'Mode switched'
	String get modeSwitched => 'Mode switched';

	/// en: 'All traffic connects directly without proxy'
	String get directModeDesc => 'All traffic connects directly without proxy';

	/// en: 'All traffic routes through the selected node below'
	String get globalModeDesc => 'All traffic routes through the selected node below';

	/// en: 'Upload'
	String get trafficUpload => 'Upload';

	/// en: 'Download'
	String get trafficDownload => 'Download';

	/// en: 'Memory'
	String get trafficMemory => 'Memory';

	/// en: 'Connections'
	String get activeConns => 'Connections';

	/// en: 'Dev Mode · Mock Data'
	String get mockModeBanner => 'Dev Mode · Mock Data';

	/// en: 'Mock Mode'
	String get mockModeLabel => 'Mock Mode';

	/// en: 'Click Connect to start mock mode'
	String get mockHint => 'Click Connect to start mock mode';

	/// en: 'DASHBOARD'
	String get dashboardLabel => 'DASHBOARD';

	/// en: 'Calm network control.'
	String get dashboardTitle => 'Calm network control.';

	/// en: 'Switch node'
	String get switchNode => 'Switch node';

	/// en: 'Live connection'
	String get liveConnection => 'Live connection';

	/// en: 'Your traffic is routed through a healthy node with low latency.'
	String get dashConnectedDesc => 'Your traffic is routed through a healthy node with low latency.';

	/// en: 'Not connected'
	String get dashDisconnectedTitle => 'Not connected';

	/// en: 'Click Connect to start routing traffic through a proxy node.'
	String get dashDisconnectedDesc => 'Click Connect to start routing traffic through a proxy node.';

	/// en: 'Realtime traffic'
	String get realtimeTraffic => 'Realtime traffic';

	/// en: 'Current Node'
	String get nodeLabel => 'Current Node';

	/// en: 'Outbound IP'
	String get exitIpLabel => 'Outbound IP';

	/// en: 'Routing Mode'
	String get routingLabel => 'Routing Mode';

	/// en: 'Tap to query'
	String get exitIpTapToQuery => 'Tap to query';

	/// en: 'Querying...'
	String get exitIpQuerying => 'Querying...';

	/// en: 'Query failed'
	String get exitIpFailed => 'Query failed';

	/// en: 'System Proxy'
	String get systemProxy => 'System Proxy';

	/// en: 'System proxy enabled'
	String get systemProxyOn => 'System proxy enabled';

	/// en: 'System proxy off'
	String get systemProxyOff => 'System proxy off';

	/// en: 'Traffic activity'
	String get trafficActivity => 'Traffic activity';

	/// en: 'Last 60 seconds'
	String get last60s => 'Last 60 seconds';

	/// en: 'Ready to connect. Tap the power button to start.'
	String get dashReadyHint => 'Ready to connect. Tap the power button to start.';

	/// en: 'No profile selected. Add one in Profiles first.'
	String get dashNoProfileHint => 'No profile selected. Add one in Profiles first.';

	/// en: 'Auto-connect: On'
	String get dashAutoConnectOn => 'Auto-connect: On';

	/// en: 'Auto-connect: Off'
	String get dashAutoConnectOff => 'Auto-connect: Off';

	/// en: 'Add a subscription in the Profiles page first'
	String get noProfileHint => 'Add a subscription in the Profiles page first';

	/// en: 'No subscription yet — tap Sync to get started'
	String get snackNoProfile => 'No subscription yet — tap Sync to get started';

	/// en: 'Config missing, please sync your subscription'
	String get snackConfigMissing => 'Config missing, please sync your subscription';

	/// en: 'Connection failed, please try again'
	String get snackStartFailed => 'Connection failed, please try again';

	/// en: 'Network Permission Required'
	String get vpnPermTitle => 'Network Permission Required';

	/// en: 'YueLink needs to set up a secure tunnel to route your traffic. No personal data is sent to our servers — all processing happens on your device. Tap "Continue" to grant the permission.'
	String get vpnPermBody => 'YueLink needs to set up a secure tunnel to route your traffic. No personal data is sent to our servers — all processing happens on your device.\n\nTap "Continue" to grant the permission.';

	/// en: 'Continue'
	String get vpnPermContinue => 'Continue';

	/// en: 'Allow VPN Access'
	String get vpnPermIosTitle => 'Allow VPN Access';

	/// en: 'iOS will now ask for permission to add a VPN configuration. This is normal and required for any VPN app.'
	String get vpnPermIosIntro => 'iOS will now ask for permission to add a VPN configuration. This is normal and required for any VPN app.';

	/// en: 'A system dialog will appear titled "YueLink Would Like to Add VPN Configurations".'
	String get vpnPermIosStep1 => 'A system dialog will appear titled "YueLink Would Like to Add VPN Configurations".';

	/// en: 'Tap "Allow" to confirm. iOS may ask for your device passcode or Face ID.'
	String get vpnPermIosStep2 => 'Tap "Allow" to confirm. iOS may ask for your device passcode or Face ID.';

	/// en: 'All traffic stays on your device — YueLink does not send your data to any external server.'
	String get vpnPermIosStep3 => 'All traffic stays on your device — YueLink does not send your data to any external server.';

	/// en: 'I Understand, Continue'
	String get vpnPermIosContinue => 'I Understand, Continue';

	/// en: 'Fix macOS Launch Block'
	String get gatekeeperFixTitle => 'Fix macOS Launch Block';

	/// en: 'Remove Apple's quarantine flag'
	String get gatekeeperFixSubtitle => 'Remove Apple\'s quarantine flag';

	/// en: 'Repair macOS Gatekeeper'
	String get gatekeeperFixDialogTitle => 'Repair macOS Gatekeeper';

	/// en: 'macOS attaches a quarantine flag to apps downloaded from the internet, which can cause repeated "YueLink can't be opened" warnings on every update. This will remove the flag from /Applications/YueLink.app and ask for your administrator password.'
	String get gatekeeperFixDialogBody => 'macOS attaches a quarantine flag to apps downloaded from the internet, which can cause repeated "YueLink can\'t be opened" warnings on every update. This will remove the flag from /Applications/YueLink.app and ask for your administrator password.';

	/// en: 'Fix Now'
	String get gatekeeperFixConfirm => 'Fix Now';

	/// en: 'Repairing… (please complete the password prompt)'
	String get gatekeeperFixRunning => 'Repairing… (please complete the password prompt)';

	/// en: 'Repair complete. Future updates will launch without warnings.'
	String get gatekeeperFixSuccess => 'Repair complete. Future updates will launch without warnings.';

	/// en: 'Repair did not complete. You can also run the fix-gatekeeper.command script from the DMG.'
	String get gatekeeperFixFailed => 'Repair did not complete. You can also run the fix-gatekeeper.command script from the DMG.';

	/// en: 'This option is only available on the macOS .app build.'
	String get gatekeeperFixUnsupported => 'This option is only available on the macOS .app build.';

	/// en: 'Connect first to view proxy nodes'
	String get notConnectedHintProxy => 'Connect first to view proxy nodes';

	/// en: 'Connect to the core to view and manage proxies.'
	String get connectToViewProxiesDesc => 'Connect to the core to view and manage proxies.';

	/// en: '{n} Nodes'
	String nodesCountLabel({required Object n}) => '${n} Nodes';

	/// en: 'Switched to {name}'
	String switchedTo({required Object name}) => 'Switched to ${name}';

	/// en: 'Failed to switch node'
	String get switchFailed => 'Failed to switch node';

	/// en: 'Testing {name}...'
	String testingGroup({required Object name}) => 'Testing ${name}...';

	/// en: 'Direct / Auto'
	String get directAuto => 'Direct / Auto';

	/// en: 'Search nodes...'
	String get searchNodesHint => 'Search nodes...';

	/// en: 'Sort by delay'
	String get sortByDelay => 'Sort by delay';

	/// en: 'Cancel sort'
	String get cancelSort => 'Cancel sort';

	/// en: 'Speed Test URL'
	String get testUrlSettings => 'Speed Test URL';

	/// en: 'Reset to Default'
	String get resetDefault => 'Reset to Default';

	/// en: 'Unsaved Changes'
	String get unsavedChanges => 'Unsaved Changes';

	/// en: 'Leave and discard unsaved changes?'
	String get unsavedChangesBody => 'Leave and discard unsaved changes?';

	/// en: 'Discard & Leave'
	String get discardAndLeave => 'Discard & Leave';

	/// en: 'Stay'
	String get stayOnPage => 'Stay';

	/// en: 'No matching nodes'
	String get noMatchingNodes => 'No matching nodes';

	/// en: 'Speed Test URL'
	String get testUrlDialogTitle => 'Speed Test URL';

	/// en: 'Custom URL'
	String get customUrlLabel => 'Custom URL';

	/// en: 'Manual'
	String get typeManual => 'Manual';

	/// en: 'Auto'
	String get typeAuto => 'Auto';

	/// en: 'Fallback'
	String get typeFallback => 'Fallback';

	/// en: 'Load Balance'
	String get typeLoadBalance => 'Load Balance';

	/// en: 'Test All'
	String get testAll => 'Test All';

	/// en: 'Testing ({n})'
	String testingCount({required Object n}) => 'Testing (${n})';

	/// en: '{visible}/{total} nodes'
	String nodesCount({required Object visible, required Object total}) => '${visible}/${total} nodes';

	/// en: 'Load failed: {error}'
	String loadFailed({required Object error}) => 'Load failed: ${error}';

	/// en: 'No subscriptions'
	String get noProfiles => 'No subscriptions';

	/// en: 'Click the button below to add a subscription'
	String get addSubscriptionHint => 'Click the button below to add a subscription';

	/// en: 'Paste from clipboard'
	String get pasteFromClipboard => 'Paste from clipboard';

	/// en: 'Add Subscription'
	String get addSubscription => 'Add Subscription';

	/// en: 'Downloading subscription...'
	String get downloadingSubscription => 'Downloading subscription...';

	/// en: 'Updating subscription...'
	String get updatingSubscription => 'Updating subscription...';

	/// en: 'Updated successfully'
	String get updateSuccess => 'Updated successfully';

	/// en: 'Update failed: {error}'
	String updateFailed({required Object error}) => 'Update failed: ${error}';

	/// en: 'Confirm Delete'
	String get confirmDelete => 'Confirm Delete';

	/// en: 'Are you sure to delete "{name}"?'
	String confirmDeleteMessage({required Object name}) => 'Are you sure to delete "${name}"?';

	/// en: 'Add Subscription'
	String get addSubscriptionDialogTitle => 'Add Subscription';

	/// en: 'Edit Subscription'
	String get editSubscriptionDialogTitle => 'Edit Subscription';

	/// en: 'Name'
	String get nameLabel => 'Name';

	/// en: 'My Subscription'
	String get nameHint => 'My Subscription';

	/// en: 'Subscription URL'
	String get urlLabel => 'Subscription URL';

	/// en: 'Update Interval'
	String get updateInterval => 'Update Interval';

	/// en: 'Default (24h)'
	String get followGlobal => 'Default (24h)';

	/// en: '7 days'
	String get days7 => '7 days';

	/// en: '6 hours'
	String get hours6 => '6 hours';

	/// en: '12 hours'
	String get hours12 => '12 hours';

	/// en: '24 hours'
	String get hours24 => '24 hours';

	/// en: '48 hours'
	String get hours48 => '48 hours';

	/// en: 'Used {used} / {total}'
	String usageLabel({required Object used, required Object total}) => 'Used ${used} / ${total}';

	/// en: 'Expired'
	String get expired => 'Expired';

	/// en: '{days} days left'
	String daysRemaining({required Object days}) => '${days} days left';

	/// en: 'Needs update'
	String get needsUpdate => 'Needs update';

	/// en: 'Updated at {time}'
	String updatedAt({required Object time}) => 'Updated at ${time}';

	/// en: 'Config file not found'
	String get noConfig => 'Config file not found';

	/// en: 'Copy config'
	String get copyConfig => 'Copy config';

	/// en: 'Config copied'
	String get copiedConfig => 'Config copied';

	/// en: 'Copy link'
	String get copyLink => 'Copy link';

	/// en: 'Subscription link copied'
	String get copiedLink => 'Subscription link copied';

	/// en: 'View config'
	String get viewConfig => 'View config';

	/// en: 'Update subscription'
	String get updateSubscription => 'Update subscription';

	/// en: 'No valid subscription URL in clipboard'
	String get clipboardNoUrl => 'No valid subscription URL in clipboard';

	/// en: 'Added successfully'
	String get addSuccess => 'Added successfully';

	/// en: 'Failed to add: {error}'
	String addFailed({required Object error}) => 'Failed to add: ${error}';

	/// en: 'Import local file'
	String get importLocalFile => 'Import local file';

	/// en: 'Imported successfully'
	String get importLocalFileSuccess => 'Imported successfully';

	/// en: 'Import failed: no valid YAML file selected'
	String get importLocalFileFailed => 'Import failed: no valid YAML file selected';

	/// en: 'My Config'
	String get importLocalNameHint => 'My Config';

	/// en: 'Export config'
	String get exportProfile => 'Export config';

	/// en: 'Exported: {name}.yaml'
	String exportProfileSuccess({required Object name}) => 'Exported: ${name}.yaml';

	/// en: 'Export all configs'
	String get exportAllProfiles => 'Export all configs';

	/// en: 'Import config files'
	String get importMultipleFiles => 'Import config files';

	/// en: 'Export failed'
	String get exportFailed => 'Export failed';

	/// en: 'Select export folder'
	String get exportSelectDir => 'Select export folder';

	/// en: 'Exported {count} YAML files'
	String exportAllDone({required Object count}) => 'Exported ${count} YAML files';

	/// en: 'Import failed: invalid backup file'
	String get importBundleFailed => 'Import failed: invalid backup file';

	/// en: 'Split Tunneling'
	String get sectionSplitTunnel => 'Split Tunneling';

	/// en: 'Mode'
	String get splitTunnelMode => 'Mode';

	/// en: 'All apps'
	String get splitTunnelModeAll => 'All apps';

	/// en: 'Proxy listed apps only'
	String get splitTunnelModeWhitelist => 'Proxy listed apps only';

	/// en: 'Bypass listed apps'
	String get splitTunnelModeBlacklist => 'Bypass listed apps';

	/// en: 'App List'
	String get splitTunnelApps => 'App List';

	/// en: 'Manage Apps'
	String get splitTunnelManage => 'Manage Apps';

	/// en: 'Search apps...'
	String get splitTunnelSearchHint => 'Search apps...';

	/// en: 'Changes take effect on next connect'
	String get splitTunnelEffectHint => 'Changes take effect on next connect';

	/// en: 'Geo Resources'
	String get sectionGeoResources => 'Geo Resources';

	/// en: 'Required geo database files for rule-based routing'
	String get geoResourcesHint => 'Required geo database files for rule-based routing';

	/// en: 'Update All'
	String get geoUpdateAll => 'Update All';

	/// en: 'Geo resources updated'
	String get geoUpdateSuccess => 'Geo resources updated';

	/// en: 'Update failed'
	String get geoUpdateFailed => 'Update failed';

	/// en: 'Not found'
	String get geoNotFound => 'Not found';

	/// en: 'Start Failed'
	String get rollbackTitle => 'Start Failed';

	/// en: 'The configuration failed to start. Rollback to the last known-good config?'
	String get rollbackContent => 'The configuration failed to start. Rollback to the last known-good config?';

	/// en: 'Rollback'
	String get rollbackConfirm => 'Rollback';

	/// en: 'Rolled back successfully'
	String get rollbackSuccess => 'Rolled back successfully';

	/// en: 'Rollback failed'
	String get rollbackFailed => 'Rollback failed';

	/// en: 'Check for Updates'
	String get checkUpdate => 'Check for Updates';

	/// en: 'New version available'
	String get updateAvailable => 'New version available';

	/// en: 'Download & Install'
	String get updateDownload => 'Download & Install';

	/// en: 'Downloading...'
	String get updateDownloading => 'Downloading...';

	/// en: 'Download complete'
	String get updateDownloadComplete => 'Download complete';

	/// en: 'Download failed'
	String get updateDownloadFailed => 'Download failed';

	/// en: 'Opening installer...'
	String get updateInstalling => 'Opening installer...';

	/// en: 'Already up to date'
	String get alreadyLatest => 'Already up to date';

	/// en: 'Failed to check for updates'
	String get updateCheckFailed => 'Failed to check for updates';

	/// en: 'Invalid YAML syntax'
	String get yamlInvalid => 'Invalid YAML syntax';

	/// en: 'Global Hotkeys'
	String get sectionHotkeys => 'Global Hotkeys';

	/// en: 'Toggle connection (Ctrl+Alt+C)'
	String get hotkeyToggle => 'Toggle connection (Ctrl+Alt+C)';

	/// en: 'Available on macOS and Windows'
	String get hotkeyHint => 'Available on macOS and Windows';

	/// en: 'Connect first to view active connections'
	String get notConnectedHintConnections => 'Connect first to view active connections';

	/// en: 'Search target, process, rule...'
	String get searchConnHint => 'Search target, process, rule...';

	/// en: 'Close All'
	String get closeAll => 'Close All';

	/// en: '{count} connections'
	String connectionsCount({required Object count}) => '${count} connections';

	/// en: '{count} connections (filtered)'
	String connectionsCountFiltered({required Object count}) => '${count} connections (filtered)';

	/// en: 'No active connections'
	String get noActiveConnections => 'No active connections';

	/// en: 'No matching results'
	String get noMatchingConnections => 'No matching results';

	/// en: 'Close All Connections'
	String get closeAllDialogTitle => 'Close All Connections';

	/// en: 'Are you sure to close all active connections?'
	String get closeAllDialogMessage => 'Are you sure to close all active connections?';

	/// en: 'Connections'
	String get statConnections => 'Connections';

	/// en: 'Total Download'
	String get statTotalDownload => 'Total Download';

	/// en: 'Total Upload'
	String get statTotalUpload => 'Total Upload';

	/// en: 'Connection Details'
	String get connectionDetailTitle => 'Connection Details';

	/// en: 'Target'
	String get detailTarget => 'Target';

	/// en: 'Protocol'
	String get detailProtocol => 'Protocol';

	/// en: 'Source'
	String get detailSource => 'Source';

	/// en: 'Target IP'
	String get detailTargetIp => 'Target IP';

	/// en: 'Proxy Chain'
	String get detailProxyChain => 'Proxy Chain';

	/// en: 'Rule'
	String get detailRule => 'Rule';

	/// en: 'Process'
	String get detailProcess => 'Process';

	/// en: 'Duration'
	String get detailDuration => 'Duration';

	/// en: 'Download'
	String get detailDownload => 'Download';

	/// en: 'Upload'
	String get detailUpload => 'Upload';

	/// en: 'Connect Time'
	String get detailConnectTime => 'Connect Time';

	/// en: 'Connect first to view logs'
	String get notConnectedHintLog => 'Connect first to view logs';

	/// en: 'Logs'
	String get tabLogs => 'Logs';

	/// en: 'Rules'
	String get tabRules => 'Rules';

	/// en: 'Search logs...'
	String get searchLogsHint => 'Search logs...';

	/// en: 'Regex pattern...'
	String get searchLogsRegexHint => 'Regex pattern...';

	/// en: 'Toggle regex search'
	String get regexSearch => 'Toggle regex search';

	/// en: 'Clear logs'
	String get clearLogs => 'Clear logs';

	/// en: 'No logs'
	String get noLogs => 'No logs';

	/// en: '{count} logs'
	String logsCount({required Object count}) => '${count} logs';

	/// en: 'Level: {level}'
	String logLevelLabel({required Object level}) => 'Level: ${level}';

	/// en: '{count} rules'
	String rulesCount({required Object count}) => '${count} rules';

	/// en: '{count} matched'
	String matchedRulesCount({required Object count}) => '${count} matched';

	/// en: 'Search rules...'
	String get searchRulesHint => 'Search rules...';

	/// en: 'No matching rules'
	String get noMatchingRules => 'No matching rules';

	/// en: 'Config Overwrite'
	String get overwriteTitle => 'Config Overwrite';

	/// en: 'Overwrite Rules'
	String get overwriteRulesTitle => 'Overwrite Rules';

	/// en: '• Scalar keys (mode, log-level, etc.) replace values in the subscription config • rules list is prepended before subscription rules • proxies / proxy-groups lists are appended after the subscription • dns / tun / sniffer / hosts / listeners blocks are merged into existing sections'
	String get overwriteRulesDescription => '• Scalar keys (mode, log-level, etc.) replace values in the subscription config\n• rules list is prepended before subscription rules\n• proxies / proxy-groups lists are appended after the subscription\n• dns / tun / sniffer / hosts / listeners blocks are merged into existing sections';

	/// en: '# Example: # mode: rule # rules: # - DOMAIN-SUFFIX,example.com,DIRECT'
	String get overwriteHintText => '# Example:\n# mode: rule\n# rules:\n#   - DOMAIN-SUFFIX,example.com,DIRECT';

	/// en: 'Saved, will take effect on next connect'
	String get savedNextConnect => 'Saved, will take effect on next connect';

	/// en: 'Connection'
	String get sectionConnection => 'Connection';

	/// en: 'Core'
	String get sectionCore => 'Core';

	/// en: 'Subscription'
	String get sectionSubscription => 'Subscription';

	/// en: 'Appearance'
	String get sectionAppearance => 'Appearance';

	/// en: 'Status'
	String get sectionStatus => 'Status';

	/// en: 'Tools'
	String get sectionTools => 'Tools';

	/// en: 'About'
	String get sectionAbout => 'About';

	/// en: 'Settings'
	String get sectionSettings => 'Settings';

	/// en: 'My Subscription'
	String get sectionService => 'My Subscription';

	/// en: 'Support'
	String get sectionSupport => 'Support';

	/// en: 'Preferences'
	String get preferencesLabel => 'Preferences';

	/// en: 'Account'
	String get sectionAccountActions => 'Account';

	/// en: 'Upstream Proxy'
	String get upstreamProxy => 'Upstream Proxy';

	/// en: 'Route through a local gateway (e.g. soft router)'
	String get upstreamProxySub => 'Route through a local gateway (e.g. soft router)';

	/// en: 'Server'
	String get upstreamProxyServer => 'Server';

	/// en: 'Port'
	String get upstreamProxyPort => 'Port';

	/// en: 'Type'
	String get upstreamProxyType => 'Type';

	/// en: 'Upstream proxy saved'
	String get upstreamProxySaved => 'Upstream proxy saved';

	/// en: 'No proxy detected on gateway'
	String get upstreamProxyNotFound => 'No proxy detected on gateway';

	/// en: 'Soft router IP, e.g. 192.168.1.1'
	String get upstreamProxyHint => 'Soft router IP, e.g. 192.168.1.1';

	/// en: 'Export Logs'
	String get exportLogs => 'Export Logs';

	/// en: 'Crash Log'
	String get exportLogsCrash => 'Crash Log';

	/// en: 'Core Log'
	String get exportLogsCore => 'Core Log';

	/// en: 'No log file found'
	String get exportLogsEmpty => 'No log file found';

	/// en: 'Log copied to clipboard'
	String get exportLogsCopied => 'Log copied to clipboard';

	/// en: 'Logs exported'
	String get exportLogsSuccess => 'Logs exported';

	/// en: 'Export failed'
	String get exportLogsFailed => 'Export failed';

	/// en: 'Desktop'
	String get sectionDesktop => 'Desktop';

	/// en: 'Network'
	String get sectionNetwork => 'Network';

	/// en: 'Close Window'
	String get closeWindowBehavior => 'Close Window';

	/// en: 'Minimize to tray'
	String get closeBehaviorTray => 'Minimize to tray';

	/// en: 'Exit application'
	String get closeBehaviorExit => 'Exit application';

	/// en: 'Toggle Connection Hotkey'
	String get toggleConnectionHotkey => 'Toggle Connection Hotkey';

	/// en: 'Edit'
	String get hotkeyEdit => 'Edit';

	/// en: 'Press a key combination...'
	String get hotkeyListening => 'Press a key combination...';

	/// en: 'Hotkey saved'
	String get hotkeySaved => 'Hotkey saved';

	/// en: 'Failed to register hotkey'
	String get hotkeyFailed => 'Failed to register hotkey';

	/// en: 'Geo Database'
	String get geoDatabase => 'Geo Database';

	/// en: 'Update Now'
	String get geoUpdateNow => 'Update Now';

	/// en: 'Geo database updated'
	String get geoUpdated => 'Geo database updated';

	/// en: 'Updated: {date}'
	String geoLastUpdated({required Object date}) => 'Updated: ${date}';

	/// en: 'System proxy not managed automatically on Linux'
	String get linuxProxyNotice => 'System proxy not managed automatically on Linux';

	/// en: 'Manual proxy: 127.0.0.1:7890'
	String get linuxProxyManual => 'Manual proxy: 127.0.0.1:7890';

	/// en: 'Not supported on all Linux desktops'
	String get hotkeyLinuxNotice => 'Not supported on all Linux desktops';

	/// en: 'Diagnostics'
	String get diagnostics => 'Diagnostics';

	/// en: 'View startup report'
	String get viewStartupReport => 'View startup report';

	/// en: 'Copied to clipboard'
	String get copiedToClipboard => 'Copied to clipboard';

	/// en: 'Language'
	String get sectionLanguage => 'Language';

	/// en: 'Connection Mode'
	String get connectionMode => 'Connection Mode';

	/// en: 'QUIC Policy'
	String get quicPolicyLabel => 'QUIC Policy';

	/// en: 'Standard (Recommended)'
	String get quicPolicyStandard => 'Standard (Recommended)';

	/// en: 'Only disables QUIC for YouTube video traffic so most services keep HTTP/3 while YouTube falls back to TCP.'
	String get quicPolicyStandardDesc => 'Only disables QUIC for YouTube video traffic so most services keep HTTP/3 while YouTube falls back to TCP.';

	/// en: 'Compatibility'
	String get quicPolicyCompatibility => 'Compatibility';

	/// en: 'Does not block QUIC. Best for MyTV Super and other Hong Kong streaming unlock scenarios.'
	String get quicPolicyCompatibilityDesc => 'Does not block QUIC. Best for MyTV Super and other Hong Kong streaming unlock scenarios.';

	/// en: 'Force Fallback'
	String get quicPolicyForceFallback => 'Force Fallback';

	/// en: 'Rejects all UDP:443 traffic to force TCP fallback. Use only for troubleshooting video playback issues.'
	String get quicPolicyForceFallbackDesc => 'Rejects all UDP:443 traffic to force TCP fallback. Use only for troubleshooting video playback issues.';

	/// en: 'TUN Mode'
	String get modeTun => 'TUN Mode';

	/// en: 'System Proxy'
	String get modeSystemProxy => 'System Proxy';

	/// en: 'Service Mode'
	String get serviceModeLabel => 'Service Mode';

	/// en: 'Install Service'
	String get serviceModeInstall => 'Install Service';

	/// en: 'Uninstall'
	String get serviceModeUninstall => 'Uninstall';

	/// en: 'Refresh'
	String get serviceModeRefresh => 'Refresh';

	/// en: 'Privileged service not installed'
	String get serviceModeNotInstalled => 'Privileged service not installed';

	/// en: 'Privileged service installed'
	String get serviceModeInstalled => 'Privileged service installed';

	/// en: 'Installed, but service is not ready'
	String get serviceModeUnreachable => 'Installed, but service is not ready';

	/// en: 'Service ready · Core running (PID {pid})'
	String serviceModeRunning({required Object pid}) => 'Service ready · Core running (PID ${pid})';

	/// en: 'Service ready · Core stopped'
	String get serviceModeIdle => 'Service ready · Core stopped';

	/// en: 'Version mismatch ({version}) — please reinstall'
	String serviceModeNeedsUpdate({required Object version}) => 'Version mismatch (${version}) — please reinstall';

	/// en: 'Update'
	String get serviceModeUpdate => 'Update';

	/// en: 'Service updated successfully'
	String get serviceModeUpdateOk => 'Service updated successfully';

	/// en: 'Service update failed: {error}'
	String serviceModeUpdateFailed({required Object error}) => 'Service update failed: ${error}';

	/// en: 'Desktop service installed'
	String get serviceModeInstallOk => 'Desktop service installed';

	/// en: 'Install service failed: {error}'
	String serviceModeInstallFailed({required Object error}) => 'Install service failed: ${error}';

	/// en: 'Desktop service removed'
	String get serviceModeUninstallOk => 'Desktop service removed';

	/// en: 'Uninstall service failed: {error}'
	String serviceModeUninstallFailed({required Object error}) => 'Uninstall service failed: ${error}';

	/// en: 'Switched to TUN mode'
	String get msgSwitchedToTun => 'Switched to TUN mode';

	/// en: 'Switched to system proxy'
	String get msgSwitchedToSystemProxy => 'Switched to system proxy';

	/// en: 'Failed to switch mode'
	String get errTunSwitchFailed => 'Failed to switch mode';

	/// en: 'TUN Bypass'
	String get tunBypassLabel => 'TUN Bypass';

	/// en: 'Exclude addresses or processes from TUN'
	String get tunBypassSub => 'Exclude addresses or processes from TUN';

	/// en: 'Bypass addresses (one per line, CIDR)'
	String get tunBypassAddrHint => 'Bypass addresses (one per line, CIDR)';

	/// en: 'Bypass processes (one per line)'
	String get tunBypassProcHint => 'Bypass processes (one per line)';

	/// en: 'TUN bypass settings saved'
	String get tunBypassSaved => 'TUN bypass settings saved';

	/// en: 'TUN Stack'
	String get tunStackLabel => 'TUN Stack';

	/// en: 'Mixed'
	String get tunStackMixed => 'Mixed';

	/// en: 'System'
	String get tunStackSystem => 'System';

	/// en: 'gVisor'
	String get tunStackGvisor => 'gVisor';

	/// en: 'Set system proxy on connect'
	String get setSystemProxyOnConnect => 'Set system proxy on connect';

	/// en: 'Auto-configure HTTP/SOCKS system proxy'
	String get setSystemProxyOnConnectSub => 'Auto-configure HTTP/SOCKS system proxy';

	/// en: 'Auto connect on startup'
	String get autoConnect => 'Auto connect on startup';

	/// en: 'Launch at startup'
	String get launchAtStartupLabel => 'Launch at startup';

	/// en: 'Auto start YueLink at login'
	String get launchAtStartupSub => 'Auto start YueLink at login';

	/// en: 'Log Level'
	String get logLevelSetting => 'Log Level';

	/// en: 'Config Overwrite'
	String get configOverwrite => 'Config Overwrite';

	/// en: 'Add custom rules on top of subscription config'
	String get configOverwriteSub => 'Add custom rules on top of subscription config';

	/// en: 'Update all subscriptions now'
	String get updateAllNow => 'Update all subscriptions now';

	/// en: 'Theme'
	String get themeLabel => 'Theme';

	/// en: 'System'
	String get themeSystem => 'System';

	/// en: 'Light'
	String get themeLight => 'Light';

	/// en: 'Dark'
	String get themeDark => 'Dark';

	/// en: 'Follow system'
	String get languageAuto => 'Follow system';

	/// en: '中文'
	String get languageChinese => '中文';

	/// en: 'English'
	String get languageEnglish => 'English';

	/// en: 'Core Status'
	String get coreStatus => 'Core Status';

	/// en: 'Running'
	String get coreRunning => 'Running';

	/// en: 'Stopped'
	String get coreStopped => 'Stopped';

	/// en: 'Run Mode'
	String get runMode => 'Run Mode';

	/// en: 'Mixed Port'
	String get mixedPort => 'Mixed Port';

	/// en: 'API Port'
	String get apiPort => 'API Port';

	/// en: 'DNS Query'
	String get dnsQuery => 'DNS Query';

	/// en: 'Running Config'
	String get runningConfig => 'Running Config';

	/// en: 'Version'
	String get versionLabel => 'Version';

	/// en: 'Core'
	String get coreLabel => 'Core';

	/// en: 'Project Home'
	String get projectHome => 'Project Home';

	/// en: 'Open Source License'
	String get openSourceLicense => 'Open Source License';

	/// en: 'Updating subscriptions...'
	String get updatingAll => 'Updating subscriptions...';

	/// en: 'Update done: {updated} succeeded, {failed} failed'
	String updateAllResult({required Object updated, required Object failed}) => 'Update done: ${updated} succeeded, ${failed} failed';

	/// en: 'DNS cache cleared'
	String get dnsCacheCleared => 'DNS cache cleared';

	/// en: 'Fake-IP cache cleared'
	String get fakeIpCacheCleared => 'Fake-IP cache cleared';

	/// en: 'Request timed out, check your network'
	String get errorTimeout => 'Request timed out, check your network';

	/// en: 'Network error, check your connection'
	String get errorNetwork => 'Network error, check your connection';

	/// en: 'Port must be between 1 and 65535'
	String get overwritePortInvalid => 'Port must be between 1 and 65535';

	/// en: 'All'
	String get proxyTypeAll => 'All';

	/// en: 'Sub-Store Conversion'
	String get sectionSubStore => 'Sub-Store Conversion';

	/// en: 'Sub-Store Server URL'
	String get subStoreUrlLabel => 'Sub-Store Server URL';

	/// en: 'http://127.0.0.1:25500'
	String get subStoreUrlHint => 'http://127.0.0.1:25500';

	/// en: 'Convert V2Ray/SS links to Clash format automatically'
	String get subStoreUrlSub => 'Convert V2Ray/SS links to Clash format automatically';

	/// en: 'Sub-Store URL saved'
	String get subStoreUrlSaved => 'Sub-Store URL saved';

	/// en: 'Basic'
	String get overwriteTabBasic => 'Basic';

	/// en: 'Rules'
	String get overwriteTabRules => 'Rules';

	/// en: 'Advanced'
	String get overwriteTabAdvanced => 'Advanced';

	/// en: 'Override Mode'
	String get overwriteModeLabel => 'Override Mode';

	/// en: 'No override'
	String get overwriteModeNone => 'No override';

	/// en: 'Mixed Port'
	String get overwritePortLabel => 'Mixed Port';

	/// en: 'e.g. 7890 (leave blank to skip)'
	String get overwritePortHint => 'e.g. 7890 (leave blank to skip)';

	/// en: 'Custom Rules (prepended)'
	String get overwriteCustomRulesLabel => 'Custom Rules (prepended)';

	/// en: 'Add Rule'
	String get overwriteAddRule => 'Add Rule';

	/// en: 'e.g. DOMAIN-SUFFIX,example.com,DIRECT'
	String get overwriteRuleHint => 'e.g. DOMAIN-SUFFIX,example.com,DIRECT';

	/// en: 'Extra YAML (appended)'
	String get overwriteExtraYamlLabel => 'Extra YAML (appended)';

	/// en: 'Mock'
	String get modeMock => 'Mock';

	/// en: 'Subprocess'
	String get modeSubprocess => 'Subprocess';

	/// en: 'Enter domain, e.g. google.com'
	String get domainHint => 'Enter domain, e.g. google.com';

	/// en: 'Query'
	String get query => 'Query';

	/// en: 'No records'
	String get noRecords => 'No records';

	/// en: 'v{v} available'
	String updateAvailableV({required Object v}) => 'v${v} available';

	/// en: 'Proxy Providers'
	String get proxyProviderTitle => 'Proxy Providers';

	/// en: 'No proxy providers'
	String get proxyProviderEmpty => 'No proxy providers';

	/// en: '{count} nodes'
	String providerNodeCount({required Object count}) => '${count} nodes';

	/// en: 'Update'
	String get providerUpdate => 'Update';

	/// en: 'Health Check'
	String get providerHealthCheck => 'Health Check';

	/// en: 'Provider updated'
	String get providerUpdateSuccess => 'Provider updated';

	/// en: 'Provider update failed'
	String get providerUpdateFailed => 'Provider update failed';

	/// en: 'Health check complete'
	String get providerHealthCheckDone => 'Health check complete';

	/// en: 'Mode'
	String get connectionModeLabel => 'Mode';

	/// en: 'Network permission denied, cannot enable TUN mode'
	String get errVpnPermission => 'Network permission denied, cannot enable TUN mode';

	/// en: 'Core failed to start, check config or port conflicts'
	String get errCoreStartFailed => 'Core failed to start, check config or port conflicts';

	/// en: 'Tunnel setup failed'
	String get errVpnTunnelFailed => 'Tunnel setup failed';

	/// en: 'Connected'
	String get msgConnected => 'Connected';

	/// en: 'API error: {code} - {body}'
	String errApiError({required Object code, required Object body}) => 'API error: ${code} - ${body}';

	/// en: 'Start failed: {msg}'
	String errStartFailed({required Object msg}) => 'Start failed: ${msg}';

	/// en: 'Disconnected'
	String get msgDisconnected => 'Disconnected';

	/// en: 'Error while disconnecting'
	String get errStopFailed => 'Error while disconnecting';

	/// en: 'System proxy setup failed. Configure proxy manually at 127.0.0.1'
	String get errSystemProxyFailed => 'System proxy setup failed. Configure proxy manually at 127.0.0.1';

	/// en: 'Download timed out, check your network'
	String get errDownloadTimeout => 'Download timed out, check your network';

	/// en: 'Network error: {detail}'
	String errNetworkError({required Object detail}) => 'Network error: ${detail}';

	/// en: 'Download failed: HTTP {code}'
	String errDownloadHttpFailed({required Object code}) => 'Download failed: HTTP ${code}';

	/// en: 'Lock chart'
	String get chartLock => 'Lock chart';

	/// en: 'Unlock chart'
	String get chartUnlock => 'Unlock chart';

	/// en: 'Mode switch failed'
	String get switchModeFailed => 'Mode switch failed';

	/// en: 'Offline preview — connect to switch nodes'
	String get offlinePreview => 'Offline preview — connect to switch nodes';

	/// en: 'Default'
	String get sortDefault => 'Default';

	/// en: 'Latency ↑'
	String get sortLatencyAsc => 'Latency ↑';

	/// en: 'Latency ↓'
	String get sortLatencyDesc => 'Latency ↓';

	/// en: 'Name A-Z'
	String get sortNameAsc => 'Name A-Z';

	/// en: 'Card view'
	String get nodeViewCard => 'Card view';

	/// en: 'List view'
	String get nodeViewList => 'List view';

	/// en: 'Sign In'
	String get authLogin => 'Sign In';

	/// en: 'Sign Out'
	String get authLogout => 'Sign Out';

	/// en: 'Email'
	String get authEmail => 'Email';

	/// en: 'Password'
	String get authPassword => 'Password';

	/// en: 'your@email.com'
	String get authEmailHint => 'your@email.com';

	/// en: 'Enter password'
	String get authPasswordHint => 'Enter password';

	/// en: 'Sign in to your Yue.to account'
	String get authLoginSubtitle => 'Sign in to your Yue.to account';

	/// en: 'Signing in...'
	String get authLoggingIn => 'Signing in...';

	/// en: 'Login failed'
	String get authLoginFailed => 'Login failed';

	/// en: 'Sign out and clear local data?'
	String get authLogoutConfirm => 'Sign out and clear local data?';

	/// en: 'Syncing subscription...'
	String get authSyncingSubscription => 'Syncing subscription...';

	/// en: 'Subscription synced'
	String get authSyncSuccess => 'Subscription synced';

	/// en: 'Subscription sync failed'
	String get authSyncFailed => 'Subscription sync failed';

	/// en: 'Account'
	String get authAccountInfo => 'Account';

	/// en: 'Plan'
	String get authPlan => 'Plan';

	/// en: 'My Plan'
	String get dashMyPlan => 'My Plan';

	/// en: 'Traffic'
	String get authTraffic => 'Traffic';

	/// en: 'Expiry'
	String get authExpiry => 'Expiry';

	/// en: '{days} days remaining'
	String authDaysRemaining({required Object days}) => '${days} days remaining';

	/// en: 'Expired'
	String get authExpired => 'Expired';

	/// en: 'Expires today'
	String get authExpiryToday => 'Expires today';

	/// en: 'Refresh'
	String get authRefreshInfo => 'Refresh';

	/// en: 'Session expired, please sign in again'
	String get authSessionExpired => 'Session expired, please sign in again';

	/// en: 'Incorrect email or password'
	String get authErrorBadCredentials => 'Incorrect email or password';

	/// en: 'Network error, please check your connection'
	String get authErrorNetwork => 'Network error, please check your connection';

	/// en: 'Service temporarily unavailable, please try again later'
	String get authErrorServer => 'Service temporarily unavailable, please try again later';

	/// en: 'Traffic Usage'
	String get mineTrafficTitle => 'Traffic Usage';

	/// en: 'Upload'
	String get mineSpeedUp => 'Upload';

	/// en: 'Download'
	String get mineSpeedDown => 'Download';

	/// en: 'Remaining'
	String get mineRemaining => 'Remaining';

	/// en: 'Devices'
	String get mineDevices => 'Devices';

	/// en: 'Quick Actions'
	String get mineActions => 'Quick Actions';

	/// en: 'Change Password'
	String get mineChangePassword => 'Change Password';

	/// en: 'Join Telegram Group'
	String get mineTelegramGroup => 'Join Telegram Group';

	/// en: 'Plans'
	String get mineRenew => 'Plans';

	/// en: 'Plan expiring soon — renew now'
	String get mineExpiryWarning => 'Plan expiring soon — renew now';

	/// en: 'Plan has expired — renew now'
	String get mineExpiredWarning => 'Plan has expired — renew now';

	/// en: 'Syncing…'
	String get mineSyncing => 'Syncing…';

	/// en: 'Synced'
	String get mineSyncDone => 'Synced';

	/// en: 'Sync failed'
	String get mineSyncFailed => 'Sync failed';

	/// en: 'Not connected'
	String get mineNotConnected => 'Not connected';

	/// en: '悦视频'
	String get mineEmby => '悦视频';

	/// en: 'No 悦视频 access for this account'
	String get mineEmbyNoAccess => 'No 悦视频 access for this account';

	/// en: 'Opening 悦视频…'
	String get mineEmbyOpening => 'Opening 悦视频…';

	/// en: 'Unable to open 悦视频'
	String get mineEmbyOpenFailed => 'Unable to open 悦视频';

	/// en: 'Please connect first to access Media'
	String get mineEmbyNeedsVpn => 'Please connect first to access Media';

	/// en: 'Terms of Service'
	String get minePrivacyPolicy => 'Terms of Service';

	/// en: 'Go to Dashboard'
	String get goToHomeToProtect => 'Go to Dashboard';

	/// en: 'Subscription synced — you're ready to connect'
	String get syncFirstSuccess => 'Subscription synced — you\'re ready to connect';

	/// en: 'Current Plan'
	String get storeCurrentPlan => 'Current Plan';

	/// en: 'Available Plans'
	String get storeAvailablePlans => 'Available Plans';

	/// en: 'Buy Now'
	String get storeBuyNow => 'Buy Now';

	/// en: 'Renew'
	String get storeRenew => 'Renew';

	/// en: 'Upgrade'
	String get storeUpgrade => 'Upgrade';

	/// en: 'No plans available'
	String get storeNoPlans => 'No plans available';

	/// en: 'Unlimited'
	String get storeUnlimited => 'Unlimited';

	/// en: 'Billing Period'
	String get storeSelectPeriod => 'Billing Period';

	/// en: 'Confirm Order'
	String get storeConfirmPurchase => 'Confirm Order';

	/// en: 'Pay Now'
	String get storePayNow => 'Pay Now';

	/// en: 'Creating order...'
	String get storeOrderCreating => 'Creating order...';

	/// en: 'Payment Successful'
	String get storeOrderSuccess => 'Payment Successful';

	/// en: 'Awaiting Payment'
	String get storeOrderPending => 'Awaiting Payment';

	/// en: 'Order Failed'
	String get storeOrderFailed => 'Order Failed';

	/// en: 'Order Cancelled'
	String get storeOrderCancelled => 'Order Cancelled';

	/// en: 'Back to Store'
	String get storeReturnToStore => 'Back to Store';

	/// en: 'Plan expiring soon — renew now'
	String get storeRenewalReminder => 'Plan expiring soon — renew now';

	/// en: 'Plan expired — buy now'
	String get storeExpiredReminder => 'Plan expired — buy now';

	/// en: 'Plan Details'
	String get storePlanDetail => 'Plan Details';

	/// en: 'Check Result'
	String get storeCheckResult => 'Check Result';

	/// en: 'Cancel Order'
	String get storeCancelOrder => 'Cancel Order';

	/// en: 'Open Payment Page'
	String get storeOpenPaymentPage => 'Open Payment Page';

	/// en: 'Have a coupon?'
	String get storeCouponExpand => 'Have a coupon?';

	/// en: 'Coupon Code'
	String get storeCouponCode => 'Coupon Code';

	/// en: 'Apply'
	String get storeCouponValidate => 'Apply';

	/// en: 'Validating...'
	String get storeCouponValidating => 'Validating...';

	/// en: 'Coupon applied'
	String get storeCouponValid => 'Coupon applied';

	/// en: 'Invalid coupon'
	String get storeCouponInvalid => 'Invalid coupon';

	/// en: 'Discount'
	String get storeDiscount => 'Discount';

	/// en: 'You Pay'
	String get storeActualAmount => 'You Pay';

	/// en: 'Remove'
	String get storeCouponRemove => 'Remove';

	/// en: 'Payment Method'
	String get storePaymentMethod => 'Payment Method';

	/// en: 'Handling fee'
	String get storeHandlingFee => 'Handling fee';

	/// en: 'Order History'
	String get storeOrderHistory => 'Order History';

	/// en: 'Order No.'
	String get storeOrderNo => 'Order No.';

	/// en: 'Date'
	String get storeOrderDate => 'Date';

	/// en: 'No orders yet'
	String get storeNoOrders => 'No orders yet';

	/// en: 'Order Detail'
	String get storeOrderDetail => 'Order Detail';

	/// en: 'Pending'
	String get storeOrderStatusPending => 'Pending';

	/// en: 'Processing'
	String get storeOrderStatusProcessing => 'Processing';

	/// en: 'Cancelled'
	String get storeOrderStatusCancelled => 'Cancelled';

	/// en: 'Completed'
	String get storeOrderStatusCompleted => 'Completed';

	/// en: 'Update Lines'
	String get dashSyncLabel => 'Update Lines';

	/// en: 'Announcements'
	String get dashAnnouncementsLabel => 'Announcements';

	/// en: 'Sync Lines'
	String get mineSyncLine => 'Sync Lines';

	/// en: 'Subscription Management'
	String get mineSubscriptionManage => 'Subscription Management';

	/// en: 'Account'
	String get dashAccountLabel => 'Account';

	/// en: 'Latest Announcements'
	String get dashLatestAnnouncement => 'Latest Announcements';

	/// en: 'No network connection'
	String get noNetworkConnection => 'No network connection';

	/// en: 'Hello'
	String get dashGreeting => 'Hello';

	/// en: 'Welcome back'
	String get dashGreetingReturning => 'Welcome back';

	/// en: 'No announcements'
	String get dashNoAnnouncements => 'No announcements';

	/// en: 'View all'
	String get dashViewAll => 'View all';

	/// en: 'No plan info'
	String get dashNoPlan => 'No plan info';

	/// en: 'Old Password'
	String get oldPassword => 'Old Password';

	/// en: 'New Password'
	String get newPassword => 'New Password';

	/// en: 'Password changed successfully'
	String get passwordChangedSuccess => 'Password changed successfully';

	/// en: 'Password change failed'
	String get passwordChangeFailed => 'Password change failed';

	/// en: 'Syncing...'
	String get syncing => 'Syncing...';

	/// en: 'Sync complete'
	String get syncComplete => 'Sync complete';

	/// en: 'Sync failed'
	String get syncFailed => 'Sync failed';

	/// en: 'Not connected'
	String get notConnected => 'Not connected';

	/// en: 'Switch Subscription'
	String get switchProfileTitle => 'Switch Subscription';

	/// en: 'Switch to "{name}"? This will use its nodes and rules.'
	String switchProfileMessage({required Object name}) => 'Switch to "${name}"? This will use its nodes and rules.';

	/// en: 'Connection is active. You need to reconnect after switching.'
	String get switchProfileReconnectHint => 'Connection is active. You need to reconnect after switching.';

	/// en: 'Switch'
	String get switchProfileConfirm => 'Switch';

	/// en: 'Welcome to YueLink'
	String get onboardingWelcome => 'Welcome to YueLink';

	/// en: 'Global network · Fast, secure, reliable · Sync across devices'
	String get onboardingWelcomeDesc => 'Global network · Fast, secure, reliable · Sync across devices';

	/// en: 'One-Tap Connect'
	String get onboardingConnect => 'One-Tap Connect';

	/// en: 'Smart node selection · No config needed · Ready out of the box'
	String get onboardingConnectDesc => 'Smart node selection · No config needed · Ready out of the box';

	/// en: 'Emby Streaming Included'
	String get onboardingNodes => 'Emby Streaming Included';

	/// en: 'Licensed movies & TV shows · Watch as soon as you're connected'
	String get onboardingNodesDesc => 'Licensed movies & TV shows · Watch as soon as you\'re connected';

	/// en: 'Daily Check-in for Traffic'
	String get onboardingStore => 'Daily Check-in for Traffic';

	/// en: 'Earn free traffic every day · One account syncs all platforms'
	String get onboardingStoreDesc => 'Earn free traffic every day · One account syncs all platforms';

	/// en: 'Skip'
	String get onboardingSkip => 'Skip';

	/// en: 'Next'
	String get onboardingNext => 'Next';

	/// en: 'Get Started'
	String get onboardingDone => 'Get Started';

	/// en: 'Proxy Chain'
	String get chainProxy => 'Proxy Chain';

	/// en: 'Entry'
	String get chainEntry => 'Entry';

	/// en: 'Exit'
	String get chainExit => 'Exit';

	/// en: 'Connect Chain'
	String get chainConnect => 'Connect Chain';

	/// en: 'Disconnect'
	String get chainDisconnect => 'Disconnect';

	/// en: 'Proxy chain connected'
	String get chainConnected => 'Proxy chain connected';

	/// en: 'Proxy chain disconnected'
	String get chainDisconnected => 'Proxy chain disconnected';

	/// en: 'Chain connect failed'
	String get chainConnectFailed => 'Chain connect failed';

	/// en: 'Connect first'
	String get chainNeedConnect => 'Connect first';

	/// en: 'No proxy group available'
	String get chainNoGroup => 'No proxy group available';

	/// en: 'Need 2+ nodes'
	String get chainNeedTwoNodes => 'Need 2+ nodes';

	/// en: 'Node already in chain'
	String get chainNodeDuplicate => 'Node already in chain';

	/// en: 'Clear'
	String get chainClear => 'Clear';

	/// en: 'No nodes in chain'
	String get chainEmptyHint => 'No nodes in chain';

	/// en: 'Long-press any node or group on the Lines page to add it'
	String get chainEmptyDesc => 'Long-press any node or group on the Lines page to add it';

	/// en: 'Added to proxy chain'
	String get chainAddHint => 'Added to proxy chain';

	/// en: 'Add to Chain'
	String get chainPickerTitle => 'Add to Chain';

	/// en: 'Search nodes / groups...'
	String get chainPickerSearch => 'Search nodes / groups...';

	/// en: 'Proxy Groups'
	String get chainSectionGroups => 'Proxy Groups';

	/// en: 'Nodes'
	String get chainSectionNodes => 'Nodes';

	/// en: 'Another proxy client took over — stopping YueLink proxy'
	String get msgSystemProxyConflict => 'Another proxy client took over — stopping YueLink proxy';

	/// en: 'Daily Check-in'
	String get checkinTitle => 'Daily Check-in';

	/// en: 'Check in to get traffic or balance rewards'
	String get checkinDesc => 'Check in to get traffic or balance rewards';

	/// en: 'Check in'
	String get checkinAction => 'Check in';

	/// en: 'Checked in'
	String get checkinDone => 'Checked in';

	/// en: 'Already checked in today'
	String get checkinAlready => 'Already checked in today';

	/// en: 'Checked in on another device'
	String get checkinOtherDevice => 'Checked in on another device';

	/// en: 'Please login first'
	String get checkinNeedLogin => 'Please login first';

	/// en: 'Check-in failed'
	String get checkinFailed => 'Check-in failed';

	/// en: 'Reward'
	String get checkinReward => 'Reward';

	/// en: 'Got {amount} traffic!'
	String checkinTrafficReward({required Object amount}) => 'Got ${amount} traffic!';

	/// en: 'Got ¥{amount} balance!'
	String checkinBalanceReward({required Object amount}) => 'Got ¥${amount} balance!';

	/// en: 'Smart Select'
	String get qaSmartSelect => 'Smart Select';

	/// en: 'Scene Mode'
	String get qaSceneMode => 'Scene Mode';

	/// en: 'Speed Test'
	String get qaSpeedTest => 'Speed Test';

	/// en: 'Expiry'
	String get statusExpiry => 'Expiry';

	/// en: 'Traffic'
	String get statusTraffic => 'Traffic';

	/// en: 'Health'
	String get statusHealth => 'Health';

	/// en: 'Expired'
	String get statusExpired => 'Expired';

	/// en: 'Unlimited'
	String get statusUnlimited => 'Unlimited';

	/// en: 'Exhausted'
	String get statusExhausted => 'Exhausted';

	/// en: 'Good'
	String get gradeExcellent => 'Good';

	/// en: 'Fair'
	String get gradeFair => 'Fair';

	/// en: 'Poor'
	String get gradePoor => 'Poor';

	/// en: 'N/A'
	String get gradeUnknown => 'N/A';

	/// en: 'Offline'
	String get gradeOffline => 'Offline';

	/// en: 'Enter'
	String get embyEnter => 'Enter';

	/// en: 'Subscribe to YueVideo to watch movies, TV shows and anime'
	String get embyNoAccessHint => 'Subscribe to YueVideo to watch movies, TV shows and anime';

	/// en: 'Tap to enter YueVideo'
	String get embyWebHint => 'Tap to enter YueVideo';

	/// en: 'No content'
	String get embyNoContent => 'No content';

	/// en: 'No library'
	String get embyNoLibrary => 'No library';

	/// en: 'Load failed'
	String get embyLoadFailed => 'Load failed';

	/// en: 'Tap to retry'
	String get embyTapRetry => 'Tap to retry';

	/// en: 'Failed to load libraries'
	String get embyGetFailed => 'Failed to load libraries';

	/// en: 'Native library load failed'
	String get errNativeLib => 'Native library load failed';

	/// en: 'Package may be corrupted, please reinstall'
	String get errNativeLibHint => 'Package may be corrupted, please reinstall';

	/// en: 'Core init failed'
	String get errCoreInit => 'Core init failed';

	/// en: 'Try restarting or clearing local cache'
	String get errCoreInitHint => 'Try restarting or clearing local cache';

	/// en: 'Network permission denied'
	String get errVpnDenied => 'Network permission denied';

	/// en: 'Authorize in system settings'
	String get errVpnDeniedHint => 'Authorize in system settings';

	/// en: 'Tunnel creation failed'
	String get errTunnel => 'Tunnel creation failed';

	/// en: 'Try rebuilding network config'
	String get errTunnelHint => 'Try rebuilding network config';

	/// en: 'Config parse failed'
	String get errConfig => 'Config parse failed';

	/// en: 'Try re-syncing subscription'
	String get errConfigHint => 'Try re-syncing subscription';

	/// en: 'Core start failed'
	String get errCoreStart => 'Core start failed';

	/// en: 'Check diagnostics report'
	String get errCoreStartHint => 'Check diagnostics report';

	/// en: 'API timeout, core may have crashed'
	String get errApiTimeout => 'API timeout, core may have crashed';

	/// en: 'Check diagnostics for details'
	String get errApiTimeoutHint => 'Check diagnostics for details';

	/// en: 'Core crashed after start'
	String get errCoreCrash => 'Core crashed after start';

	/// en: 'Check Go Core log in diagnostics'
	String get errCoreCrashHint => 'Check Go Core log in diagnostics';

	/// en: 'Geo data file error'
	String get errGeo => 'Geo data file error';

	/// en: 'Try clearing local cache'
	String get errGeoHint => 'Try clearing local cache';

	/// en: 'Connection failed'
	String get errGeneric => 'Connection failed';

	/// en: 'Go to repair page for details'
	String get errGenericHint => 'Go to repair page for details';

	/// en: 'Go to Repair'
	String get goRepair => 'Go to Repair';

	/// en: 'Copy Report'
	String get copyReport => 'Copy Report';

	/// en: 'Startup report copied'
	String get reportCopied => 'Startup report copied';

	/// en: 'Go Core log (last {count} lines):'
	String goCoreLogs({required Object count}) => 'Go Core log (last ${count} lines):';

	/// en: 'Recently Used'
	String get recentlyUsed => 'Recently Used';

	/// en: 'Repair Tools'
	String get repairTools => 'Repair Tools';

	/// en: 'Rebuild Network Config'
	String get repairRebuildVpn => 'Rebuild Network Config';

	/// en: 'Remove old tunnel, re-create on next connect'
	String get repairRebuildVpnHint => 'Remove old tunnel, re-create on next connect';

	/// en: 'Clear Tunnel Config'
	String get repairClearTunnel => 'Clear Tunnel Config';

	/// en: 'Delete App Group config and GEO data'
	String get repairClearTunnelHint => 'Delete App Group config and GEO data';

	/// en: 'Re-sync Subscription'
	String get repairResync => 'Re-sync Subscription';

	/// en: 'Re-fetch subscription config from server'
	String get repairResyncHint => 'Re-fetch subscription config from server';

	/// en: 'Clear Local Cache'
	String get repairClearCache => 'Clear Local Cache';

	/// en: 'Delete local config files, logs, startup report'
	String get repairClearCacheHint => 'Delete local config files, logs, startup report';

	/// en: 'Restart Core'
	String get repairRestartCore => 'Restart Core';

	/// en: 'Rebuild core state without touching the subscription — use when latency tests all time out'
	String get repairRestartCoreHint => 'Rebuild core state without touching the subscription — use when latency tests all time out';

	/// en: 'One-Click Repair All'
	String get repairOneClick => 'One-Click Repair All';

	/// en: 'Repairing...'
	String get repairRunning => 'Repairing...';

	/// en: 'Please login first'
	String get repairNeedLogin => 'Please login first';

	/// en: 'Data Monitor'
	String get dataMonitor => 'Data Monitor';

	/// en: 'Not connected'
	String get vpnNotRunning => 'Not connected';

	/// en: 'Modules'
	String get sectionModules => 'Modules';

	/// en: 'Rule Modules'
	String get modulesLabel => 'Rule Modules';

	/// en: 'No modules installed'
	String get modulesEmpty => 'No modules installed';

	/// en: 'Module URL'
	String get moduleAddUrl => 'Module URL';

	/// en: 'Adding module…'
	String get moduleAdding => 'Adding module…';

	/// en: 'Module added'
	String get moduleAddSuccess => 'Module added';

	/// en: 'Refresh'
	String get moduleRefresh => 'Refresh';

	/// en: 'Delete module'
	String get moduleDelete => 'Delete module';

	/// en: 'Delete this module?'
	String get moduleDeleteConfirm => 'Delete this module?';

	/// en: 'Rules'
	String get moduleRuleCount => 'Rules';

	/// en: 'Not active in current version'
	String get moduleNotActive => 'Not active in current version';

	/// en: 'MITM hostnames detected'
	String get moduleMitmDetected => 'MITM hostnames detected';

	/// en: 'Scripts detected'
	String get moduleScriptDetected => 'Scripts detected';

	/// en: 'URL Rewrites detected'
	String get moduleRewriteDetected => 'URL Rewrites detected';

	/// en: '— will be enabled in a future version'
	String get moduleFutureVersion => '— will be enabled in a future version';

	/// en: 'MITM Engine'
	String get mitmEngine => 'MITM Engine';

	/// en: 'Running'
	String get mitmEngineRunning => 'Running';

	/// en: 'Stopped'
	String get mitmEngineStopped => 'Stopped';

	/// en: 'Start'
	String get mitmEngineStart => 'Start';

	/// en: 'Stop'
	String get mitmEngineStop => 'Stop';

	/// en: 'Port'
	String get mitmEnginePort => 'Port';

	/// en: 'Root CA Certificate'
	String get mitmCertTitle => 'Root CA Certificate';

	/// en: 'Install Certificate'
	String get mitmCertInstall => 'Install Certificate';

	/// en: 'Generate'
	String get mitmCertGenerate => 'Generate';

	/// en: 'Export PEM'
	String get mitmCertExport => 'Export PEM';

	/// en: 'SHA-256 Fingerprint'
	String get mitmCertFingerprint => 'SHA-256 Fingerprint';

	/// en: 'Expires'
	String get mitmCertExpiry => 'Expires';

	/// en: 'No certificate yet'
	String get mitmCertNotFound => 'No certificate yet';

	/// en: 'Certificate Installation'
	String get mitmCertGuideTitle => 'Certificate Installation';

	/// en: 'MITM Hostnames'
	String get mitmHostnameCount => 'MITM Hostnames';

	/// en: 'Imported {ok} subscriptions'
	String importAllResultAllOk({required Object ok}) => 'Imported ${ok} subscriptions';

	/// en: 'Imported {ok}, failed {failed}'
	String importAllResultPartial({required Object ok, required Object failed}) => 'Imported ${ok}, failed ${failed}';

	/// en: 'Scan QR'
	String get scanQrImport => 'Scan QR';

	/// en: 'Scan QR Code'
	String get scanQrTitle => 'Scan QR Code';

	/// en: 'Scanned content is not a valid URL'
	String get scanQrInvalidUrl => 'Scanned content is not a valid URL';

	/// en: 'Camera permission denied'
	String get scanQrPermissionDenied => 'Camera permission denied';

	/// en: 'Load failed'
	String get webLoadFailed => 'Load failed';

	/// en: 'Press shortcut keys...'
	String get hotkeyPrompt => 'Press shortcut keys...';

	/// en: 'Failed to load app list'
	String get loadAppListFailed => 'Failed to load app list';

	/// en: 'Done'
	String get repairActionDone => 'Done';

	/// en: 'Failed'
	String get repairActionFailed => 'Failed';

	/// en: 'Download the IPA from the opened page and install via TrollStore'
	String get installIpaHint => 'Download the IPA from the opened page and install via TrollStore';

	/// en: 'Auto-install not supported on iOS. Download from GitHub Releases'
	String get installIosManual => 'Auto-install not supported on iOS. Download from GitHub Releases';

	/// en: 'Auto-install not supported on this platform'
	String get installUnsupported => 'Auto-install not supported on this platform';

	/// en: 'Loading...'
	String get loading => 'Loading...';

	/// en: 'Announcements'
	String get latestAnnouncements => 'Announcements';

	/// en: 'View all'
	String get viewAll => 'View all';

	/// en: 'Smart Select'
	String get smartSelect => 'Smart Select';

	/// en: 'Search all libraries...'
	String get embySearchHint => 'Search all libraries...';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Other Subscriptions'
	String get otherSubscriptions => 'Other Subscriptions';

	/// en: '4K movies · J-Drama · Anime, watch anywhere anytime'
	String get heroBannerEmby => '4K movies · J-Drama · Anime, watch anywhere anytime';

	/// en: 'Dedicated line to ChatGPT / Gemini, low-latency stable access'
	String get heroBannerAi => 'Dedicated line to ChatGPT / Gemini, low-latency stable access';

	/// en: 'Upgrade your plan for more nodes · more traffic · faster speed'
	String get heroBannerUpgrade => 'Upgrade your plan for more nodes · more traffic · faster speed';

	/// en: 'Play'
	String get embyPlay => 'Play';

	/// en: 'Director'
	String get embyDirector => 'Director';

	/// en: 'Cast'
	String get embyCast => 'Cast';

	/// en: 'Similar'
	String get embySimilar => 'Similar';

	/// en: 'No results'
	String get embyNoResults => 'No results';

	/// en: 'Resume Playback'
	String get embyResumeTitle => 'Resume Playback';

	/// en: 'Restart'
	String get embyRestartBtn => 'Restart';

	/// en: 'Continue'
	String get embyContinueBtn => 'Continue';

	/// en: '▶▶ 2x Speed'
	String get embySpeedUp => '▶▶ 2x Speed';

	/// en: 'Playback failed'
	String get embyPlayFailed => 'Playback failed';

	/// en: 'No audio tracks'
	String get embyNoAudioTrack => 'No audio tracks';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Subtitle size'
	String get embySubtitleSize => 'Subtitle size';

	/// en: 'Please enter feedback content'
	String get feedbackEmpty => 'Please enter feedback content';

	/// en: 'Thanks for your feedback, we will handle it shortly'
	String get feedbackSuccess => 'Thanks for your feedback, we will handle it shortly';

	/// en: 'Submit failed, please try again later'
	String get feedbackFailed => 'Submit failed, please try again later';

	/// en: 'Network error, please try again later'
	String get feedbackNetError => 'Network error, please try again later';

	/// en: 'Feedback'
	String get feedbackTitle => 'Feedback';

	/// en: 'Please describe the issue or suggestion in detail…'
	String get feedbackHint => 'Please describe the issue or suggestion in detail…';

	/// en: 'Telegram / Email'
	String get feedbackContactHint => 'Telegram / Email';

	/// en: 'Submit Feedback'
	String get feedbackSubmit => 'Submit Feedback';

	/// en: 'Available'
	String get available => 'Available';

	/// en: 'Apply best: '
	String get applyBestNode => 'Apply best: ';

	/// en: 'Connection Repair'
	String get repairTitle => 'Connection Repair';

	/// en: 'Diagnostics'
	String get diagnosticsLabel => 'Diagnostics';

	/// en: 'View steps and timing of last connection startup'
	String get diagnosticsHint => 'View steps and timing of last connection startup';

	/// en: 'Network Diagnostics'
	String get networkDiagnostics => 'Network Diagnostics';

	/// en: 'Used / Total'
	String get trafficUsedTotal => 'Used / Total';

	/// en: 'Remaining'
	String get trafficRemaining => 'Remaining';

	/// en: 'Privacy'
	String get privacy => 'Privacy';

	/// en: 'Anonymous usage stats'
	String get telemetryTitle => 'Anonymous usage stats';

	/// en: 'Help improve YueLink, no PII'
	String get telemetrySubtitle => 'Help improve YueLink, no PII';

	/// en: 'View sent events'
	String get telemetryViewEvents => 'View sent events';

	/// en: 'Client ID'
	String get telemetryClientId => 'Client ID';

	/// en: 'Session ID'
	String get telemetrySessionId => 'Session ID';

	/// en: 'Last {n} events'
	String telemetryEventCount({required Object n}) => 'Last ${n} events';

	/// en: 'No events recorded'
	String get telemetryEmpty => 'No events recorded';

	/// en: 'Sign-In Calendar'
	String get calendarTitle => 'Sign-In Calendar';

	/// en: '{year}-{month}'
	String calendarMonthLabel({required Object year, required Object month}) => '${year}-${month}';

	/// en: 'Previous month'
	String get calendarPrevMonth => 'Previous month';

	/// en: 'Next month'
	String get calendarNextMonth => 'Next month';

	/// en: 'Load failed — pull to retry'
	String get calendarLoadFailed => 'Load failed — pull to retry';

	/// en: 'No data'
	String get calendarEmpty => 'No data';

	/// en: 'Retry'
	String get calendarRetry => 'Retry';

	/// en: 'Please log in first'
	String get calendarPleaseLogin => 'Please log in first';

	/// en: 'Streak'
	String get calendarStreakLabel => 'Streak';

	/// en: 'Signed this month'
	String get calendarSignedThisMonth => 'Signed this month';

	/// en: 'Bonus'
	String get calendarMultiplier => 'Bonus';

	/// en: 'Resign yesterday · {cost} pts'
	String calendarBtnResignWithCost({required Object cost}) => 'Resign yesterday · ${cost} pts';

	/// en: 'Close'
	String get calendarBtnClose => 'Close';

	/// en: 'Signed'
	String get calendarBtnSignedToday => 'Signed';

	/// en: 'Signed'
	String get calendarLegendSigned => 'Signed';

	/// en: 'Card'
	String get calendarLegendCard => 'Card';

	/// en: 'Missed'
	String get calendarLegendMissed => 'Missed';

	/// en: 'Today (not yet)'
	String get calendarLegendTodayMiss => 'Today (not yet)';

	/// en: 'Future'
	String get calendarLegendFuture => 'Future';

	/// en: 'd'
	String get calendarUnit => 'd';

	/// en: '/{total}'
	String calendarSuffixOf({required Object total}) => '/${total}';

	/// en: 'Sign-In Calendar'
	String get calendarEntryTitle => 'Sign-In Calendar';

	/// en: 'Monthly view · streak rewards · resign with points'
	String get calendarEntrySubtitle => 'Monthly view · streak rewards · resign with points';

	/// en: 'Mon'
	String get weekMon => 'Mon';

	/// en: 'Tue'
	String get weekTue => 'Tue';

	/// en: 'Wed'
	String get weekWed => 'Wed';

	/// en: 'Thu'
	String get weekThu => 'Thu';

	/// en: 'Fri'
	String get weekFri => 'Fri';

	/// en: 'Sat'
	String get weekSat => 'Sat';

	/// en: 'Sun'
	String get weekSun => 'Sun';

	/// en: '{n}-day streak'
	String checkinStreakSuffix({required Object n}) => '${n}-day streak';

	/// en: 'Resign Card'
	String get resignTitle => 'Resign Card';

	/// en: 'Pay {cost} pts to fill yesterday — your streak stays alive.'
	String resignDesc({required Object cost}) => 'Pay ${cost} pts to fill yesterday — your streak stays alive.';

	/// en: 'Current points: '
	String get resignCurrentPoints => 'Current points: ';

	/// en: 'Need: {cost} pts'
	String resignNeedPoints({required Object cost}) => 'Need: ${cost} pts';

	/// en: 'Insufficient points. Earn more via daily check-in or group betting.'
	String get resignInsufficient => 'Insufficient points. Earn more via daily check-in or group betting.';

	/// en: 'Cancel'
	String get resignCancel => 'Cancel';

	/// en: 'Resign'
	String get resignConfirm => 'Resign';

	/// en: 'iOS Install Guide'
	String get iosGuideTitle => 'iOS Install Guide';

	/// en: 'iOS Install Methods'
	String get iosGuideEntry => 'iOS Install Methods';

	/// en: 'YueLink for iOS is sideloaded. The three options have different VPN-availability trade-offs.'
	String get iosGuideIntro => 'YueLink for iOS is sideloaded. The three options have different VPN-availability trade-offs.';

	/// en: 'VPN dropped within {seconds}s — almost always TrollStore / unsigned IPA. Re-install via AltStore or SideStore to fix.'
	String iosGuideErrorBanner({required Object seconds}) => 'VPN dropped within ${seconds}s — almost always TrollStore / unsigned IPA. Re-install via AltStore or SideStore to fix.';

	/// en: 'AltStore / SideStore'
	String get iosGuideMethodAltstoreTitle => 'AltStore / SideStore';

	/// en: 'Recommended'
	String get iosGuideMethodAltstoreTag => 'Recommended';

	/// en: '✅ Full VPN works (entitlement trusted by system)'
	String get iosGuideMethodAltstoreProVpn => '✅ Full VPN works (entitlement trusted by system)';

	/// en: '✅ Free, signed with your Apple ID'
	String get iosGuideMethodAltstoreProFree => '✅ Free, signed with your Apple ID';

	/// en: '✅ Supports all device generations'
	String get iosGuideMethodAltstoreProDevice => '✅ Supports all device generations';

	/// en: '⚠️ 7-day re-sign required (AltServer / SideServer on desktop)'
	String get iosGuideMethodAltstoreCon7d => '⚠️ 7-day re-sign required (AltServer / SideServer on desktop)';

	/// en: '⚠️ Free Apple ID can hold only 3 apps at once'
	String get iosGuideMethodAltstoreConLimit => '⚠️ Free Apple ID can hold only 3 apps at once';

	/// en: 'Install AltServer / SideServer on desktop → install AltStore / SideStore on iPhone → drop YueLink IPA into the desktop tool or import via AltStore → Settings → General → VPN & Device Management → trust the developer cert'
	String get iosGuideMethodAltstoreHowto => 'Install AltServer / SideServer on desktop → install AltStore / SideStore on iPhone → drop YueLink IPA into the desktop tool or import via AltStore → Settings → General → VPN & Device Management → trust the developer cert';

	/// en: 'TrollStore'
	String get iosGuideMethodTrollTitle => 'TrollStore';

	/// en: 'VPN won't work'
	String get iosGuideMethodTrollTag => 'VPN won\'t work';

	/// en: '✅ Permanent, no re-signing'
	String get iosGuideMethodTrollProForever => '✅ Permanent, no re-signing';

	/// en: '🚫 VPN (NetworkExtension) doesn't work'
	String get iosGuideMethodTrollConVpn => '🚫 VPN (NetworkExtension) doesn\'t work';

	/// en: '🚫 PacketTunnel starts then drops — looks connected but no traffic flows'
	String get iosGuideMethodTrollConFail => '🚫 PacketTunnel starts then drops — looks connected but no traffic flows';

	/// en: '🚫 Only specific older-iOS exploit-eligible devices'
	String get iosGuideMethodTrollConDevice => '🚫 Only specific older-iOS exploit-eligible devices';

	/// en: 'TrollStore bypasses signature checks via a CoreTrust bug, but NetworkExtension still requires an Apple-issued provisioning profile. TrollStore IPAs lack this trust chain — the system starts PacketTunnel but blocks all packets. Fine if you only use YueLink for non-VPN features (e.g. Emby). For proxying, switch to AltStore / SideStore.'
	String get iosGuideMethodTrollHowto => 'TrollStore bypasses signature checks via a CoreTrust bug, but NetworkExtension still requires an Apple-issued provisioning profile. TrollStore IPAs lack this trust chain — the system starts PacketTunnel but blocks all packets.\n\nFine if you only use YueLink for non-VPN features (e.g. Emby). For proxying, switch to AltStore / SideStore.';

	/// en: 'Direct IPA / 3rd-party distribution'
	String get iosGuideMethodIpaTitle => 'Direct IPA / 3rd-party distribution';

	/// en: 'Risky'
	String get iosGuideMethodIpaTag => 'Risky';

	/// en: '✅ Some commercially-signed builds work'
	String get iosGuideMethodIpaProSigned => '✅ Some commercially-signed builds work';

	/// en: '⚠️ Apple may revoke commercial certs anytime, crashing all installs'
	String get iosGuideMethodIpaConRevoke => '⚠️ Apple may revoke commercial certs anytime, crashing all installs';

	/// en: '⚠️ 3rd-party distribution channels can tamper with the binary'
	String get iosGuideMethodIpaConTamper => '⚠️ 3rd-party distribution channels can tamper with the binary';

	/// en: 'Only sign and install IPAs from the official GitHub Releases. Avoid pre-signed installs from unknown sources.'
	String get iosGuideMethodIpaHowto => 'Only sign and install IPAs from the official GitHub Releases. Avoid pre-signed installs from unknown sources.';

	/// en: 'Got it'
	String get iosGuideAck => 'Got it';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'navHome' => 'Home',
			'navProxies' => 'Lines',
			'navProfile' => 'Subscriptions',
			'navMine' => 'Me',
			'navStore' => 'Store',
			'navEmby' => 'Media',
			'navConnections' => 'Connections',
			'navLog' => 'Logs',
			'navSettings' => 'Settings',
			'trayConnect' => 'Connect',
			'trayDisconnect' => 'Disconnect',
			'trayShowWindow' => 'Show Window',
			'trayQuit' => 'Quit',
			'trayProxies' => 'Quick Switch',
			'cancel' => 'Cancel',
			'confirm' => 'OK',
			'save' => 'Save',
			'delete' => 'Delete',
			'edit' => 'Edit',
			'add' => 'Add',
			'retry' => 'Retry',
			'saved' => 'Saved',
			'upload' => 'Upload',
			'download' => 'Download',
			'operationFailed' => 'Operation failed',
			'noData' => 'No data',
			'disconnectedUnexpected' => 'Connection dropped',
			'subExpired' => ({required Object name}) => 'Subscription "${name}" has expired',
			'subExpiringSoon' => ({required Object name, required Object days}) => 'Subscription "${name}" expires in ${days} day(s)',
			'todayUsage' => 'Today',
			'statusConnected' => 'Protected',
			'statusDisconnected' => 'Not Protected',
			'statusConnecting' => 'Connecting...',
			'statusProcessing' => 'Processing...',
			'statusDisconnecting' => 'Disconnecting...',
			'btnConnect' => 'Connect',
			'btnDisconnect' => 'Disconnect',
			'btnConnecting' => 'Connecting',
			'btnDisconnecting' => 'Disconnecting',
			'routeModeRule' => 'Rule',
			'routeModeGlobal' => 'Global',
			'routeModeDirect' => 'Direct',
			'routingModeSetting' => 'Routing Mode',
			'tipTapToSwitchRouting' => 'Tap to switch routing mode',
			'tipTapToSwitchConnection' => 'Tap to switch connection mode',
			'modeSwitched' => 'Mode switched',
			'directModeDesc' => 'All traffic connects directly without proxy',
			'globalModeDesc' => 'All traffic routes through the selected node below',
			'trafficUpload' => 'Upload',
			'trafficDownload' => 'Download',
			'trafficMemory' => 'Memory',
			'activeConns' => 'Connections',
			'mockModeBanner' => 'Dev Mode · Mock Data',
			'mockModeLabel' => 'Mock Mode',
			'mockHint' => 'Click Connect to start mock mode',
			'dashboardLabel' => 'DASHBOARD',
			'dashboardTitle' => 'Calm network control.',
			'switchNode' => 'Switch node',
			'liveConnection' => 'Live connection',
			'dashConnectedDesc' => 'Your traffic is routed through a healthy node with low latency.',
			'dashDisconnectedTitle' => 'Not connected',
			'dashDisconnectedDesc' => 'Click Connect to start routing traffic through a proxy node.',
			'realtimeTraffic' => 'Realtime traffic',
			'nodeLabel' => 'Current Node',
			'exitIpLabel' => 'Outbound IP',
			'routingLabel' => 'Routing Mode',
			'exitIpTapToQuery' => 'Tap to query',
			'exitIpQuerying' => 'Querying...',
			'exitIpFailed' => 'Query failed',
			'systemProxy' => 'System Proxy',
			'systemProxyOn' => 'System proxy enabled',
			'systemProxyOff' => 'System proxy off',
			'trafficActivity' => 'Traffic activity',
			'last60s' => 'Last 60 seconds',
			'dashReadyHint' => 'Ready to connect. Tap the power button to start.',
			'dashNoProfileHint' => 'No profile selected. Add one in Profiles first.',
			'dashAutoConnectOn' => 'Auto-connect: On',
			'dashAutoConnectOff' => 'Auto-connect: Off',
			'noProfileHint' => 'Add a subscription in the Profiles page first',
			'snackNoProfile' => 'No subscription yet — tap Sync to get started',
			'snackConfigMissing' => 'Config missing, please sync your subscription',
			'snackStartFailed' => 'Connection failed, please try again',
			'vpnPermTitle' => 'Network Permission Required',
			'vpnPermBody' => 'YueLink needs to set up a secure tunnel to route your traffic. No personal data is sent to our servers — all processing happens on your device.\n\nTap "Continue" to grant the permission.',
			'vpnPermContinue' => 'Continue',
			'vpnPermIosTitle' => 'Allow VPN Access',
			'vpnPermIosIntro' => 'iOS will now ask for permission to add a VPN configuration. This is normal and required for any VPN app.',
			'vpnPermIosStep1' => 'A system dialog will appear titled "YueLink Would Like to Add VPN Configurations".',
			'vpnPermIosStep2' => 'Tap "Allow" to confirm. iOS may ask for your device passcode or Face ID.',
			'vpnPermIosStep3' => 'All traffic stays on your device — YueLink does not send your data to any external server.',
			'vpnPermIosContinue' => 'I Understand, Continue',
			'gatekeeperFixTitle' => 'Fix macOS Launch Block',
			'gatekeeperFixSubtitle' => 'Remove Apple\'s quarantine flag',
			'gatekeeperFixDialogTitle' => 'Repair macOS Gatekeeper',
			'gatekeeperFixDialogBody' => 'macOS attaches a quarantine flag to apps downloaded from the internet, which can cause repeated "YueLink can\'t be opened" warnings on every update. This will remove the flag from /Applications/YueLink.app and ask for your administrator password.',
			'gatekeeperFixConfirm' => 'Fix Now',
			'gatekeeperFixRunning' => 'Repairing… (please complete the password prompt)',
			'gatekeeperFixSuccess' => 'Repair complete. Future updates will launch without warnings.',
			'gatekeeperFixFailed' => 'Repair did not complete. You can also run the fix-gatekeeper.command script from the DMG.',
			'gatekeeperFixUnsupported' => 'This option is only available on the macOS .app build.',
			'notConnectedHintProxy' => 'Connect first to view proxy nodes',
			'connectToViewProxiesDesc' => 'Connect to the core to view and manage proxies.',
			'nodesCountLabel' => ({required Object n}) => '${n} Nodes',
			'switchedTo' => ({required Object name}) => 'Switched to ${name}',
			'switchFailed' => 'Failed to switch node',
			'testingGroup' => ({required Object name}) => 'Testing ${name}...',
			'directAuto' => 'Direct / Auto',
			'searchNodesHint' => 'Search nodes...',
			'sortByDelay' => 'Sort by delay',
			'cancelSort' => 'Cancel sort',
			'testUrlSettings' => 'Speed Test URL',
			'resetDefault' => 'Reset to Default',
			'unsavedChanges' => 'Unsaved Changes',
			'unsavedChangesBody' => 'Leave and discard unsaved changes?',
			'discardAndLeave' => 'Discard & Leave',
			'stayOnPage' => 'Stay',
			'noMatchingNodes' => 'No matching nodes',
			'testUrlDialogTitle' => 'Speed Test URL',
			'customUrlLabel' => 'Custom URL',
			'typeManual' => 'Manual',
			'typeAuto' => 'Auto',
			'typeFallback' => 'Fallback',
			'typeLoadBalance' => 'Load Balance',
			'testAll' => 'Test All',
			'testingCount' => ({required Object n}) => 'Testing (${n})',
			'nodesCount' => ({required Object visible, required Object total}) => '${visible}/${total} nodes',
			'loadFailed' => ({required Object error}) => 'Load failed: ${error}',
			'noProfiles' => 'No subscriptions',
			'addSubscriptionHint' => 'Click the button below to add a subscription',
			'pasteFromClipboard' => 'Paste from clipboard',
			'addSubscription' => 'Add Subscription',
			'downloadingSubscription' => 'Downloading subscription...',
			'updatingSubscription' => 'Updating subscription...',
			'updateSuccess' => 'Updated successfully',
			'updateFailed' => ({required Object error}) => 'Update failed: ${error}',
			'confirmDelete' => 'Confirm Delete',
			'confirmDeleteMessage' => ({required Object name}) => 'Are you sure to delete "${name}"?',
			'addSubscriptionDialogTitle' => 'Add Subscription',
			'editSubscriptionDialogTitle' => 'Edit Subscription',
			'nameLabel' => 'Name',
			'nameHint' => 'My Subscription',
			'urlLabel' => 'Subscription URL',
			'updateInterval' => 'Update Interval',
			'followGlobal' => 'Default (24h)',
			'days7' => '7 days',
			'hours6' => '6 hours',
			'hours12' => '12 hours',
			'hours24' => '24 hours',
			'hours48' => '48 hours',
			'usageLabel' => ({required Object used, required Object total}) => 'Used ${used} / ${total}',
			'expired' => 'Expired',
			'daysRemaining' => ({required Object days}) => '${days} days left',
			'needsUpdate' => 'Needs update',
			'updatedAt' => ({required Object time}) => 'Updated at ${time}',
			'noConfig' => 'Config file not found',
			'copyConfig' => 'Copy config',
			'copiedConfig' => 'Config copied',
			'copyLink' => 'Copy link',
			'copiedLink' => 'Subscription link copied',
			'viewConfig' => 'View config',
			'updateSubscription' => 'Update subscription',
			'clipboardNoUrl' => 'No valid subscription URL in clipboard',
			'addSuccess' => 'Added successfully',
			'addFailed' => ({required Object error}) => 'Failed to add: ${error}',
			'importLocalFile' => 'Import local file',
			'importLocalFileSuccess' => 'Imported successfully',
			'importLocalFileFailed' => 'Import failed: no valid YAML file selected',
			'importLocalNameHint' => 'My Config',
			'exportProfile' => 'Export config',
			'exportProfileSuccess' => ({required Object name}) => 'Exported: ${name}.yaml',
			'exportAllProfiles' => 'Export all configs',
			'importMultipleFiles' => 'Import config files',
			'exportFailed' => 'Export failed',
			'exportSelectDir' => 'Select export folder',
			'exportAllDone' => ({required Object count}) => 'Exported ${count} YAML files',
			'importBundleFailed' => 'Import failed: invalid backup file',
			'sectionSplitTunnel' => 'Split Tunneling',
			'splitTunnelMode' => 'Mode',
			'splitTunnelModeAll' => 'All apps',
			'splitTunnelModeWhitelist' => 'Proxy listed apps only',
			'splitTunnelModeBlacklist' => 'Bypass listed apps',
			'splitTunnelApps' => 'App List',
			'splitTunnelManage' => 'Manage Apps',
			'splitTunnelSearchHint' => 'Search apps...',
			'splitTunnelEffectHint' => 'Changes take effect on next connect',
			'sectionGeoResources' => 'Geo Resources',
			'geoResourcesHint' => 'Required geo database files for rule-based routing',
			'geoUpdateAll' => 'Update All',
			'geoUpdateSuccess' => 'Geo resources updated',
			'geoUpdateFailed' => 'Update failed',
			'geoNotFound' => 'Not found',
			'rollbackTitle' => 'Start Failed',
			'rollbackContent' => 'The configuration failed to start. Rollback to the last known-good config?',
			'rollbackConfirm' => 'Rollback',
			'rollbackSuccess' => 'Rolled back successfully',
			'rollbackFailed' => 'Rollback failed',
			'checkUpdate' => 'Check for Updates',
			'updateAvailable' => 'New version available',
			'updateDownload' => 'Download & Install',
			'updateDownloading' => 'Downloading...',
			'updateDownloadComplete' => 'Download complete',
			'updateDownloadFailed' => 'Download failed',
			'updateInstalling' => 'Opening installer...',
			'alreadyLatest' => 'Already up to date',
			'updateCheckFailed' => 'Failed to check for updates',
			'yamlInvalid' => 'Invalid YAML syntax',
			'sectionHotkeys' => 'Global Hotkeys',
			'hotkeyToggle' => 'Toggle connection (Ctrl+Alt+C)',
			'hotkeyHint' => 'Available on macOS and Windows',
			'notConnectedHintConnections' => 'Connect first to view active connections',
			'searchConnHint' => 'Search target, process, rule...',
			'closeAll' => 'Close All',
			'connectionsCount' => ({required Object count}) => '${count} connections',
			'connectionsCountFiltered' => ({required Object count}) => '${count} connections (filtered)',
			'noActiveConnections' => 'No active connections',
			'noMatchingConnections' => 'No matching results',
			'closeAllDialogTitle' => 'Close All Connections',
			'closeAllDialogMessage' => 'Are you sure to close all active connections?',
			'statConnections' => 'Connections',
			'statTotalDownload' => 'Total Download',
			'statTotalUpload' => 'Total Upload',
			'connectionDetailTitle' => 'Connection Details',
			'detailTarget' => 'Target',
			'detailProtocol' => 'Protocol',
			'detailSource' => 'Source',
			'detailTargetIp' => 'Target IP',
			'detailProxyChain' => 'Proxy Chain',
			'detailRule' => 'Rule',
			'detailProcess' => 'Process',
			'detailDuration' => 'Duration',
			'detailDownload' => 'Download',
			'detailUpload' => 'Upload',
			'detailConnectTime' => 'Connect Time',
			'notConnectedHintLog' => 'Connect first to view logs',
			'tabLogs' => 'Logs',
			'tabRules' => 'Rules',
			'searchLogsHint' => 'Search logs...',
			'searchLogsRegexHint' => 'Regex pattern...',
			'regexSearch' => 'Toggle regex search',
			'clearLogs' => 'Clear logs',
			'noLogs' => 'No logs',
			'logsCount' => ({required Object count}) => '${count} logs',
			'logLevelLabel' => ({required Object level}) => 'Level: ${level}',
			'rulesCount' => ({required Object count}) => '${count} rules',
			'matchedRulesCount' => ({required Object count}) => '${count} matched',
			'searchRulesHint' => 'Search rules...',
			'noMatchingRules' => 'No matching rules',
			'overwriteTitle' => 'Config Overwrite',
			'overwriteRulesTitle' => 'Overwrite Rules',
			'overwriteRulesDescription' => '• Scalar keys (mode, log-level, etc.) replace values in the subscription config\n• rules list is prepended before subscription rules\n• proxies / proxy-groups lists are appended after the subscription\n• dns / tun / sniffer / hosts / listeners blocks are merged into existing sections',
			'overwriteHintText' => '# Example:\n# mode: rule\n# rules:\n#   - DOMAIN-SUFFIX,example.com,DIRECT',
			'savedNextConnect' => 'Saved, will take effect on next connect',
			'sectionConnection' => 'Connection',
			'sectionCore' => 'Core',
			'sectionSubscription' => 'Subscription',
			'sectionAppearance' => 'Appearance',
			'sectionStatus' => 'Status',
			'sectionTools' => 'Tools',
			'sectionAbout' => 'About',
			'sectionSettings' => 'Settings',
			'sectionService' => 'My Subscription',
			'sectionSupport' => 'Support',
			'preferencesLabel' => 'Preferences',
			'sectionAccountActions' => 'Account',
			'upstreamProxy' => 'Upstream Proxy',
			'upstreamProxySub' => 'Route through a local gateway (e.g. soft router)',
			'upstreamProxyServer' => 'Server',
			'upstreamProxyPort' => 'Port',
			'upstreamProxyType' => 'Type',
			'upstreamProxySaved' => 'Upstream proxy saved',
			'upstreamProxyNotFound' => 'No proxy detected on gateway',
			'upstreamProxyHint' => 'Soft router IP, e.g. 192.168.1.1',
			'exportLogs' => 'Export Logs',
			'exportLogsCrash' => 'Crash Log',
			'exportLogsCore' => 'Core Log',
			'exportLogsEmpty' => 'No log file found',
			'exportLogsCopied' => 'Log copied to clipboard',
			'exportLogsSuccess' => 'Logs exported',
			'exportLogsFailed' => 'Export failed',
			'sectionDesktop' => 'Desktop',
			'sectionNetwork' => 'Network',
			'closeWindowBehavior' => 'Close Window',
			'closeBehaviorTray' => 'Minimize to tray',
			'closeBehaviorExit' => 'Exit application',
			'toggleConnectionHotkey' => 'Toggle Connection Hotkey',
			'hotkeyEdit' => 'Edit',
			'hotkeyListening' => 'Press a key combination...',
			'hotkeySaved' => 'Hotkey saved',
			'hotkeyFailed' => 'Failed to register hotkey',
			'geoDatabase' => 'Geo Database',
			'geoUpdateNow' => 'Update Now',
			'geoUpdated' => 'Geo database updated',
			'geoLastUpdated' => ({required Object date}) => 'Updated: ${date}',
			'linuxProxyNotice' => 'System proxy not managed automatically on Linux',
			'linuxProxyManual' => 'Manual proxy: 127.0.0.1:7890',
			'hotkeyLinuxNotice' => 'Not supported on all Linux desktops',
			'diagnostics' => 'Diagnostics',
			'viewStartupReport' => 'View startup report',
			'copiedToClipboard' => 'Copied to clipboard',
			'sectionLanguage' => 'Language',
			'connectionMode' => 'Connection Mode',
			'quicPolicyLabel' => 'QUIC Policy',
			'quicPolicyStandard' => 'Standard (Recommended)',
			'quicPolicyStandardDesc' => 'Only disables QUIC for YouTube video traffic so most services keep HTTP/3 while YouTube falls back to TCP.',
			'quicPolicyCompatibility' => 'Compatibility',
			'quicPolicyCompatibilityDesc' => 'Does not block QUIC. Best for MyTV Super and other Hong Kong streaming unlock scenarios.',
			'quicPolicyForceFallback' => 'Force Fallback',
			'quicPolicyForceFallbackDesc' => 'Rejects all UDP:443 traffic to force TCP fallback. Use only for troubleshooting video playback issues.',
			'modeTun' => 'TUN Mode',
			'modeSystemProxy' => 'System Proxy',
			'serviceModeLabel' => 'Service Mode',
			'serviceModeInstall' => 'Install Service',
			'serviceModeUninstall' => 'Uninstall',
			'serviceModeRefresh' => 'Refresh',
			'serviceModeNotInstalled' => 'Privileged service not installed',
			'serviceModeInstalled' => 'Privileged service installed',
			'serviceModeUnreachable' => 'Installed, but service is not ready',
			'serviceModeRunning' => ({required Object pid}) => 'Service ready · Core running (PID ${pid})',
			'serviceModeIdle' => 'Service ready · Core stopped',
			'serviceModeNeedsUpdate' => ({required Object version}) => 'Version mismatch (${version}) — please reinstall',
			'serviceModeUpdate' => 'Update',
			'serviceModeUpdateOk' => 'Service updated successfully',
			'serviceModeUpdateFailed' => ({required Object error}) => 'Service update failed: ${error}',
			'serviceModeInstallOk' => 'Desktop service installed',
			'serviceModeInstallFailed' => ({required Object error}) => 'Install service failed: ${error}',
			'serviceModeUninstallOk' => 'Desktop service removed',
			'serviceModeUninstallFailed' => ({required Object error}) => 'Uninstall service failed: ${error}',
			'msgSwitchedToTun' => 'Switched to TUN mode',
			'msgSwitchedToSystemProxy' => 'Switched to system proxy',
			'errTunSwitchFailed' => 'Failed to switch mode',
			'tunBypassLabel' => 'TUN Bypass',
			'tunBypassSub' => 'Exclude addresses or processes from TUN',
			'tunBypassAddrHint' => 'Bypass addresses (one per line, CIDR)',
			'tunBypassProcHint' => 'Bypass processes (one per line)',
			'tunBypassSaved' => 'TUN bypass settings saved',
			'tunStackLabel' => 'TUN Stack',
			'tunStackMixed' => 'Mixed',
			'tunStackSystem' => 'System',
			'tunStackGvisor' => 'gVisor',
			'setSystemProxyOnConnect' => 'Set system proxy on connect',
			'setSystemProxyOnConnectSub' => 'Auto-configure HTTP/SOCKS system proxy',
			'autoConnect' => 'Auto connect on startup',
			'launchAtStartupLabel' => 'Launch at startup',
			'launchAtStartupSub' => 'Auto start YueLink at login',
			'logLevelSetting' => 'Log Level',
			'configOverwrite' => 'Config Overwrite',
			'configOverwriteSub' => 'Add custom rules on top of subscription config',
			'updateAllNow' => 'Update all subscriptions now',
			'themeLabel' => 'Theme',
			'themeSystem' => 'System',
			'themeLight' => 'Light',
			'themeDark' => 'Dark',
			'languageAuto' => 'Follow system',
			'languageChinese' => '中文',
			'languageEnglish' => 'English',
			'coreStatus' => 'Core Status',
			'coreRunning' => 'Running',
			'coreStopped' => 'Stopped',
			'runMode' => 'Run Mode',
			'mixedPort' => 'Mixed Port',
			'apiPort' => 'API Port',
			'dnsQuery' => 'DNS Query',
			'runningConfig' => 'Running Config',
			'versionLabel' => 'Version',
			'coreLabel' => 'Core',
			'projectHome' => 'Project Home',
			'openSourceLicense' => 'Open Source License',
			'updatingAll' => 'Updating subscriptions...',
			'updateAllResult' => ({required Object updated, required Object failed}) => 'Update done: ${updated} succeeded, ${failed} failed',
			'dnsCacheCleared' => 'DNS cache cleared',
			'fakeIpCacheCleared' => 'Fake-IP cache cleared',
			'errorTimeout' => 'Request timed out, check your network',
			'errorNetwork' => 'Network error, check your connection',
			'overwritePortInvalid' => 'Port must be between 1 and 65535',
			'proxyTypeAll' => 'All',
			'sectionSubStore' => 'Sub-Store Conversion',
			'subStoreUrlLabel' => 'Sub-Store Server URL',
			'subStoreUrlHint' => 'http://127.0.0.1:25500',
			'subStoreUrlSub' => 'Convert V2Ray/SS links to Clash format automatically',
			'subStoreUrlSaved' => 'Sub-Store URL saved',
			'overwriteTabBasic' => 'Basic',
			'overwriteTabRules' => 'Rules',
			'overwriteTabAdvanced' => 'Advanced',
			'overwriteModeLabel' => 'Override Mode',
			'overwriteModeNone' => 'No override',
			'overwritePortLabel' => 'Mixed Port',
			'overwritePortHint' => 'e.g. 7890 (leave blank to skip)',
			'overwriteCustomRulesLabel' => 'Custom Rules (prepended)',
			'overwriteAddRule' => 'Add Rule',
			'overwriteRuleHint' => 'e.g. DOMAIN-SUFFIX,example.com,DIRECT',
			'overwriteExtraYamlLabel' => 'Extra YAML (appended)',
			'modeMock' => 'Mock',
			'modeSubprocess' => 'Subprocess',
			'domainHint' => 'Enter domain, e.g. google.com',
			'query' => 'Query',
			'noRecords' => 'No records',
			'updateAvailableV' => ({required Object v}) => 'v${v} available',
			'proxyProviderTitle' => 'Proxy Providers',
			'proxyProviderEmpty' => 'No proxy providers',
			'providerNodeCount' => ({required Object count}) => '${count} nodes',
			'providerUpdate' => 'Update',
			'providerHealthCheck' => 'Health Check',
			'providerUpdateSuccess' => 'Provider updated',
			'providerUpdateFailed' => 'Provider update failed',
			'providerHealthCheckDone' => 'Health check complete',
			'connectionModeLabel' => 'Mode',
			'errVpnPermission' => 'Network permission denied, cannot enable TUN mode',
			'errCoreStartFailed' => 'Core failed to start, check config or port conflicts',
			'errVpnTunnelFailed' => 'Tunnel setup failed',
			'msgConnected' => 'Connected',
			'errApiError' => ({required Object code, required Object body}) => 'API error: ${code} - ${body}',
			'errStartFailed' => ({required Object msg}) => 'Start failed: ${msg}',
			'msgDisconnected' => 'Disconnected',
			'errStopFailed' => 'Error while disconnecting',
			'errSystemProxyFailed' => 'System proxy setup failed. Configure proxy manually at 127.0.0.1',
			'errDownloadTimeout' => 'Download timed out, check your network',
			'errNetworkError' => ({required Object detail}) => 'Network error: ${detail}',
			'errDownloadHttpFailed' => ({required Object code}) => 'Download failed: HTTP ${code}',
			'chartLock' => 'Lock chart',
			'chartUnlock' => 'Unlock chart',
			'switchModeFailed' => 'Mode switch failed',
			'offlinePreview' => 'Offline preview — connect to switch nodes',
			'sortDefault' => 'Default',
			'sortLatencyAsc' => 'Latency ↑',
			'sortLatencyDesc' => 'Latency ↓',
			'sortNameAsc' => 'Name A-Z',
			'nodeViewCard' => 'Card view',
			'nodeViewList' => 'List view',
			'authLogin' => 'Sign In',
			'authLogout' => 'Sign Out',
			'authEmail' => 'Email',
			'authPassword' => 'Password',
			'authEmailHint' => 'your@email.com',
			'authPasswordHint' => 'Enter password',
			'authLoginSubtitle' => 'Sign in to your Yue.to account',
			'authLoggingIn' => 'Signing in...',
			'authLoginFailed' => 'Login failed',
			'authLogoutConfirm' => 'Sign out and clear local data?',
			'authSyncingSubscription' => 'Syncing subscription...',
			'authSyncSuccess' => 'Subscription synced',
			'authSyncFailed' => 'Subscription sync failed',
			'authAccountInfo' => 'Account',
			'authPlan' => 'Plan',
			'dashMyPlan' => 'My Plan',
			'authTraffic' => 'Traffic',
			'authExpiry' => 'Expiry',
			'authDaysRemaining' => ({required Object days}) => '${days} days remaining',
			'authExpired' => 'Expired',
			'authExpiryToday' => 'Expires today',
			'authRefreshInfo' => 'Refresh',
			'authSessionExpired' => 'Session expired, please sign in again',
			'authErrorBadCredentials' => 'Incorrect email or password',
			'authErrorNetwork' => 'Network error, please check your connection',
			'authErrorServer' => 'Service temporarily unavailable, please try again later',
			'mineTrafficTitle' => 'Traffic Usage',
			'mineSpeedUp' => 'Upload',
			'mineSpeedDown' => 'Download',
			'mineRemaining' => 'Remaining',
			'mineDevices' => 'Devices',
			'mineActions' => 'Quick Actions',
			'mineChangePassword' => 'Change Password',
			'mineTelegramGroup' => 'Join Telegram Group',
			'mineRenew' => 'Plans',
			'mineExpiryWarning' => 'Plan expiring soon — renew now',
			'mineExpiredWarning' => 'Plan has expired — renew now',
			'mineSyncing' => 'Syncing…',
			'mineSyncDone' => 'Synced',
			'mineSyncFailed' => 'Sync failed',
			'mineNotConnected' => 'Not connected',
			'mineEmby' => '悦视频',
			'mineEmbyNoAccess' => 'No 悦视频 access for this account',
			'mineEmbyOpening' => 'Opening 悦视频…',
			'mineEmbyOpenFailed' => 'Unable to open 悦视频',
			'mineEmbyNeedsVpn' => 'Please connect first to access Media',
			'minePrivacyPolicy' => 'Terms of Service',
			'goToHomeToProtect' => 'Go to Dashboard',
			'syncFirstSuccess' => 'Subscription synced — you\'re ready to connect',
			'storeCurrentPlan' => 'Current Plan',
			'storeAvailablePlans' => 'Available Plans',
			'storeBuyNow' => 'Buy Now',
			'storeRenew' => 'Renew',
			'storeUpgrade' => 'Upgrade',
			'storeNoPlans' => 'No plans available',
			'storeUnlimited' => 'Unlimited',
			'storeSelectPeriod' => 'Billing Period',
			'storeConfirmPurchase' => 'Confirm Order',
			'storePayNow' => 'Pay Now',
			'storeOrderCreating' => 'Creating order...',
			'storeOrderSuccess' => 'Payment Successful',
			'storeOrderPending' => 'Awaiting Payment',
			'storeOrderFailed' => 'Order Failed',
			'storeOrderCancelled' => 'Order Cancelled',
			'storeReturnToStore' => 'Back to Store',
			'storeRenewalReminder' => 'Plan expiring soon — renew now',
			'storeExpiredReminder' => 'Plan expired — buy now',
			'storePlanDetail' => 'Plan Details',
			'storeCheckResult' => 'Check Result',
			'storeCancelOrder' => 'Cancel Order',
			'storeOpenPaymentPage' => 'Open Payment Page',
			'storeCouponExpand' => 'Have a coupon?',
			'storeCouponCode' => 'Coupon Code',
			'storeCouponValidate' => 'Apply',
			'storeCouponValidating' => 'Validating...',
			'storeCouponValid' => 'Coupon applied',
			'storeCouponInvalid' => 'Invalid coupon',
			'storeDiscount' => 'Discount',
			'storeActualAmount' => 'You Pay',
			'storeCouponRemove' => 'Remove',
			'storePaymentMethod' => 'Payment Method',
			'storeHandlingFee' => 'Handling fee',
			'storeOrderHistory' => 'Order History',
			'storeOrderNo' => 'Order No.',
			_ => null,
		} ?? switch (path) {
			'storeOrderDate' => 'Date',
			'storeNoOrders' => 'No orders yet',
			'storeOrderDetail' => 'Order Detail',
			'storeOrderStatusPending' => 'Pending',
			'storeOrderStatusProcessing' => 'Processing',
			'storeOrderStatusCancelled' => 'Cancelled',
			'storeOrderStatusCompleted' => 'Completed',
			'dashSyncLabel' => 'Update Lines',
			'dashAnnouncementsLabel' => 'Announcements',
			'mineSyncLine' => 'Sync Lines',
			'mineSubscriptionManage' => 'Subscription Management',
			'dashAccountLabel' => 'Account',
			'dashLatestAnnouncement' => 'Latest Announcements',
			'noNetworkConnection' => 'No network connection',
			'dashGreeting' => 'Hello',
			'dashGreetingReturning' => 'Welcome back',
			'dashNoAnnouncements' => 'No announcements',
			'dashViewAll' => 'View all',
			'dashNoPlan' => 'No plan info',
			'oldPassword' => 'Old Password',
			'newPassword' => 'New Password',
			'passwordChangedSuccess' => 'Password changed successfully',
			'passwordChangeFailed' => 'Password change failed',
			'syncing' => 'Syncing...',
			'syncComplete' => 'Sync complete',
			'syncFailed' => 'Sync failed',
			'notConnected' => 'Not connected',
			'switchProfileTitle' => 'Switch Subscription',
			'switchProfileMessage' => ({required Object name}) => 'Switch to "${name}"? This will use its nodes and rules.',
			'switchProfileReconnectHint' => 'Connection is active. You need to reconnect after switching.',
			'switchProfileConfirm' => 'Switch',
			'onboardingWelcome' => 'Welcome to YueLink',
			'onboardingWelcomeDesc' => 'Global network · Fast, secure, reliable · Sync across devices',
			'onboardingConnect' => 'One-Tap Connect',
			'onboardingConnectDesc' => 'Smart node selection · No config needed · Ready out of the box',
			'onboardingNodes' => 'Emby Streaming Included',
			'onboardingNodesDesc' => 'Licensed movies & TV shows · Watch as soon as you\'re connected',
			'onboardingStore' => 'Daily Check-in for Traffic',
			'onboardingStoreDesc' => 'Earn free traffic every day · One account syncs all platforms',
			'onboardingSkip' => 'Skip',
			'onboardingNext' => 'Next',
			'onboardingDone' => 'Get Started',
			'chainProxy' => 'Proxy Chain',
			'chainEntry' => 'Entry',
			'chainExit' => 'Exit',
			'chainConnect' => 'Connect Chain',
			'chainDisconnect' => 'Disconnect',
			'chainConnected' => 'Proxy chain connected',
			'chainDisconnected' => 'Proxy chain disconnected',
			'chainConnectFailed' => 'Chain connect failed',
			'chainNeedConnect' => 'Connect first',
			'chainNoGroup' => 'No proxy group available',
			'chainNeedTwoNodes' => 'Need 2+ nodes',
			'chainNodeDuplicate' => 'Node already in chain',
			'chainClear' => 'Clear',
			'chainEmptyHint' => 'No nodes in chain',
			'chainEmptyDesc' => 'Long-press any node or group on the Lines page to add it',
			'chainAddHint' => 'Added to proxy chain',
			'chainPickerTitle' => 'Add to Chain',
			'chainPickerSearch' => 'Search nodes / groups...',
			'chainSectionGroups' => 'Proxy Groups',
			'chainSectionNodes' => 'Nodes',
			'msgSystemProxyConflict' => 'Another proxy client took over — stopping YueLink proxy',
			'checkinTitle' => 'Daily Check-in',
			'checkinDesc' => 'Check in to get traffic or balance rewards',
			'checkinAction' => 'Check in',
			'checkinDone' => 'Checked in',
			'checkinAlready' => 'Already checked in today',
			'checkinOtherDevice' => 'Checked in on another device',
			'checkinNeedLogin' => 'Please login first',
			'checkinFailed' => 'Check-in failed',
			'checkinReward' => 'Reward',
			'checkinTrafficReward' => ({required Object amount}) => 'Got ${amount} traffic!',
			'checkinBalanceReward' => ({required Object amount}) => 'Got ¥${amount} balance!',
			'qaSmartSelect' => 'Smart Select',
			'qaSceneMode' => 'Scene Mode',
			'qaSpeedTest' => 'Speed Test',
			'statusExpiry' => 'Expiry',
			'statusTraffic' => 'Traffic',
			'statusHealth' => 'Health',
			'statusExpired' => 'Expired',
			'statusUnlimited' => 'Unlimited',
			'statusExhausted' => 'Exhausted',
			'gradeExcellent' => 'Good',
			'gradeFair' => 'Fair',
			'gradePoor' => 'Poor',
			'gradeUnknown' => 'N/A',
			'gradeOffline' => 'Offline',
			'embyEnter' => 'Enter',
			'embyNoAccessHint' => 'Subscribe to YueVideo to watch movies, TV shows and anime',
			'embyWebHint' => 'Tap to enter YueVideo',
			'embyNoContent' => 'No content',
			'embyNoLibrary' => 'No library',
			'embyLoadFailed' => 'Load failed',
			'embyTapRetry' => 'Tap to retry',
			'embyGetFailed' => 'Failed to load libraries',
			'errNativeLib' => 'Native library load failed',
			'errNativeLibHint' => 'Package may be corrupted, please reinstall',
			'errCoreInit' => 'Core init failed',
			'errCoreInitHint' => 'Try restarting or clearing local cache',
			'errVpnDenied' => 'Network permission denied',
			'errVpnDeniedHint' => 'Authorize in system settings',
			'errTunnel' => 'Tunnel creation failed',
			'errTunnelHint' => 'Try rebuilding network config',
			'errConfig' => 'Config parse failed',
			'errConfigHint' => 'Try re-syncing subscription',
			'errCoreStart' => 'Core start failed',
			'errCoreStartHint' => 'Check diagnostics report',
			'errApiTimeout' => 'API timeout, core may have crashed',
			'errApiTimeoutHint' => 'Check diagnostics for details',
			'errCoreCrash' => 'Core crashed after start',
			'errCoreCrashHint' => 'Check Go Core log in diagnostics',
			'errGeo' => 'Geo data file error',
			'errGeoHint' => 'Try clearing local cache',
			'errGeneric' => 'Connection failed',
			'errGenericHint' => 'Go to repair page for details',
			'goRepair' => 'Go to Repair',
			'copyReport' => 'Copy Report',
			'reportCopied' => 'Startup report copied',
			'goCoreLogs' => ({required Object count}) => 'Go Core log (last ${count} lines):',
			'recentlyUsed' => 'Recently Used',
			'repairTools' => 'Repair Tools',
			'repairRebuildVpn' => 'Rebuild Network Config',
			'repairRebuildVpnHint' => 'Remove old tunnel, re-create on next connect',
			'repairClearTunnel' => 'Clear Tunnel Config',
			'repairClearTunnelHint' => 'Delete App Group config and GEO data',
			'repairResync' => 'Re-sync Subscription',
			'repairResyncHint' => 'Re-fetch subscription config from server',
			'repairClearCache' => 'Clear Local Cache',
			'repairClearCacheHint' => 'Delete local config files, logs, startup report',
			'repairRestartCore' => 'Restart Core',
			'repairRestartCoreHint' => 'Rebuild core state without touching the subscription — use when latency tests all time out',
			'repairOneClick' => 'One-Click Repair All',
			'repairRunning' => 'Repairing...',
			'repairNeedLogin' => 'Please login first',
			'dataMonitor' => 'Data Monitor',
			'vpnNotRunning' => 'Not connected',
			'sectionModules' => 'Modules',
			'modulesLabel' => 'Rule Modules',
			'modulesEmpty' => 'No modules installed',
			'moduleAddUrl' => 'Module URL',
			'moduleAdding' => 'Adding module…',
			'moduleAddSuccess' => 'Module added',
			'moduleRefresh' => 'Refresh',
			'moduleDelete' => 'Delete module',
			'moduleDeleteConfirm' => 'Delete this module?',
			'moduleRuleCount' => 'Rules',
			'moduleNotActive' => 'Not active in current version',
			'moduleMitmDetected' => 'MITM hostnames detected',
			'moduleScriptDetected' => 'Scripts detected',
			'moduleRewriteDetected' => 'URL Rewrites detected',
			'moduleFutureVersion' => '— will be enabled in a future version',
			'mitmEngine' => 'MITM Engine',
			'mitmEngineRunning' => 'Running',
			'mitmEngineStopped' => 'Stopped',
			'mitmEngineStart' => 'Start',
			'mitmEngineStop' => 'Stop',
			'mitmEnginePort' => 'Port',
			'mitmCertTitle' => 'Root CA Certificate',
			'mitmCertInstall' => 'Install Certificate',
			'mitmCertGenerate' => 'Generate',
			'mitmCertExport' => 'Export PEM',
			'mitmCertFingerprint' => 'SHA-256 Fingerprint',
			'mitmCertExpiry' => 'Expires',
			'mitmCertNotFound' => 'No certificate yet',
			'mitmCertGuideTitle' => 'Certificate Installation',
			'mitmHostnameCount' => 'MITM Hostnames',
			'importAllResultAllOk' => ({required Object ok}) => 'Imported ${ok} subscriptions',
			'importAllResultPartial' => ({required Object ok, required Object failed}) => 'Imported ${ok}, failed ${failed}',
			'scanQrImport' => 'Scan QR',
			'scanQrTitle' => 'Scan QR Code',
			'scanQrInvalidUrl' => 'Scanned content is not a valid URL',
			'scanQrPermissionDenied' => 'Camera permission denied',
			'webLoadFailed' => 'Load failed',
			'hotkeyPrompt' => 'Press shortcut keys...',
			'loadAppListFailed' => 'Failed to load app list',
			'repairActionDone' => 'Done',
			'repairActionFailed' => 'Failed',
			'installIpaHint' => 'Download the IPA from the opened page and install via TrollStore',
			'installIosManual' => 'Auto-install not supported on iOS. Download from GitHub Releases',
			'installUnsupported' => 'Auto-install not supported on this platform',
			'loading' => 'Loading...',
			'latestAnnouncements' => 'Announcements',
			'viewAll' => 'View all',
			'smartSelect' => 'Smart Select',
			'embySearchHint' => 'Search all libraries...',
			'refresh' => 'Refresh',
			'otherSubscriptions' => 'Other Subscriptions',
			'heroBannerEmby' => '4K movies · J-Drama · Anime, watch anywhere anytime',
			'heroBannerAi' => 'Dedicated line to ChatGPT / Gemini, low-latency stable access',
			'heroBannerUpgrade' => 'Upgrade your plan for more nodes · more traffic · faster speed',
			'embyPlay' => 'Play',
			'embyDirector' => 'Director',
			'embyCast' => 'Cast',
			'embySimilar' => 'Similar',
			'embyNoResults' => 'No results',
			'embyResumeTitle' => 'Resume Playback',
			'embyRestartBtn' => 'Restart',
			'embyContinueBtn' => 'Continue',
			'embySpeedUp' => '▶▶ 2x Speed',
			'embyPlayFailed' => 'Playback failed',
			'embyNoAudioTrack' => 'No audio tracks',
			'close' => 'Close',
			'embySubtitleSize' => 'Subtitle size',
			'feedbackEmpty' => 'Please enter feedback content',
			'feedbackSuccess' => 'Thanks for your feedback, we will handle it shortly',
			'feedbackFailed' => 'Submit failed, please try again later',
			'feedbackNetError' => 'Network error, please try again later',
			'feedbackTitle' => 'Feedback',
			'feedbackHint' => 'Please describe the issue or suggestion in detail…',
			'feedbackContactHint' => 'Telegram / Email',
			'feedbackSubmit' => 'Submit Feedback',
			'available' => 'Available',
			'applyBestNode' => 'Apply best: ',
			'repairTitle' => 'Connection Repair',
			'diagnosticsLabel' => 'Diagnostics',
			'diagnosticsHint' => 'View steps and timing of last connection startup',
			'networkDiagnostics' => 'Network Diagnostics',
			'trafficUsedTotal' => 'Used / Total',
			'trafficRemaining' => 'Remaining',
			'privacy' => 'Privacy',
			'telemetryTitle' => 'Anonymous usage stats',
			'telemetrySubtitle' => 'Help improve YueLink, no PII',
			'telemetryViewEvents' => 'View sent events',
			'telemetryClientId' => 'Client ID',
			'telemetrySessionId' => 'Session ID',
			'telemetryEventCount' => ({required Object n}) => 'Last ${n} events',
			'telemetryEmpty' => 'No events recorded',
			'calendarTitle' => 'Sign-In Calendar',
			'calendarMonthLabel' => ({required Object year, required Object month}) => '${year}-${month}',
			'calendarPrevMonth' => 'Previous month',
			'calendarNextMonth' => 'Next month',
			'calendarLoadFailed' => 'Load failed — pull to retry',
			'calendarEmpty' => 'No data',
			'calendarRetry' => 'Retry',
			'calendarPleaseLogin' => 'Please log in first',
			'calendarStreakLabel' => 'Streak',
			'calendarSignedThisMonth' => 'Signed this month',
			'calendarMultiplier' => 'Bonus',
			'calendarBtnResignWithCost' => ({required Object cost}) => 'Resign yesterday · ${cost} pts',
			'calendarBtnClose' => 'Close',
			'calendarBtnSignedToday' => 'Signed',
			'calendarLegendSigned' => 'Signed',
			'calendarLegendCard' => 'Card',
			'calendarLegendMissed' => 'Missed',
			'calendarLegendTodayMiss' => 'Today (not yet)',
			'calendarLegendFuture' => 'Future',
			'calendarUnit' => 'd',
			'calendarSuffixOf' => ({required Object total}) => '/${total}',
			'calendarEntryTitle' => 'Sign-In Calendar',
			'calendarEntrySubtitle' => 'Monthly view · streak rewards · resign with points',
			'weekMon' => 'Mon',
			'weekTue' => 'Tue',
			'weekWed' => 'Wed',
			'weekThu' => 'Thu',
			'weekFri' => 'Fri',
			'weekSat' => 'Sat',
			'weekSun' => 'Sun',
			'checkinStreakSuffix' => ({required Object n}) => '${n}-day streak',
			'resignTitle' => 'Resign Card',
			'resignDesc' => ({required Object cost}) => 'Pay ${cost} pts to fill yesterday — your streak stays alive.',
			'resignCurrentPoints' => 'Current points: ',
			'resignNeedPoints' => ({required Object cost}) => 'Need: ${cost} pts',
			'resignInsufficient' => 'Insufficient points. Earn more via daily check-in or group betting.',
			'resignCancel' => 'Cancel',
			'resignConfirm' => 'Resign',
			'iosGuideTitle' => 'iOS Install Guide',
			'iosGuideEntry' => 'iOS Install Methods',
			'iosGuideIntro' => 'YueLink for iOS is sideloaded. The three options have different VPN-availability trade-offs.',
			'iosGuideErrorBanner' => ({required Object seconds}) => 'VPN dropped within ${seconds}s — almost always TrollStore / unsigned IPA. Re-install via AltStore or SideStore to fix.',
			'iosGuideMethodAltstoreTitle' => 'AltStore / SideStore',
			'iosGuideMethodAltstoreTag' => 'Recommended',
			'iosGuideMethodAltstoreProVpn' => '✅ Full VPN works (entitlement trusted by system)',
			'iosGuideMethodAltstoreProFree' => '✅ Free, signed with your Apple ID',
			'iosGuideMethodAltstoreProDevice' => '✅ Supports all device generations',
			'iosGuideMethodAltstoreCon7d' => '⚠️ 7-day re-sign required (AltServer / SideServer on desktop)',
			'iosGuideMethodAltstoreConLimit' => '⚠️ Free Apple ID can hold only 3 apps at once',
			'iosGuideMethodAltstoreHowto' => 'Install AltServer / SideServer on desktop → install AltStore / SideStore on iPhone → drop YueLink IPA into the desktop tool or import via AltStore → Settings → General → VPN & Device Management → trust the developer cert',
			'iosGuideMethodTrollTitle' => 'TrollStore',
			'iosGuideMethodTrollTag' => 'VPN won\'t work',
			'iosGuideMethodTrollProForever' => '✅ Permanent, no re-signing',
			'iosGuideMethodTrollConVpn' => '🚫 VPN (NetworkExtension) doesn\'t work',
			'iosGuideMethodTrollConFail' => '🚫 PacketTunnel starts then drops — looks connected but no traffic flows',
			'iosGuideMethodTrollConDevice' => '🚫 Only specific older-iOS exploit-eligible devices',
			'iosGuideMethodTrollHowto' => 'TrollStore bypasses signature checks via a CoreTrust bug, but NetworkExtension still requires an Apple-issued provisioning profile. TrollStore IPAs lack this trust chain — the system starts PacketTunnel but blocks all packets.\n\nFine if you only use YueLink for non-VPN features (e.g. Emby). For proxying, switch to AltStore / SideStore.',
			'iosGuideMethodIpaTitle' => 'Direct IPA / 3rd-party distribution',
			'iosGuideMethodIpaTag' => 'Risky',
			'iosGuideMethodIpaProSigned' => '✅ Some commercially-signed builds work',
			'iosGuideMethodIpaConRevoke' => '⚠️ Apple may revoke commercial certs anytime, crashing all installs',
			'iosGuideMethodIpaConTamper' => '⚠️ 3rd-party distribution channels can tamper with the binary',
			'iosGuideMethodIpaHowto' => 'Only sign and install IPAs from the official GitHub Releases. Avoid pre-signed installs from unknown sources.',
			'iosGuideAck' => 'Got it',
			_ => null,
		};
	}
}
