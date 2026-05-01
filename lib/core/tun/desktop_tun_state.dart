import 'package:flutter/foundation.dart';

/// Desktop TUN lifecycle stages. The enum names stay Dart-friendly while
/// [wireName] is the closed telemetry/UI contract.
enum DesktopTunState {
  off,
  checkingPrerequisites,
  missingDriver,
  missingPermission,
  installingDriver,
  startingCore,
  waitingController,
  applyingTunConfig,
  verifyingInterface,
  verifyingRoute,
  verifyingDns,
  verifyingConnectivity,
  running,
  degraded,
  repairing,
  stopping,
  cleanupFailed,
  failed,
}

extension DesktopTunStateWire on DesktopTunState {
  String get wireName => switch (this) {
    DesktopTunState.off => 'off',
    DesktopTunState.checkingPrerequisites => 'checking_prerequisites',
    DesktopTunState.missingDriver => 'missing_driver',
    DesktopTunState.missingPermission => 'missing_permission',
    DesktopTunState.installingDriver => 'installing_driver',
    DesktopTunState.startingCore => 'starting_core',
    DesktopTunState.waitingController => 'waiting_controller',
    DesktopTunState.applyingTunConfig => 'applying_tun_config',
    DesktopTunState.verifyingInterface => 'verifying_interface',
    DesktopTunState.verifyingRoute => 'verifying_route',
    DesktopTunState.verifyingDns => 'verifying_dns',
    DesktopTunState.verifyingConnectivity => 'verifying_connectivity',
    DesktopTunState.running => 'running',
    DesktopTunState.degraded => 'degraded',
    DesktopTunState.repairing => 'repairing',
    DesktopTunState.stopping => 'stopping',
    DesktopTunState.cleanupFailed => 'cleanup_failed',
    DesktopTunState.failed => 'failed',
  };
}

@immutable
class DesktopTunSnapshot {
  const DesktopTunSnapshot({
    required this.state,
    required this.platform,
    required this.mode,
    required this.tunStack,
    required this.hasAdmin,
    required this.driverPresent,
    required this.interfacePresent,
    required this.routeOk,
    required this.dnsOk,
    required this.ipv6Enabled,
    required this.controllerOk,
    required this.systemProxyEnabled,
    required this.proxyGuardActive,
    required this.transportOk,
    required this.googleOk,
    required this.githubOk,
    required this.errorClass,
    required this.userMessage,
    required this.repairAction,
    this.coreVersion,
    this.elapsedMs = 0,
    this.sampleRate = 1.0,
    this.detail,
  });

  factory DesktopTunSnapshot.off({
    String platform = 'unknown',
    String mode = 'system_proxy',
    String tunStack = 'mixed',
  }) {
    return DesktopTunSnapshot(
      state: DesktopTunState.off,
      platform: platform,
      mode: mode,
      tunStack: tunStack,
      hasAdmin: false,
      driverPresent: false,
      interfacePresent: false,
      routeOk: false,
      dnsOk: false,
      ipv6Enabled: false,
      controllerOk: false,
      systemProxyEnabled: false,
      proxyGuardActive: false,
      transportOk: false,
      googleOk: false,
      githubOk: false,
      errorClass: 'off',
      userMessage: 'TUN 未开启',
      repairAction: 'none',
    );
  }

  final DesktopTunState state;
  final String platform;
  final String mode;
  final String tunStack;
  final bool hasAdmin;
  final bool driverPresent;
  final bool interfacePresent;
  final bool routeOk;
  final bool dnsOk;
  final bool ipv6Enabled;
  final bool controllerOk;
  final bool systemProxyEnabled;
  final bool proxyGuardActive;
  final bool transportOk;
  final bool googleOk;
  final bool githubOk;
  final String errorClass;
  final String userMessage;
  final String repairAction;
  final String? coreVersion;
  final int elapsedMs;
  final double sampleRate;
  final String? detail;

  bool get runningVerified => state == DesktopTunState.running;
  bool get needsRepair =>
      state == DesktopTunState.degraded ||
      state == DesktopTunState.cleanupFailed ||
      state == DesktopTunState.failed;

  DesktopTunSnapshot copyWith({
    DesktopTunState? state,
    String? platform,
    String? mode,
    String? tunStack,
    bool? hasAdmin,
    bool? driverPresent,
    bool? interfacePresent,
    bool? routeOk,
    bool? dnsOk,
    bool? ipv6Enabled,
    bool? controllerOk,
    bool? systemProxyEnabled,
    bool? proxyGuardActive,
    bool? transportOk,
    bool? googleOk,
    bool? githubOk,
    String? errorClass,
    String? userMessage,
    String? repairAction,
    String? coreVersion,
    int? elapsedMs,
    double? sampleRate,
    String? detail,
  }) {
    return DesktopTunSnapshot(
      state: state ?? this.state,
      platform: platform ?? this.platform,
      mode: mode ?? this.mode,
      tunStack: tunStack ?? this.tunStack,
      hasAdmin: hasAdmin ?? this.hasAdmin,
      driverPresent: driverPresent ?? this.driverPresent,
      interfacePresent: interfacePresent ?? this.interfacePresent,
      routeOk: routeOk ?? this.routeOk,
      dnsOk: dnsOk ?? this.dnsOk,
      ipv6Enabled: ipv6Enabled ?? this.ipv6Enabled,
      controllerOk: controllerOk ?? this.controllerOk,
      systemProxyEnabled: systemProxyEnabled ?? this.systemProxyEnabled,
      proxyGuardActive: proxyGuardActive ?? this.proxyGuardActive,
      transportOk: transportOk ?? this.transportOk,
      googleOk: googleOk ?? this.googleOk,
      githubOk: githubOk ?? this.githubOk,
      errorClass: errorClass ?? this.errorClass,
      userMessage: userMessage ?? this.userMessage,
      repairAction: repairAction ?? this.repairAction,
      coreVersion: coreVersion ?? this.coreVersion,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      sampleRate: sampleRate ?? this.sampleRate,
      detail: detail ?? this.detail,
    );
  }

  Map<String, dynamic> toTelemetryProps({
    String? repairActionOverride,
    int? elapsedMsOverride,
  }) {
    return {
      'platform': platform,
      'core_version': ?coreVersion,
      'tun_stack': tunStack,
      'mode': mode,
      'state': state.wireName,
      'has_admin': hasAdmin,
      'driver_present': driverPresent,
      'interface_present': interfacePresent,
      'route_ok': routeOk,
      'dns_ok': dnsOk,
      'ipv6_enabled': ipv6Enabled,
      'controller_ok': controllerOk,
      'system_proxy_enabled': systemProxyEnabled,
      'proxy_guard_active': proxyGuardActive,
      'transport_ok': transportOk,
      'google_ok': googleOk,
      'github_ok': githubOk,
      'error_class': errorClass,
      'elapsed_ms': elapsedMsOverride ?? elapsedMs,
      'repair_action': repairActionOverride ?? repairAction,
      'sample_rate': sampleRate.clamp(0.0, 1.0),
    };
  }
}

class DesktopTunStateMachine {
  const DesktopTunStateMachine._();

  static DesktopTunSnapshot evaluate({
    required String platform,
    required String mode,
    required String tunStack,
    required bool hasAdmin,
    required bool driverPresent,
    required bool interfacePresent,
    required bool routeOk,
    required bool dnsOk,
    required bool ipv6Enabled,
    required bool controllerOk,
    required bool systemProxyEnabled,
    required bool proxyGuardActive,
    required bool transportOk,
    required bool googleOk,
    required bool githubOk,
    String? coreVersion,
    int elapsedMs = 0,
    double sampleRate = 1.0,
    String? detail,
  }) {
    final classification = classify(
      hasAdmin: hasAdmin,
      driverPresent: driverPresent,
      interfacePresent: interfacePresent,
      routeOk: routeOk,
      dnsOk: dnsOk,
      controllerOk: controllerOk,
      systemProxyEnabled: systemProxyEnabled,
      transportOk: transportOk,
      googleOk: googleOk,
      githubOk: githubOk,
    );
    return DesktopTunSnapshot(
      state: classification.state,
      platform: platform,
      mode: mode,
      tunStack: tunStack,
      hasAdmin: hasAdmin,
      driverPresent: driverPresent,
      interfacePresent: interfacePresent,
      routeOk: routeOk,
      dnsOk: dnsOk,
      ipv6Enabled: ipv6Enabled,
      controllerOk: controllerOk,
      systemProxyEnabled: systemProxyEnabled,
      proxyGuardActive: proxyGuardActive,
      transportOk: transportOk,
      googleOk: googleOk,
      githubOk: githubOk,
      errorClass: classification.errorClass,
      userMessage: classification.userMessage,
      repairAction: classification.repairAction,
      coreVersion: coreVersion,
      elapsedMs: elapsedMs,
      sampleRate: sampleRate,
      detail: detail,
    );
  }

  static ({
    DesktopTunState state,
    String errorClass,
    String userMessage,
    String repairAction,
  })
  classify({
    required bool hasAdmin,
    required bool driverPresent,
    required bool interfacePresent,
    required bool routeOk,
    required bool dnsOk,
    required bool controllerOk,
    required bool systemProxyEnabled,
    required bool transportOk,
    required bool googleOk,
    required bool githubOk,
  }) {
    if (!driverPresent) {
      return (
        state: DesktopTunState.missingDriver,
        errorClass: 'missing_driver',
        userMessage: 'TUN 驱动或设备缺失',
        repairAction: 'user_install_driver',
      );
    }
    if (!hasAdmin) {
      return (
        state: DesktopTunState.missingPermission,
        errorClass: 'missing_permission',
        userMessage: '需要管理员权限',
        repairAction: 'user_grant_permission',
      );
    }
    if (!controllerOk) {
      return (
        state: DesktopTunState.failed,
        errorClass: 'controller_failed',
        userMessage: 'mihomo 已启动，但控制接口不可用',
        repairAction: 'restart_core',
      );
    }
    if (!interfacePresent) {
      return (
        state: DesktopTunState.degraded,
        errorClass: 'tun_interface_missing',
        userMessage: 'TUN 网卡未创建',
        repairAction: 'restart_core',
      );
    }
    if (!routeOk) {
      return (
        state: DesktopTunState.degraded,
        errorClass: 'route_not_applied',
        userMessage: 'TUN 网卡已创建，但路由未接管',
        repairAction: 'reapply_route',
      );
    }
    if (!dnsOk) {
      return (
        state: DesktopTunState.degraded,
        errorClass: 'dns_hijack_failed',
        userMessage: 'DNS 接管失败',
        repairAction: 'reapply_dns',
      );
    }
    if (systemProxyEnabled) {
      return (
        state: DesktopTunState.degraded,
        errorClass: 'system_proxy_conflict',
        userMessage: '系统代理与 TUN 同时开启，可能造成控制面回环',
        repairAction: 'clear_system_proxy',
      );
    }
    if (!transportOk && !googleOk && !githubOk) {
      return (
        state: DesktopTunState.degraded,
        errorClass: 'node_timeout',
        userMessage: 'TUN 已开启，但基础连通性异常',
        repairAction: 'refresh_and_probe',
      );
    }
    return (
      state: DesktopTunState.running,
      errorClass: 'ok',
      userMessage: 'TUN 已验证',
      repairAction: 'none',
    );
  }
}
