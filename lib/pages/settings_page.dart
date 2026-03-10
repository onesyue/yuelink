import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../providers/core_provider.dart';
import '../services/core_manager.dart';
import '../services/settings_service.dart';

// ------------------------------------------------------------------
// Settings providers
// ------------------------------------------------------------------

enum ProxyMode { tun, systemProxy }

final proxyModeProvider = StateProvider<ProxyMode>((ref) => ProxyMode.tun);
final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final autoConnectProvider = StateProvider<bool>((ref) => false);

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyMode = ref.watch(proxyModeProvider);
    final theme = ref.watch(themeProvider);
    final autoConnect = ref.watch(autoConnectProvider);
    final status = ref.watch(coreStatusProvider);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Proxy mode
          _SectionHeader(title: '代理模式'),
          Card(
            child: Column(
              children: [
                RadioListTile<ProxyMode>(
                  title: const Text('TUN 模式'),
                  subtitle: const Text('全局代理，需要 VPN 权限'),
                  value: ProxyMode.tun,
                  groupValue: proxyMode,
                  onChanged: (v) =>
                      ref.read(proxyModeProvider.notifier).state = v!,
                ),
                RadioListTile<ProxyMode>(
                  title: const Text('系统代理'),
                  subtitle: const Text('仅 HTTP/SOCKS 代理，无需额外权限'),
                  value: ProxyMode.systemProxy,
                  groupValue: proxyMode,
                  onChanged: (v) =>
                      ref.read(proxyModeProvider.notifier).state = v!,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // General
          _SectionHeader(title: '通用'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('开机自动连接'),
                  value: autoConnect,
                  onChanged: (v) {
                    ref.read(autoConnectProvider.notifier).state = v;
                    SettingsService.set('autoConnect', v);
                  },
                ),
                ListTile(
                  title: const Text('Mixed 端口'),
                  subtitle: const Text('HTTP/SOCKS 混合代理'),
                  trailing: Text('${AppConstants.defaultMixedPort}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ListTile(
                  title: const Text('API 端口'),
                  subtitle: const Text('external-controller'),
                  trailing: Text('${AppConstants.defaultApiPort}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Theme
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

          // Status info
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
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _modeColor(CoreManager.instance.mode)
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _modeName(CoreManager.instance.mode),
                      style: TextStyle(
                        fontSize: 12,
                        color: _modeColor(CoreManager.instance.mode),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tools
          _SectionHeader(title: '工具'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('DNS 查询'),
                  subtitle: const Text('查询域名解析结果'),
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
                  subtitle: const Text('查看当前生效的配置参数'),
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

          // About
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

  String _modeName(CoreMode mode) {
    switch (mode) {
      case CoreMode.mock:
        return '模拟';
      case CoreMode.ffi:
        return 'FFI';
      case CoreMode.subprocess:
        return '子进程';
    }
  }

  Color _modeColor(CoreMode mode) {
    switch (mode) {
      case CoreMode.mock:
        return Colors.amber.shade700;
      case CoreMode.ffi:
        return Colors.green;
      case CoreMode.subprocess:
        return Colors.blue;
    }
  }

  Future<void> _flushDns(BuildContext context) async {
    final ok = await CoreManager.instance.api.flushDnsCache();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'DNS 缓存已清除' : '操作失败')),
      );
    }
  }

  Future<void> _flushFakeIp(BuildContext context) async {
    final ok = await CoreManager.instance.api.flushFakeIpCache();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Fake-IP 缓存已清除' : '操作失败')),
      );
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _config == null
                  ? const Center(child: Text('无数据'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: _config!.entries.map((e) {
                        final value = e.value;
                        final display = value is Map || value is List
                            ? const JsonEncoder.withIndent('  ')
                                .convert(value)
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
                                    color: Theme.of(context).colorScheme.primary,
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
                                child: SelectableText(
                                  display,
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 12),
                                ),
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
            // Input row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: '输入域名，如 google.com',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onSubmitted: (_) => _query(),
                  ),
                ),
                const SizedBox(width: 8),
                // Record type dropdown
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

            // Error
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

            // Result
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
        // Status
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

        // Answers
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
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
                        SelectableText(
                          '${answer['data'] ?? ''}',
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13),
                        ),
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
