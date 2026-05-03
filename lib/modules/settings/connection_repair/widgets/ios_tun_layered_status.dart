import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/kernel/core_manager.dart';
import '../../../../core/providers/core_provider.dart';
import '../../../../shared/widgets/setting_icon.dart';
import '../../../../shared/widgets/yl_list.dart';
import '../../../../theme.dart';

/// iOS-specific layered diagnostic. NEPacketTunnelProvider is a system-
/// managed extension; driver / route / admin / interface layers don't
/// apply here. We show only what the in-app process can actually probe:
/// mihomo controller, DNS hijack, exit-site reachability.
class IosTunLayeredStatus extends ConsumerStatefulWidget {
  const IosTunLayeredStatus({super.key});

  @override
  ConsumerState<IosTunLayeredStatus> createState() =>
      _IosTunLayeredStatusState();
}

class _IosTunLayeredStatusState extends ConsumerState<IosTunLayeredStatus> {
  bool _checking = false;
  ({bool ok, String reason})? _controller;
  bool? _dnsOk;
  bool? _googleOk;
  bool? _githubOk;

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() => _checking = true);
    final api = CoreManager.instance.api;
    try {
      final results = await Future.wait<Object>([
        api.healthSnapshot(),
        _queryDnsOk(),
        _httpsReachable('https://www.gstatic.com/generate_204'),
        _httpsReachable('https://github.com/'),
      ]);
      if (!mounted) return;
      setState(() {
        _controller = results[0] as ({bool ok, String reason});
        _dnsOk = results[1] as bool;
        _googleOk = results[2] as bool;
        _githubOk = results[3] as bool;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<bool> _queryDnsOk() async {
    try {
      final api = CoreManager.instance.api;
      final dns = await api
          .queryDns('www.gstatic.com')
          .timeout(const Duration(seconds: 4));
      final answers = dns['Answer'];
      return answers is List && answers.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _httpsReachable(String url) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);
    client.findProxy = (_) => 'DIRECT';
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      await resp.drain<void>();
      return resp.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(connectionModeProvider);
    final isTun = mode == 'tun';
    final hasData =
        _controller != null ||
        _dnsOk != null ||
        _googleOk != null ||
        _githubOk != null;
    return Column(
      children: [
        YLListTile(
          leading: YLSettingIcon(
            icon: isTun ? Icons.hub_rounded : Icons.http_rounded,
            color: isTun ? YLColors.tunConnected : YLColors.zinc500,
          ),
          title: '当前模式',
          subtitle: isTun ? 'TUN · 分层诊断已启用' : '系统代理 · TUN 未开启',
          trailing: _checking
              ? YLListTrailing.loading()
              : YLListTrailing.value('重新检测'),
          onTap: _checking ? null : _refresh,
        ),
        if (!isTun)
          const YLListTile(
            leading: YLSettingIcon(
              icon: Icons.power_settings_new_rounded,
              color: YLColors.zinc400,
            ),
            title: 'TUN 层',
            subtitle: '当前未使用 TUN，节点超时不会归因到 TUN',
            trailing: null,
          )
        else if (!hasData)
          YLListTile(
            leading: const YLSettingIcon(
              icon: Icons.help_rounded,
              color: YLColors.connecting,
            ),
            title: 'TUN 状态',
            subtitle: '尚未检测；点击重新检测',
            trailing: YLListTrailing.badge(
              text: '待检测',
              color: YLColors.connecting,
            ),
          )
        else ...[
          YLListTile(
            leading: YLSettingIcon(
              icon: Icons.memory_rounded,
              color: (_controller?.ok ?? false)
                  ? YLColors.connected
                  : YLColors.error,
            ),
            title: 'Core 层',
            subtitle: (_controller?.ok ?? false)
                ? 'mihomo 控制接口可访问'
                : 'mihomo 控制接口不可用 (${_controller?.reason ?? "unknown"})',
            trailing: YLListTrailing.badge(
              text: (_controller?.ok ?? false) ? 'OK' : '失败',
              color: (_controller?.ok ?? false)
                  ? YLColors.connected
                  : YLColors.error,
            ),
          ),
          YLListTile(
            leading: YLSettingIcon(
              icon: Icons.dns_rounded,
              color: (_dnsOk ?? false) ? YLColors.connected : YLColors.error,
            ),
            title: 'DNS 层',
            subtitle: (_dnsOk ?? false) ? 'DNS 已通过 mihomo 接管' : 'DNS 未接管或解析失败',
            trailing: YLListTrailing.badge(
              text: (_dnsOk ?? false) ? 'OK' : '异常',
              color: (_dnsOk ?? false) ? YLColors.connected : YLColors.error,
            ),
          ),
          YLListTile(
            leading: YLSettingIcon(
              icon: Icons.public_rounded,
              color: ((_googleOk ?? false) || (_githubOk ?? false))
                  ? YLColors.connected
                  : YLColors.error,
            ),
            title: '目标站层',
            subtitle:
                'Google ${(_googleOk ?? false) ? "OK" : "失败"} · '
                'GitHub ${(_githubOk ?? false) ? "OK" : "失败"}；'
                'Claude 403 会归因 AI 出口受限，不归因 TUN',
            trailing: YLListTrailing.badge(
              text: ((_googleOk ?? false) || (_githubOk ?? false))
                  ? 'OK'
                  : '异常',
              color: ((_googleOk ?? false) || (_githubOk ?? false))
                  ? YLColors.connected
                  : YLColors.error,
            ),
          ),
        ],
      ],
    );
  }
}
