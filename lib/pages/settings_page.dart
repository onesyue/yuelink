import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../providers/core_provider.dart';
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
    final isMock = ref.watch(isMockModeProvider);
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
                  title: const Text('HTTP 端口'),
                  trailing: Text('${AppConstants.defaultHttpPort}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ListTile(
                  title: const Text('SOCKS 端口'),
                  trailing: Text('${AppConstants.defaultSocksPort}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ListTile(
                  title: const Text('Mixed 端口'),
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
                if (isMock)
                  ListTile(
                    title: const Text('运行模式'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('模拟',
                          style: TextStyle(
                              fontSize: 12, color: Colors.amber.shade700)),
                    ),
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
