import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../l10n/app_strings.dart';
import '../providers/core_provider.dart';
import '../providers/split_tunnel_provider.dart';
import '../services/app_notifier.dart';
import '../services/auto_update_service.dart';
import '../services/core_manager.dart';
import '../services/geo_resource_service.dart';
import '../services/settings_service.dart';
import '../services/vpn_service.dart';
import '../services/webdav_service.dart';
import '../services/update_checker.dart';
import '../theme.dart';
import 'log_page.dart';
import 'overwrite_page.dart';
import 'proxy_provider_page.dart';
import 'settings/dns_query_page.dart';
import 'settings/running_config_page.dart';

// ── Settings-level providers ─────────────────────────────────────────────────

final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final languageProvider = StateProvider<String>((ref) => 'zh');

// ─────────────────────────────────────────────────────────────────────────────

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _launchAtStartup = false;
  int _autoUpdateInterval = 24;
  UpdateInfo? _pendingUpdate;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final startup = await SettingsService.getLaunchAtStartup();
    final interval = await SettingsService.getAutoUpdateInterval();
    if (mounted) {
      setState(() {
        _launchAtStartup = startup;
        _autoUpdateInterval = interval;
      });
    }
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateChecker.instance.check();
    if (mounted && info != null) {
      setState(() => _pendingUpdate = info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = ref.watch(themeProvider);
    final language = ref.watch(languageProvider);
    final autoConnect = ref.watch(autoConnectProvider);
    final connectionMode = ref.watch(connectionModeProvider);
    final logLevel = ref.watch(logLevelProvider);
    final systemProxyOnConnect = ref.watch(systemProxyOnConnectProvider);
    final status = ref.watch(coreStatusProvider);
    final isDesktop = Platform.isMacOS || Platform.isWindows;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top bar ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.navSettings.toUpperCase(),
                  style: YLText.caption.copyWith(
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w600,
                    color: YLColors.zinc400,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.navSettings,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 0.5,
            color: dividerColor,
          ),

          // ── Content ──────────────────────────────────────────────
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [

              // ══ 1. General ════════════════════════════════════════
              _SectionTitle(s.sectionAppearance),
              _SettingsCard(
                child: Column(
                  children: [
                    // Theme
                    YLInfoRow(
                      label: s.sectionAppearance,
                      trailing: SegmentedButton<ThemeMode>(
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        segments: [
                          ButtonSegment(
                              value: ThemeMode.system,
                              label: Text(s.themeSystem)),
                          ButtonSegment(
                              value: ThemeMode.light,
                              label: Text(s.themeLight)),
                          ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text(s.themeDark)),
                        ],
                        selected: {theme},
                        onSelectionChanged: (v) {
                          ref.read(themeProvider.notifier).state = v.first;
                          SettingsService.setThemeMode(v.first);
                        },
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Language
                    YLInfoRow(
                      label: s.sectionLanguage,
                      trailing: SegmentedButton<String>(
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        segments: [
                          ButtonSegment(
                              value: 'zh', label: Text(s.languageChinese)),
                          ButtonSegment(
                              value: 'en', label: Text(s.languageEnglish)),
                        ],
                        selected: {language},
                        onSelectionChanged: (v) async {
                          ref.read(languageProvider.notifier).state = v.first;
                          await SettingsService.setLanguage(v.first);
                        },
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Auto connect
                    YLSettingsRow(
                      title: s.autoConnect,
                      trailing: Switch(
                        value: autoConnect,
                        onChanged: (v) async {
                          ref.read(autoConnectProvider.notifier).state = v;
                          await SettingsService.setAutoConnect(v);
                        },
                      ),
                    ),
                    if (isDesktop) ...[
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLSettingsRow(
                        title: s.launchAtStartupLabel,
                        description: s.launchAtStartupSub,
                        trailing: Switch(
                          value: _launchAtStartup,
                          onChanged: (v) async {
                            setState(() => _launchAtStartup = v);
                            await SettingsService.setLaunchAtStartup(v);
                            if (v) {
                              await launchAtStartup.enable();
                            } else {
                              await launchAtStartup.disable();
                            }
                          },
                        ),
                      ),
                    ],
                    if (isDesktop) ...[
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLInfoRow(
                        label: s.sectionHotkeys,
                        value: 'Ctrl+Alt+C',
                      ),
                    ],
                  ],
                ),
              ),

              // ══ 2. Proxy ══════════════════════════════════════════
              _SectionTitle(s.sectionConnection),
              _SettingsCard(
                child: Column(
                  children: [
                    YLInfoRow(
                      label: s.connectionMode,
                      trailing: DropdownButton<String>(
                        value: connectionMode,
                        underline: const SizedBox.shrink(),
                        style: YLText.body,
                        items: [
                          DropdownMenuItem(
                              value: 'tun', child: Text(s.modeTun)),
                          DropdownMenuItem(
                              value: 'systemProxy',
                              child: Text(s.modeSystemProxy)),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          ref.read(connectionModeProvider.notifier).state = v;
                          await SettingsService.setConnectionMode(v);
                        },
                      ),
                    ),
                    if (isDesktop) ...[
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLSettingsRow(
                        title: s.setSystemProxyOnConnect,
                        description: s.setSystemProxyOnConnectSub,
                        trailing: Switch(
                          value: systemProxyOnConnect,
                          onChanged: (v) async {
                            ref
                                .read(systemProxyOnConnectProvider.notifier)
                                .state = v;
                            await SettingsService.setSystemProxyOnConnect(v);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ══ 3. Subscription & Sync ════════════════════════════
              _SectionTitle(s.sectionSubscription),
              _SettingsCard(
                child: Column(
                  children: [
                    YLInfoRow(
                      label: s.autoUpdateInterval,
                      trailing: DropdownButton<int>(
                        value: _autoUpdateInterval,
                        underline: const SizedBox.shrink(),
                        style: YLText.body,
                        items: [
                          DropdownMenuItem(
                              value: 0, child: Text(s.disabled)),
                          DropdownMenuItem(
                              value: 6, child: Text(s.hours6)),
                          DropdownMenuItem(
                              value: 12, child: Text(s.hours12)),
                          DropdownMenuItem(
                              value: 24, child: Text(s.hours24)),
                          DropdownMenuItem(
                              value: 48, child: Text(s.hours48)),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() => _autoUpdateInterval = v);
                          await SettingsService.setAutoUpdateInterval(v);
                        },
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.updateAllNow,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      onTap: () => _updateAllProfiles(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const _SubStoreSection(),
              const SizedBox(height: 8),
              const _WebDavSection(),

              // ══ 4. Core ═══════════════════════════════════════════
              _SectionTitle(s.sectionCore),
              _SettingsCard(
                child: Column(
                  children: [
                    // Status info
                    YLInfoRow(
                      label: s.coreStatus,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          YLStatusDot(
                            color: status == CoreStatus.running
                                ? YLColors.connected
                                : YLColors.zinc400,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            status == CoreStatus.running
                                ? s.coreRunning
                                : s.coreStopped,
                            style: YLText.body.copyWith(
                              color: status == CoreStatus.running
                                  ? YLColors.connected
                                  : YLColors.zinc500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.runMode,
                      trailing: _ModeChip(mode: CoreManager.instance.mode),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.mixedPort,
                      value: '${AppConstants.defaultMixedPort}',
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.apiPort,
                      value: '${AppConstants.defaultApiPort}',
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Log level
                    YLInfoRow(
                      label: s.logLevelSetting,
                      trailing: DropdownButton<String>(
                        value: logLevel,
                        underline: const SizedBox.shrink(),
                        style: YLText.body,
                        items: const [
                          DropdownMenuItem(
                              value: 'debug', child: Text('Debug')),
                          DropdownMenuItem(
                              value: 'info', child: Text('Info')),
                          DropdownMenuItem(
                              value: 'warning', child: Text('Warning')),
                          DropdownMenuItem(
                              value: 'error', child: Text('Error')),
                          DropdownMenuItem(
                              value: 'silent', child: Text('Silent')),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          ref.read(logLevelProvider.notifier).state = v;
                          await SettingsService.setLogLevel(v);
                          if (status == CoreStatus.running) {
                            try {
                              await CoreManager.instance.api.setLogLevel(v);
                            } catch (_) {}
                          }
                        },
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.configOverwrite,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const OverwritePage()),
                      ),
                    ),
                  ],
                ),
              ),

              // ══ 5. Diagnostics ════════════════════════════════════
              _SectionTitle(s.sectionTools),
              _SettingsCard(
                child: Column(
                  children: [
                    // Logs
                    YLInfoRow(
                      label: s.tabLogs,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      enabled: status == CoreStatus.running,
                      onTap: status == CoreStatus.running
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const LogPage()),
                              )
                          : null,
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Proxy providers
                    YLInfoRow(
                      label: s.proxyProviderTitle,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      enabled: status == CoreStatus.running,
                      onTap: status == CoreStatus.running
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const ProxyProviderPage()),
                              )
                          : null,
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // DNS query
                    YLInfoRow(
                      label: s.dnsQuery,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      enabled: status == CoreStatus.running,
                      onTap: status == CoreStatus.running
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const DnsQueryPage()),
                              )
                          : null,
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Running config
                    YLInfoRow(
                      label: s.runningConfig,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      enabled: status == CoreStatus.running,
                      onTap: status == CoreStatus.running
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const RunningConfigPage()),
                              )
                          : null,
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Flush DNS cache
                    YLInfoRow(
                      label: s.flushDnsCache,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      enabled: status == CoreStatus.running,
                      onTap: status == CoreStatus.running
                          ? () => _flushDns(context)
                          : null,
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Flush Fake-IP cache
                    YLInfoRow(
                      label: s.flushFakeIpCache,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      enabled: status == CoreStatus.running,
                      onTap: status == CoreStatus.running
                          ? () => _flushFakeIp(context)
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Geo resources (inline)
              const _GeoResourceSection(),
              const SizedBox(height: 8),

              // Split tunnel (Android only)
              if (Platform.isAndroid) ...[
                const _SplitTunnelSection(),
                const SizedBox(height: 8),
              ],

              // ══ About ═════════════════════════════════════════════
              _SectionTitle(s.sectionAbout),
              _SettingsCard(
                child: Column(
                  children: [
                    YLInfoRow(
                      label: s.versionLabel,
                      value: AppConstants.appVersion,
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.coreLabel,
                      value: 'mihomo (Clash.Meta)',
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.projectHome,
                      trailing: const Icon(Icons.open_in_new,
                          size: 14, color: YLColors.zinc400),
                      onTap: () =>
                          _launchUrl('https://github.com/onesyue/yuelink'),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.checkUpdate,
                      trailing: _checkingUpdate
                          ? const SizedBox(
                              width: 14, height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : _pendingUpdate != null
                              ? YLChip(
                                  s.updateAvailableV(
                                      _pendingUpdate!.latestVersion),
                                  color: YLColors.primary)
                              : const Icon(Icons.chevron_right,
                                  size: 18, color: YLColors.zinc400),
                      onTap: _checkingUpdate
                          ? null
                          : _pendingUpdate != null
                              ? () async {
                                  final uri = Uri.parse(
                                      _pendingUpdate!.releaseUrl);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri,
                                        mode: LaunchMode.externalApplication);
                                  }
                                }
                              : () async {
                                  setState(() => _checkingUpdate = true);
                                  final info =
                                      await UpdateChecker.instance.check();
                                  if (mounted) {
                                    setState(() {
                                      _pendingUpdate = info;
                                      _checkingUpdate = false;
                                    });
                                    if (info == null) {
                                      AppNotifier.info(s.alreadyLatest);
                                    }
                                  }
                                },
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.openSourceLicense,
                      trailing: const Icon(Icons.chevron_right,
                          size: 18, color: YLColors.zinc400),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: AppConstants.appName,
                        applicationVersion: AppConstants.appVersion,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateAllProfiles(BuildContext context) async {
    final s = S.of(context);
    AppNotifier.info(s.updatingAll);
    final result = await AutoUpdateService.instance.updateAll();
    AppNotifier.success(s.updateAllResult(result.updated, result.failed));
  }

  Future<void> _flushDns(BuildContext context) async {
    final s = S.of(context);
    final ok = await CoreManager.instance.api.flushDnsCache();
    if (ok) {
      AppNotifier.success(s.dnsCacheCleared);
    } else {
      AppNotifier.error(s.operationFailed);
    }
  }

  Future<void> _flushFakeIp(BuildContext context) async {
    final s = S.of(context);
    final ok = await CoreManager.instance.api.flushFakeIpCache();
    if (ok) {
      AppNotifier.success(s.fakeIpCacheCleared);
    } else {
      AppNotifier.error(s.operationFailed);
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ── Sub-Store Section ─────────────────────────────────────────────────────────

class _SubStoreSection extends StatefulWidget {
  const _SubStoreSection();

  @override
  State<_SubStoreSection> createState() => _SubStoreSectionState();
}

class _SubStoreSectionState extends State<_SubStoreSection> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    SettingsService.getSubStoreUrl().then((url) {
      if (mounted) _ctrl.text = url;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.subStoreUrlSub,
                style: YLText.caption.copyWith(
                    color: isDark ? YLColors.zinc500 : YLColors.zinc400)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                labelText: s.subStoreUrlLabel,
                hintText: s.subStoreUrlHint,
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save_outlined, size: 18),
                  tooltip: s.save,
                  onPressed: _save,
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    await SettingsService.setSubStoreUrl(_ctrl.text.trim());
    if (mounted) AppNotifier.success(S.of(context).subStoreUrlSaved);
  }
}

// ── WebDAV Section ────────────────────────────────────────────────────────────

class _WebDavSection extends StatefulWidget {
  const _WebDavSection();

  @override
  State<_WebDavSection> createState() => _WebDavSectionState();
}

class _WebDavSectionState extends State<_WebDavSection> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await SettingsService.getWebDavConfig();
    if (mounted) {
      _urlCtrl.text = cfg['url'] ?? '';
      _userCtrl.text = cfg['username'] ?? '';
      _passCtrl.text = cfg['password'] ?? '';
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlCtrl,
              decoration: InputDecoration(
                labelText: s.webdavUrl,
                hintText: 'https://example.com/dav',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userCtrl,
              decoration: InputDecoration(
                labelText: s.username,
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: s.password,
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      size: 18),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(s.testConnection),
                    onPressed: _loading ? null : _testConnection,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                    label: Text(s.upload),
                    onPressed: _loading ? null : _upload,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.cloud_download_outlined, size: 16),
                    label: Text(s.download),
                    onPressed: _loading ? null : _download,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveConfig() async {
    await SettingsService.setWebDavConfig(
      url: _urlCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
  }

  Future<void> _testConnection() async {
    final s = S.of(context);
    await _saveConfig();
    setState(() => _loading = true);
    try {
      final ok = await WebDavService.instance.testConnection();
      if (ok) {
        AppNotifier.success(s.connectionSuccess);
      } else {
        AppNotifier.error(s.connectionFailed);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final s = S.of(context);
    await _saveConfig();
    setState(() => _loading = true);
    try {
      await WebDavService.instance.upload();
      AppNotifier.success(s.uploadSuccess);
    } catch (e) {
      AppNotifier.error(s.uploadFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final s = S.of(context);
    await _saveConfig();
    setState(() => _loading = true);
    try {
      await WebDavService.instance.download();
      AppNotifier.success(s.downloadSuccess);
    } catch (e) {
      AppNotifier.error(s.downloadFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final CoreMode mode;
  const _ModeChip({required this.mode});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final (name, color) = switch (mode) {
      CoreMode.mock => (s.modeMock, Colors.amber.shade700),
      CoreMode.ffi => ('FFI', Colors.green),
      CoreMode.subprocess => (s.modeSubprocess, Colors.blue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Text(name,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ── Settings page helper widgets ─────────────────────────────────────────────

/// Section title — matches the dashboard top bar label style.
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
          color: YLColors.zinc400,
        ),
      ),
    );
  }
}

/// Card container matching the dashboard card style.
class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── Geo Resource Section ──────────────────────────────────────────────────────

class _GeoResourceSection extends StatefulWidget {
  const _GeoResourceSection();

  @override
  State<_GeoResourceSection> createState() => _GeoResourceSectionState();
}

class _GeoResourceSectionState extends State<_GeoResourceSection> {
  List<GeoFileInfo>? _infos;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final infos = await GeoResourceService.instance.getAllInfo();
    if (mounted) setState(() => _infos = infos);
  }

  Future<void> _updateAll() async {
    setState(() => _updating = true);
    final s = S.of(context);
    try {
      final results = await GeoResourceService.instance.updateAll();
      final allOk = results.values.every((ok) => ok);
      if (allOk) {
        AppNotifier.success(s.geoUpdateSuccess);
      } else {
        AppNotifier.warning(s.geoUpdateFailed);
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final infos = _infos;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return _SettingsCard(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Icon(Icons.public_rounded, size: 16,
                    color: isDark ? YLColors.zinc400 : YLColors.zinc500),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.sectionGeoResources, style: YLText.titleMedium),
                      const SizedBox(height: 2),
                      Text(s.geoResourcesHint,
                          style: YLText.caption.copyWith(
                              color: isDark ? YLColors.zinc500 : YLColors.zinc400)),
                    ],
                  ),
                ),
                _updating
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: Icon(Icons.download_for_offline_outlined,
                            size: 18,
                            color: isDark ? YLColors.zinc400 : YLColors.zinc500),
                        tooltip: s.geoUpdateAll,
                        onPressed: _updateAll,
                      ),
              ],
            ),
          ),
          if (infos != null)
            for (final info in infos) ...[
              Divider(height: 1, thickness: 0.5, color: dividerColor),
              YLInfoRow(
                label: info.name,
                value: info.exists
                    ? '${info.sizeFormatted}  ·  '
                        '${info.modified?.toLocal().toString().substring(0, 16) ?? ""}'
                    : s.geoNotFound,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      info.exists ? Icons.check_circle_outline : Icons.error_outline,
                      size: 14,
                      color: info.exists ? YLColors.connected : YLColors.zinc400,
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: _updating
                          ? null
                          : () async {
                              setState(() => _updating = true);
                              await GeoResourceService.instance.update(info.name);
                              await _refresh();
                              if (mounted) setState(() => _updating = false);
                            },
                      child: Icon(Icons.refresh_rounded, size: 16,
                          color: isDark ? YLColors.zinc400 : YLColors.zinc500),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

// ── Split Tunnel Section (Android) ────────────────────────────────────────────

class _SplitTunnelSection extends ConsumerStatefulWidget {
  const _SplitTunnelSection();

  @override
  ConsumerState<_SplitTunnelSection> createState() =>
      _SplitTunnelSectionState();
}

class _SplitTunnelSectionState extends ConsumerState<_SplitTunnelSection> {
  List<Map<String, String>>? _apps;
  String _search = '';
  bool _loading = false;

  Future<void> _loadApps() async {
    setState(() => _loading = true);
    final apps = await VpnService.getInstalledApps(showSystem: false);
    if (mounted) setState(() { _apps = apps; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode = ref.watch(splitTunnelModeProvider);
    final selectedPkgs = ref.watch(splitTunnelAppsProvider);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return _SettingsCard(
      child: Column(
        children: [
          // Mode selector
          YLInfoRow(
            label: s.splitTunnelMode,
            trailing: DropdownButton<SplitTunnelMode>(
              value: mode,
              underline: const SizedBox.shrink(),
              style: YLText.body,
              items: [
                DropdownMenuItem(
                    value: SplitTunnelMode.all,
                    child: Text(s.splitTunnelModeAll)),
                DropdownMenuItem(
                    value: SplitTunnelMode.whitelist,
                    child: Text(s.splitTunnelModeWhitelist)),
                DropdownMenuItem(
                    value: SplitTunnelMode.blacklist,
                    child: Text(s.splitTunnelModeBlacklist)),
              ],
              onChanged: (v) {
                if (v != null) ref.read(splitTunnelModeProvider.notifier).set(v);
              },
            ),
          ),
          if (mode != SplitTunnelMode.all) ...[
            Divider(height: 1, thickness: 0.5, color: dividerColor),
            YLSettingsRow(
              title: s.splitTunnelApps,
              description: s.splitTunnelEffectHint,
              trailing: TextButton.icon(
                icon: const Icon(Icons.apps, size: 14),
                label: Text(s.splitTunnelManage),
                onPressed: () {
                  if (_apps == null) _loadApps();
                  _showAppPicker(context, selectedPkgs);
                },
              ),
            ),
            if (selectedPkgs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: selectedPkgs
                      .map((pkg) => Chip(
                            label: Text(pkg,
                                style: const TextStyle(fontSize: 11)),
                            deleteIcon:
                                const Icon(Icons.close, size: 14),
                            onDeleted: () => ref
                                .read(splitTunnelAppsProvider.notifier)
                                .remove(pkg),
                          ))
                      .toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _showAppPicker(BuildContext context, List<String> selected) {
    final s = S.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final apps = _apps ?? [];
          final filtered = _search.isEmpty
              ? apps
              : apps
                  .where((a) =>
                      (a['appName'] ?? '').toLowerCase().contains(_search) ||
                      (a['packageName'] ?? '').toLowerCase().contains(_search))
                  .toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            expand: false,
            builder: (_, sc) => Column(
              children: [
                const SizedBox(height: 8),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: s.splitTunnelSearchHint,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setModal(() => _search = v.toLowerCase()),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          controller: sc,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final app = filtered[i];
                            final pkg = app['packageName'] ?? '';
                            final isSelected = selected.contains(pkg);
                            return CheckboxListTile(
                              dense: true,
                              title: Text(app['appName'] ?? pkg),
                              subtitle: Text(pkg,
                                  style: const TextStyle(fontSize: 11)),
                              value: isSelected,
                              onChanged: (_) {
                                ref
                                    .read(splitTunnelAppsProvider.notifier)
                                    .toggle(pkg);
                                setModal(() {});
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A single settings row with a label on the left and a value or trailing widget on the right.
class YLInfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const YLInfoRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = enabled
        ? (isDark ? YLColors.zinc200 : YLColors.zinc700)
        : YLColors.zinc400;
    final valueColor = enabled
        ? (isDark ? YLColors.zinc400 : YLColors.zinc500)
        : YLColors.zinc300;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: YLText.body.copyWith(color: labelColor)),
          ),
          if (value != null)
            Text(value!, style: YLText.body.copyWith(color: valueColor)),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap != null && enabled) {
      return InkWell(onTap: onTap, child: content);
    }
    return Opacity(opacity: enabled ? 1.0 : 0.5, child: content);
  }
}

/// A settings row with a title, optional description, and a trailing widget.
class YLSettingsRow extends StatelessWidget {
  final String title;
  final String? description;
  final Widget trailing;

  const YLSettingsRow({
    super.key,
    required this.title,
    this.description,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? YLColors.zinc200 : YLColors.zinc700;
    final descColor = isDark ? YLColors.zinc500 : YLColors.zinc400;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: YLText.body.copyWith(color: titleColor)),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description!,
                      style: YLText.caption.copyWith(color: descColor)),
                ],
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
