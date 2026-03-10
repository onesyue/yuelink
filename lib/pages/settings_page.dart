import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../providers/core_provider.dart';
import '../services/auto_update_service.dart';
import '../services/core_manager.dart';
import '../services/settings_service.dart';
import '../services/webdav_service.dart';
import 'overwrite_page.dart';
import 'unlock_test_page.dart';

// ------------------------------------------------------------------
// Settings providers
// ------------------------------------------------------------------

final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _launchAtStartup = false;
  int _autoUpdateInterval = 24;

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
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final autoConnect = ref.watch(autoConnectProvider);
    final connectionMode = ref.watch(connectionModeProvider);
    final logLevel = ref.watch(logLevelProvider);
    final systemProxyOnConnect = ref.watch(systemProxyOnConnectProvider);
    final status = ref.watch(coreStatusProvider);
    final isDesktop = Platform.isMacOS || Platform.isWindows;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 连接 ─────────────────────────────────────────────────
          _SectionHeader(title: '连接'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('接入方式'),
                  trailing: DropdownButton<String>(
                    value: connectionMode,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'tun', child: Text('TUN 模式')),
                      DropdownMenuItem(
                          value: 'systemProxy', child: Text('系统代理')),
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
                    title: const Text('连接时设置系统代理'),
                    subtitle: const Text('连接后自动配置 HTTP/SOCKS 系统代理'),
                    value: systemProxyOnConnect,
                    onChanged: (v) async {
                      ref.read(systemProxyOnConnectProvider.notifier).state = v;
                      await SettingsService.setSystemProxyOnConnect(v);
                    },
                  ),
                SwitchListTile(
                  title: const Text('启动时自动连接'),
                  value: autoConnect,
                  onChanged: (v) async {
                    ref.read(autoConnectProvider.notifier).state = v;
                    await SettingsService.setAutoConnect(v);
                  },
                ),
                if (isDesktop)
                  SwitchListTile(
                    title: const Text('开机自启动'),
                    subtitle: const Text('登录时自动启动 YueLink'),
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

          // ── 内核 ─────────────────────────────────────────────────
          _SectionHeader(title: '内核'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('日志级别'),
                  trailing: DropdownButton<String>(
                    value: logLevel,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'debug', child: Text('Debug')),
                      DropdownMenuItem(value: 'info', child: Text('Info')),
                      DropdownMenuItem(
                          value: 'warning', child: Text('Warning')),
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
                  title: const Text('配置覆写'),
                  subtitle: const Text('在订阅配置之上叠加自定义规则'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OverwritePage()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_open_outlined),
                  title: const Text('节点解锁检测'),
                  subtitle: const Text('检测流媒体与 AI 服务可用性'),
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

          // ── 订阅 ─────────────────────────────────────────────────
          _SectionHeader(title: '订阅'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('自动更新间隔'),
                  trailing: DropdownButton<int>(
                    value: _autoUpdateInterval,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('关闭')),
                      DropdownMenuItem(value: 6, child: Text('6 小时')),
                      DropdownMenuItem(value: 12, child: Text('12 小时')),
                      DropdownMenuItem(value: 24, child: Text('24 小时')),
                      DropdownMenuItem(value: 48, child: Text('48 小时')),
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
                  title: const Text('立即更新所有订阅'),
                  onTap: () => _updateAllProfiles(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── WebDAV ───────────────────────────────────────────────
          _SectionHeader(title: 'WebDAV 同步'),
          const _WebDavSection(),
          const SizedBox(height: 16),

          // ── 外观 ─────────────────────────────────────────────────
          _SectionHeader(title: '外观'),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('跟随系统'),
                  value: ThemeMode.system,
                  groupValue: theme,
                  onChanged: (v) {
                    ref.read(themeProvider.notifier).state = v!;
                    SettingsService.setThemeMode(v);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('浅色'),
                  value: ThemeMode.light,
                  groupValue: theme,
                  onChanged: (v) {
                    ref.read(themeProvider.notifier).state = v!;
                    SettingsService.setThemeMode(v);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('深色'),
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

          // ── 状态 ─────────────────────────────────────────────────
          _SectionHeader(title: '状态'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('内核状态'),
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
                        status == CoreStatus.running ? '运行中' : '已停止',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                ListTile(
                  title: const Text('运行模式'),
                  trailing: _ModeChip(mode: CoreManager.instance.mode),
                ),
                ListTile(
                  title: const Text('Mixed 端口'),
                  trailing: Text('${AppConstants.defaultMixedPort}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ListTile(
                  title: const Text('API 端口'),
                  trailing: Text('${AppConstants.defaultApiPort}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 工具 ─────────────────────────────────────────────────
          _SectionHeader(title: '工具'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('DNS 查询'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  enabled: status == CoreStatus.running,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const _DnsQueryPage()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_applications_outlined),
                  title: const Text('运行配置'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  enabled: status == CoreStatus.running,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const _RunningConfigPage()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('清除 DNS 缓存'),
                  enabled: status == CoreStatus.running,
                  onTap: () => _flushDns(context),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('清除 Fake-IP 缓存'),
                  enabled: status == CoreStatus.running,
                  onTap: () => _flushFakeIp(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 关于 ─────────────────────────────────────────────────
          _SectionHeader(title: '关于'),
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
                  title: const Text('版本'),
                  trailing: Text(AppConstants.appVersion,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ListTile(
                  title: const Text('内核'),
                  trailing: Text('mihomo (Clash.Meta)',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ListTile(
                  title: const Text('项目主页'),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () => _launchUrl('https://github.com/onesyue/yuelink'),
                ),
                ListTile(
                  title: const Text('开源许可'),
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
    final messenger = ScaffoldMessenger.of(context);
    messenger
        .showSnackBar(const SnackBar(content: Text('正在更新订阅...')));
    final result = await AutoUpdateService.instance.updateAll();
    if (context.mounted) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
          content: Text(
              '更新完成：成功 ${result.updated} 个，失败 ${result.failed} 个')));
    }
  }

  Future<void> _flushDns(BuildContext context) async {
    final ok = await CoreManager.instance.api.flushDnsCache();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(ok ? 'DNS 缓存已清除' : '操作失败')));
    }
  }

  Future<void> _flushFakeIp(BuildContext context) async {
    final ok = await CoreManager.instance.api.flushFakeIpCache();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Fake-IP 缓存已清除' : '操作失败')));
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ------------------------------------------------------------------
// WebDAV Section
// ------------------------------------------------------------------

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'WebDAV 地址',
                hintText: 'https://example.com/dav',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: '密码',
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
                    label: const Text('测试连接'),
                    onPressed: _loading ? null : _testConnection,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('上传'),
                    onPressed: _loading ? null : _upload,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('下载'),
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
    await _saveConfig();
    setState(() => _loading = true);
    try {
      final ok = await WebDavService.instance.testConnection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ok ? '连接成功' : '连接失败，请检查地址和凭据')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    await _saveConfig();
    setState(() => _loading = true);
    try {
      await WebDavService.instance.upload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('上传成功')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('上传失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    await _saveConfig();
    setState(() => _loading = true);
    try {
      await WebDavService.instance.download();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('下载成功，重启后生效')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ------------------------------------------------------------------
// Helper widgets
// ------------------------------------------------------------------

class _ModeChip extends StatelessWidget {
  final CoreMode mode;
  const _ModeChip({required this.mode});

  @override
  Widget build(BuildContext context) {
    final (name, color) = switch (mode) {
      CoreMode.mock => ('模拟', Colors.amber.shade700),
      CoreMode.ffi => ('FFI', Colors.green),
      CoreMode.subprocess => ('子进程', Colors.blue),
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

// ==================================================================
// Running Config Page
// ==================================================================

class _RunningConfigPage extends StatefulWidget {
  const _RunningConfigPage();

  @override
  State<_RunningConfigPage> createState() => _RunningConfigPageState();
}

class _RunningConfigPageState extends State<_RunningConfigPage> {
  Map<String, dynamic>? _config;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await CoreManager.instance.api.getConfig();
      if (mounted) setState(() => _config = config);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行配置'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red)))
              : _config == null
                  ? const Center(child: Text('无数据'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: _config!.entries.map((e) {
                        final value = e.value;
                        final display = value is Map || value is List
                            ? const JsonEncoder.withIndent('  ').convert(value)
                            : '$value';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.key,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  )),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: SelectableText(display,
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 12)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
    );
  }
}

// ==================================================================
// DNS Query Page
// ==================================================================

class _DnsQueryPage extends StatefulWidget {
  const _DnsQueryPage();

  @override
  State<_DnsQueryPage> createState() => _DnsQueryPageState();
}

class _DnsQueryPageState extends State<_DnsQueryPage> {
  final _controller = TextEditingController();
  String _queryType = 'A';
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  static const _queryTypes = ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS', 'SOA'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _query() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result =
          await CoreManager.instance.api.queryDns(name, type: _queryType);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DNS 查询')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: '输入域名，如 google.com',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onSubmitted: (_) => _query(),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _queryType,
                  items: _queryTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _queryType = v);
                  },
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _query,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('查询'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            if (_result != null)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildResult(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final status = _result!['Status'] as int? ?? -1;
    final answers = _result!['Answer'] as List? ?? [];

    return ListView(
      children: [
        Row(
          children: [
            Icon(
              status == 0 ? Icons.check_circle : Icons.error,
              size: 18,
              color: status == 0 ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(
              status == 0 ? 'NOERROR' : 'Status: $status',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: status == 0 ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        if (answers.isEmpty)
          const Text('无记录', style: TextStyle(color: Colors.grey))
        else
          ...answers.map((a) {
            final answer = a as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${answer['type'] ?? _queryType}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText('${answer['data'] ?? ''}',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13)),
                        if (answer['TTL'] != null)
                          Text('TTL: ${answer['TTL']}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
