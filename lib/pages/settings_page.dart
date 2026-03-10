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
import '../providers/node_filter_provider.dart';
import '../services/node_filter_service.dart';
import '../services/update_checker.dart';
import 'overwrite_page.dart';
import 'settings/dns_query_page.dart';
import 'settings/running_config_page.dart';
import 'unlock_test_page.dart';

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
    final guardMode = ref.watch(guardModeProvider);
    final status = ref.watch(coreStatusProvider);
    final isDesktop = Platform.isMacOS || Platform.isWindows;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 连接 ──────────────────────────────────────────────────
          _SectionHeader(title: s.sectionConnection),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(s.connectionMode),
                  trailing: DropdownButton<String>(
                    value: connectionMode,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: 'tun', child: Text(s.modeTun)),
                      DropdownMenuItem(
                          value: 'systemProxy', child: Text(s.modeSystemProxy)),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      ref.read(connectionModeProvider.notifier).state = v;
                      await SettingsService.setConnectionMode(v);
                    },
                  ),
                ),
                if (isDesktop)
                  SwitchListTile(
                    title: Text(s.setSystemProxyOnConnect),
                    subtitle: Text(s.setSystemProxyOnConnectSub),
                    value: systemProxyOnConnect,
                    onChanged: (v) async {
                      ref.read(systemProxyOnConnectProvider.notifier).state = v;
                      await SettingsService.setSystemProxyOnConnect(v);
                    },
                  ),
                if (isDesktop && systemProxyOnConnect)
                  SwitchListTile(
                    title: Text(s.guardModeLabel),
                    subtitle: Text(s.guardModeSub),
                    value: guardMode,
                    onChanged: (v) async {
                      ref.read(guardModeProvider.notifier).state = v;
                      await SettingsService.setGuardMode(v);
                    },
                  ),
                SwitchListTile(
                  title: Text(s.autoConnect),
                  value: autoConnect,
                  onChanged: (v) async {
                    ref.read(autoConnectProvider.notifier).state = v;
                    await SettingsService.setAutoConnect(v);
                  },
                ),
                if (isDesktop)
                  SwitchListTile(
                    title: Text(s.launchAtStartupLabel),
                    subtitle: Text(s.launchAtStartupSub),
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
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 内核 ──────────────────────────────────────────────────
          _SectionHeader(title: s.sectionCore),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(s.logLevelSetting),
                  trailing: DropdownButton<String>(
                    value: logLevel,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'debug', child: Text('Debug')),
                      DropdownMenuItem(value: 'info', child: Text('Info')),
                      DropdownMenuItem(value: 'warning', child: Text('Warning')),
                      DropdownMenuItem(value: 'error', child: Text('Error')),
                      DropdownMenuItem(value: 'silent', child: Text('Silent')),
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
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: Text(s.configOverwrite),
                  subtitle: Text(s.configOverwriteSub),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OverwritePage()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_open_outlined),
                  title: Text(s.unlockTestLabel),
                  subtitle: Text(s.unlockTestSub),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  enabled: status == CoreStatus.running,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UnlockTestPage()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 订阅 ──────────────────────────────────────────────────
          _SectionHeader(title: s.sectionSubscription),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(s.autoUpdateInterval),
                  trailing: DropdownButton<int>(
                    value: _autoUpdateInterval,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: 0, child: Text(s.disabled)),
                      DropdownMenuItem(value: 6, child: Text(s.hours6)),
                      DropdownMenuItem(value: 12, child: Text(s.hours12)),
                      DropdownMenuItem(value: 24, child: Text(s.hours24)),
                      DropdownMenuItem(value: 48, child: Text(s.hours48)),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _autoUpdateInterval = v);
                      await SettingsService.setAutoUpdateInterval(v);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.refresh_outlined),
                  title: Text(s.updateAllNow),
                  onTap: () => _updateAllProfiles(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Sub-Store ─────────────────────────────────────────────
          _SectionHeader(title: s.sectionSubStore),
          const _SubStoreSection(),
          const SizedBox(height: 16),

          // ── WebDAV ────────────────────────────────────────────────
          _SectionHeader(title: s.sectionWebDav),
          const _WebDavSection(),
          const SizedBox(height: 16),

          // ── 外观 ──────────────────────────────────────────────────
          _SectionHeader(title: s.sectionAppearance),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text(s.themeSystem),
                  value: ThemeMode.system,
                  groupValue: theme,
                  onChanged: (v) {
                    ref.read(themeProvider.notifier).state = v!;
                    SettingsService.setThemeMode(v);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: Text(s.themeLight),
                  value: ThemeMode.light,
                  groupValue: theme,
                  onChanged: (v) {
                    ref.read(themeProvider.notifier).state = v!;
                    SettingsService.setThemeMode(v);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: Text(s.themeDark),
                  value: ThemeMode.dark,
                  groupValue: theme,
                  onChanged: (v) {
                    ref.read(themeProvider.notifier).state = v!;
                    SettingsService.setThemeMode(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 语言 ──────────────────────────────────────────────────
          _SectionHeader(title: s.sectionLanguage),
          Card(
            child: Column(
              children: [
                RadioListTile<String>(
                  title: Text(s.languageChinese),
                  value: 'zh',
                  groupValue: language,
                  onChanged: (v) async {
                    if (v == null) return;
                    ref.read(languageProvider.notifier).state = v;
                    await SettingsService.setLanguage(v);
                  },
                ),
                RadioListTile<String>(
                  title: Text(s.languageEnglish),
                  value: 'en',
                  groupValue: language,
                  onChanged: (v) async {
                    if (v == null) return;
                    ref.read(languageProvider.notifier).state = v;
                    await SettingsService.setLanguage(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 状态 ──────────────────────────────────────────────────
          _SectionHeader(title: s.sectionStatus),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(s.coreStatus),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: status == CoreStatus.running
                              ? Colors.green
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status == CoreStatus.running
                            ? s.coreRunning
                            : s.coreStopped,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                ListTile(
                  title: Text(s.runMode),
                  trailing: _ModeChip(mode: CoreManager.instance.mode),
                ),
                ListTile(
                  title: Text(s.mixedPort),
                  trailing: Text('${AppConstants.defaultMixedPort}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ListTile(
                  title: Text(s.apiPort),
                  trailing: Text('${AppConstants.defaultApiPort}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 工具 ──────────────────────────────────────────────────
          _SectionHeader(title: s.sectionTools),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(s.dnsQuery),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  enabled: status == CoreStatus.running,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DnsQueryPage()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_applications_outlined),
                  title: Text(s.runningConfig),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  enabled: status == CoreStatus.running,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RunningConfigPage()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: Text(s.flushDnsCache),
                  enabled: status == CoreStatus.running,
                  onTap: () => _flushDns(context),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: Text(s.flushFakeIpCache),
                  enabled: status == CoreStatus.running,
                  onTap: () => _flushFakeIp(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 节点筛选 ──────────────────────────────────────────────
          _SectionHeader(title: s.sectionNodeFilterNew),
          const _NodeFilterSection(),
          const SizedBox(height: 16),

          // ── Geo 资源 ──────────────────────────────────────────────
          _SectionHeader(title: s.sectionGeoResources),
          const _GeoResourceSection(),
          const SizedBox(height: 16),

          // ── 分应用代理 (Android only) ──────────────────────────────
          if (Platform.isAndroid) ...[
            _SectionHeader(title: s.sectionSplitTunnel),
            const _SplitTunnelSection(),
            const SizedBox(height: 16),
          ],

          // ── 全局热键 (桌面 only) ──────────────────────────────────
          if (isDesktop) ...[
            _SectionHeader(title: s.sectionHotkeys),
            Card(
              child: ListTile(
                leading: const Icon(Icons.keyboard_alt_outlined),
                title: Text(s.hotkeyToggle),
                subtitle: Text(s.hotkeyHint),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── 关于 ──────────────────────────────────────────────────
          _SectionHeader(title: s.sectionAbout),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text(AppConstants.appName),
                  subtitle: const Text('by ${AppConstants.appBrand}'),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.link_rounded,
                        size: 22,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                ListTile(
                  title: Text(s.versionLabel),
                  trailing: Text(AppConstants.appVersion,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ListTile(
                  title: Text(s.coreLabel),
                  trailing: Text('mihomo (Clash.Meta)',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ListTile(
                  title: Text(s.projectHome),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () =>
                      _launchUrl('https://github.com/onesyue/yuelink'),
                ),
                ListTile(
                  leading: _checkingUpdate
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _pendingUpdate != null
                              ? Icons.new_releases_outlined
                              : Icons.system_update_alt_outlined,
                          color: _pendingUpdate != null
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          size: 22,
                        ),
                  title: Text(s.checkUpdate),
                  subtitle: _pendingUpdate != null
                      ? Text(
                          s.updateAvailableV(_pendingUpdate!.latestVersion),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500),
                        )
                      : null,
                  trailing: _pendingUpdate != null
                      ? FilledButton.tonal(
                          onPressed: () async {
                            final uri = Uri.parse(_pendingUpdate!.releaseUrl);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Text(s.updateDownload),
                        )
                      : null,
                  onTap: _pendingUpdate == null && !_checkingUpdate
                      ? () async {
                          setState(() => _checkingUpdate = true);
                          final info = await UpdateChecker.instance.check();
                          if (mounted) {
                            setState(() {
                              _pendingUpdate = info;
                              _checkingUpdate = false;
                            });
                            if (info == null) {
                              AppNotifier.info(s.alreadyLatest);
                            }
                          }
                        }
                      : null,
                ),
                ListTile(
                  title: Text(s.openSourceLicense),
                  trailing: const Icon(Icons.chevron_right, size: 20),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.subStoreUrlSub,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                labelText: s.subStoreUrlLabel,
                hintText: s.subStoreUrlHint,
                border: const OutlineInputBorder(),
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
    return Card(
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
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userCtrl,
              decoration: InputDecoration(
                labelText: s.username,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: s.password,
                border: const OutlineInputBorder(),
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
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(s.testConnection),
                    onPressed: _loading ? null : _testConnection,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text(s.upload),
                    onPressed: _loading ? null : _upload,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
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
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(name, style: TextStyle(fontSize: 12, color: color)),
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
    final infos = _infos;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.public),
            title: Text(s.sectionGeoResources),
            subtitle: Text(s.geoResourcesHint),
            trailing: _updating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: const Icon(Icons.download_for_offline_outlined),
                    tooltip: s.geoUpdateAll,
                    onPressed: _updateAll,
                  ),
          ),
          if (infos != null)
            for (final info in infos)
              ListTile(
                dense: true,
                leading: Icon(
                  info.exists ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18,
                  color: info.exists ? Colors.green : Colors.grey,
                ),
                title: Text(info.name,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                subtitle: info.exists
                    ? Text('${info.sizeFormatted}  •  '
                        '${info.modified?.toLocal().toString().substring(0, 16) ?? ""}')
                    : Text(s.geoNotFound,
                        style: const TextStyle(color: Colors.grey)),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _updating
                      ? null
                      : () async {
                          setState(() => _updating = true);
                          await GeoResourceService.instance.update(info.name);
                          await _refresh();
                          if (mounted) setState(() => _updating = false);
                        },
                ),
              ),
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
    final mode = ref.watch(splitTunnelModeProvider);
    final selectedPkgs = ref.watch(splitTunnelAppsProvider);

    return Card(
      child: Column(
        children: [
          // Mode selector
          ListTile(
            title: Text(s.splitTunnelMode),
            trailing: DropdownButton<SplitTunnelMode>(
              value: mode,
              underline: const SizedBox.shrink(),
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
            ListTile(
              title: Text(s.splitTunnelApps),
              subtitle: Text(s.splitTunnelEffectHint),
              trailing: TextButton.icon(
                icon: const Icon(Icons.apps, size: 16),
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

// ── Node Filter Section ───────────────────────────────────────────────────────

class _NodeFilterSection extends ConsumerStatefulWidget {
  const _NodeFilterSection();

  @override
  ConsumerState<_NodeFilterSection> createState() => _NodeFilterSectionState();
}

class _NodeFilterSectionState extends ConsumerState<_NodeFilterSection> {
  void _showAddDialog() {
    final s = S.of(context);
    final patternCtrl = TextEditingController();
    final renameCtrl = TextEditingController();
    var action = NodeFilterAction.keep;
    String? patternError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(s.nodeFilterAddRule),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Action dropdown
              DropdownButtonFormField<NodeFilterAction>(
                value: action,
                decoration: InputDecoration(
                    labelText: s.nodeFilterAction,
                    border: const OutlineInputBorder(),
                    isDense: true),
                items: [
                  DropdownMenuItem(
                      value: NodeFilterAction.keep,
                      child: Text(s.nodeFilterActionKeep)),
                  DropdownMenuItem(
                      value: NodeFilterAction.exclude,
                      child: Text(s.nodeFilterActionExclude)),
                  DropdownMenuItem(
                      value: NodeFilterAction.rename,
                      child: Text(s.nodeFilterActionRename)),
                ],
                onChanged: (v) {
                  if (v != null) setDialog(() => action = v);
                },
              ),
              const SizedBox(height: 12),
              // Pattern input
              TextField(
                controller: patternCtrl,
                decoration: InputDecoration(
                  labelText: s.nodeFilterPattern,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: patternError,
                ),
                onChanged: (_) {
                  final p = patternCtrl.text.trim();
                  String? err;
                  if (p.isNotEmpty) {
                    try {
                      RegExp(p);
                    } catch (_) {
                      err = s.nodeFilterInvalidRegex;
                    }
                  }
                  setDialog(() => patternError = err);
                },
              ),
              // Rename target (only for rename action)
              if (action == NodeFilterAction.rename) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: renameCtrl,
                  decoration: InputDecoration(
                    labelText: s.nodeFilterRenameTo,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            FilledButton(
              onPressed: patternError != null
                  ? null
                  : () async {
                      final pattern = patternCtrl.text.trim();
                      if (pattern.isEmpty) return;
                      await ref.read(nodeFilterRulesProvider.notifier).add(
                            NodeFilterRule(
                              action: action,
                              pattern: pattern,
                              renameTo: action == NodeFilterAction.rename
                                  ? renameCtrl.text.trim()
                                  : null,
                            ),
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                      AppNotifier.success(s.nodeFilterRuleAdded);
                    },
              child: Text(s.confirm),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      patternCtrl.dispose();
      renameCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rulesAsync = ref.watch(nodeFilterRulesProvider);

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.filter_alt_outlined),
            title: Text(s.sectionNodeFilterNew),
            subtitle: Text(s.nodeFilterEmpty,
                style: Theme.of(context).textTheme.bodySmall),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              tooltip: s.nodeFilterAddRule,
              onPressed: _showAddDialog,
            ),
          ),
          rulesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (rules) {
              if (rules.isEmpty) return const SizedBox.shrink();
              return ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rules.length,
                onReorder: (o, n) => ref
                    .read(nodeFilterRulesProvider.notifier)
                    .reorder(o, n),
                itemBuilder: (ctx, i) {
                  final rule = rules[i];
                  final actionLabel = switch (rule.action) {
                    NodeFilterAction.keep => s.nodeFilterActionKeep,
                    NodeFilterAction.exclude => s.nodeFilterActionExclude,
                    NodeFilterAction.rename => s.nodeFilterActionRename,
                  };
                  final actionColor = switch (rule.action) {
                    NodeFilterAction.keep => Colors.green,
                    NodeFilterAction.exclude => Colors.red,
                    NodeFilterAction.rename => Colors.blue,
                  };
                  return ListTile(
                    key: ValueKey(i),
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: actionColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(actionLabel,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: actionColor)),
                    ),
                    title: Text(rule.pattern,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                    subtitle: rule.renameTo != null
                        ? Text('→ ${rule.renameTo}',
                            style: const TextStyle(fontSize: 11))
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => ref
                          .read(nodeFilterRulesProvider.notifier)
                          .remove(i),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}
