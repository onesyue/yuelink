import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/kernel/core_manager.dart';
import '../../../../core/providers/core_provider.dart';
import '../../../../core/tun/desktop_tun_diagnostics.dart';
import '../../../../core/tun/desktop_tun_state.dart';
import '../../../../core/tun/desktop_tun_telemetry.dart';
import '../../../../shared/widgets/setting_icon.dart';
import '../../../../shared/widgets/yl_list.dart';
import '../../../../theme.dart';

class DesktopTunLayeredStatus extends ConsumerStatefulWidget {
  const DesktopTunLayeredStatus({super.key});

  @override
  ConsumerState<DesktopTunLayeredStatus> createState() =>
      _DesktopTunLayeredStatusState();
}

class _DesktopTunLayeredStatusState
    extends ConsumerState<DesktopTunLayeredStatus> {
  bool _checking = false;

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final snapshot = await DesktopTunDiagnostics.instance.inspect(
        api: CoreManager.instance.api,
        mixedPort: CoreManager.instance.mixedPort,
        mode: ref.read(connectionModeProvider),
        tunStack: ref.read(desktopTunStackProvider),
      );
      ref.read(desktopTunHealthProvider.notifier).set(snapshot);
      DesktopTunTelemetry.healthSnapshot(snapshot);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(desktopTunHealthProvider);
    final mode = ref.watch(connectionModeProvider);
    final isTun = mode == 'tun';
    final rows = _rows(snapshot, isTun: isTun);
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
        for (final row in rows)
          YLListTile(
            leading: YLSettingIcon(icon: row.icon, color: row.color),
            title: row.title,
            subtitle: row.subtitle,
            trailing: YLListTrailing.badge(
              text: row.ok ? 'OK' : row.badge,
              color: row.ok ? YLColors.connected : row.color,
            ),
          ),
      ],
    );
  }

  List<_TunDiagRow> _rows(DesktopTunSnapshot? s, {required bool isTun}) {
    if (!isTun) {
      return const [
        _TunDiagRow(
          title: 'TUN 层',
          subtitle: '当前未使用 TUN，节点超时不会归因到 TUN',
          ok: true,
          badge: 'OFF',
          icon: Icons.power_settings_new_rounded,
          color: YLColors.zinc400,
        ),
      ];
    }
    if (s == null) {
      return const [
        _TunDiagRow(
          title: 'TUN 状态',
          subtitle: '尚未检测；点击重新检测',
          ok: false,
          badge: '待检测',
          icon: Icons.help_rounded,
          color: YLColors.connecting,
        ),
      ];
    }
    return [
      _TunDiagRow(
        title: 'App 层',
        subtitle: s.systemProxyEnabled
            ? 'TUN 与系统代理同时开启，可能造成控制面回环'
            : 'mode=${s.mode} · stack=${s.tunStack}',
        ok: !s.systemProxyEnabled,
        badge: '冲突',
        icon: Icons.desktop_windows_rounded,
        color: s.systemProxyEnabled ? YLColors.error : YLColors.connected,
      ),
      _TunDiagRow(
        title: 'Core 层',
        subtitle: s.controllerOk ? 'mihomo 控制接口可访问' : 'mihomo 已启动但控制接口不可用',
        ok: s.controllerOk,
        badge: '失败',
        icon: Icons.memory_rounded,
        color: s.controllerOk ? YLColors.connected : YLColors.error,
      ),
      _TunDiagRow(
        title: 'TUN 层',
        subtitle: _tunLayerSubtitle(s),
        ok: s.driverPresent && s.hasAdmin && s.interfacePresent,
        badge: '异常',
        icon: Icons.route_rounded,
        color: (s.driverPresent && s.hasAdmin && s.interfacePresent)
            ? YLColors.connected
            : YLColors.error,
      ),
      _TunDiagRow(
        title: 'Route / DNS',
        subtitle: s.routeOk
            ? (s.dnsOk ? '路由和 DNS 已验证' : 'DNS 未接管')
            : 'TUN 网卡已创建，但路由未接管',
        ok: s.routeOk && s.dnsOk,
        badge: '异常',
        icon: Icons.dns_rounded,
        color: (s.routeOk && s.dnsOk) ? YLColors.connected : YLColors.error,
      ),
      _TunDiagRow(
        title: '目标站层',
        subtitle:
            'Google ${s.googleOk ? "OK" : "失败"} · GitHub ${s.githubOk ? "OK" : "失败"}；Claude 403 会归因 AI 出口受限，不归因 TUN',
        ok: s.googleOk || s.githubOk,
        badge: '异常',
        icon: Icons.public_rounded,
        color: (s.googleOk || s.githubOk) ? YLColors.connected : YLColors.error,
      ),
    ];
  }

  String _tunLayerSubtitle(DesktopTunSnapshot s) {
    if (!s.driverPresent) return 'TUN 驱动/设备缺失';
    if (!s.hasAdmin) return '需要管理员权限或服务模式权限';
    if (!s.interfacePresent) return 'TUN interface 未创建';
    return 'TUN interface 已创建';
  }
}

class _TunDiagRow {
  const _TunDiagRow({
    required this.title,
    required this.subtitle,
    required this.ok,
    required this.badge,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final bool ok;
  final String badge;
  final IconData icon;
  final Color color;
}
