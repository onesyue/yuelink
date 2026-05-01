import 'desktop_tun_state.dart';

enum DesktopTunRepairLevel { level0, level1, level2, level3, level4 }

class DesktopTunRepairPlan {
  const DesktopTunRepairPlan({
    required this.level,
    required this.action,
    required this.userMessage,
    required this.canRunAutomatically,
  });

  final DesktopTunRepairLevel level;
  final String action;
  final String userMessage;
  final bool canRunAutomatically;
}

/// Policy + throttling for desktop TUN repair.
///
/// This class intentionally decides *what* to do, not how platform routes/DNS
/// are mutated. Callers execute the action through existing lifecycle and
/// platform managers, which keeps unit tests deterministic and prevents repair
/// loops from being hidden inside UI code.
class DesktopTunRepairService {
  DesktopTunRepairService({
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  }) : _now = now ?? DateTime.now,
       _sleep = sleep ?? Future.delayed;

  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  DateTime? _lastLevel2At;
  DateTime? _lastLevel3At;
  bool _repairInFlight = false;

  bool get repairInFlight => _repairInFlight;

  DesktopTunRepairPlan plan(DesktopTunSnapshot snapshot) {
    switch (snapshot.errorClass) {
      case 'ok':
        return const DesktopTunRepairPlan(
          level: DesktopTunRepairLevel.level0,
          action: 'refresh_state',
          userMessage: 'TUN 状态正常',
          canRunAutomatically: true,
        );
      case 'route_not_applied':
        return const DesktopTunRepairPlan(
          level: DesktopTunRepairLevel.level1,
          action: 'reapply_route',
          userMessage: '重新检查并应用 TUN 路由',
          canRunAutomatically: true,
        );
      case 'dns_hijack_failed':
      case 'system_proxy_conflict':
        return const DesktopTunRepairPlan(
          level: DesktopTunRepairLevel.level1,
          action: 'reapply_dns',
          userMessage: '重新应用 DNS / 清理系统代理',
          canRunAutomatically: true,
        );
      case 'controller_failed':
      case 'tun_interface_missing':
      case 'node_timeout':
        return const DesktopTunRepairPlan(
          level: DesktopTunRepairLevel.level2,
          action: 'restart_core',
          userMessage: '重启 mihomo 并重新验证 TUN',
          canRunAutomatically: true,
        );
      case 'cleanup_failed':
        return const DesktopTunRepairPlan(
          level: DesktopTunRepairLevel.level3,
          action: 'cleanup_and_restart',
          userMessage: '清理 YueLink 自己的路由/DNS 状态后重启',
          canRunAutomatically: true,
        );
      case 'missing_driver':
      case 'missing_permission':
        return DesktopTunRepairPlan(
          level: DesktopTunRepairLevel.level4,
          action: snapshot.repairAction,
          userMessage: snapshot.userMessage,
          canRunAutomatically: false,
        );
      default:
        return const DesktopTunRepairPlan(
          level: DesktopTunRepairLevel.level0,
          action: 'refresh_state',
          userMessage: '刷新 TUN 状态',
          canRunAutomatically: true,
        );
    }
  }

  Future<T?> runThrottled<T>(
    DesktopTunRepairPlan plan,
    Future<T> Function() action,
  ) async {
    if (_repairInFlight) return null;
    if (!_canRun(plan.level)) return null;
    _repairInFlight = true;
    try {
      _markRun(plan.level);
      return await action();
    } finally {
      // Give OS route/DNS watchers a small settle window before the next
      // automatic repair can run. Manual repair buttons can still call their
      // own lifecycle actions explicitly.
      await _sleep(const Duration(milliseconds: 250));
      _repairInFlight = false;
    }
  }

  bool _canRun(DesktopTunRepairLevel level) {
    final now = _now();
    if (level == DesktopTunRepairLevel.level2 && _lastLevel2At != null) {
      return now.difference(_lastLevel2At!) >= const Duration(seconds: 30);
    }
    if (level == DesktopTunRepairLevel.level3 && _lastLevel3At != null) {
      return now.difference(_lastLevel3At!) >= const Duration(hours: 1);
    }
    return true;
  }

  void _markRun(DesktopTunRepairLevel level) {
    final now = _now();
    if (level == DesktopTunRepairLevel.level2) _lastLevel2At = now;
    if (level == DesktopTunRepairLevel.level3) _lastLevel3At = now;
  }
}
