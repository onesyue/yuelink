import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/tun/desktop_tun_repair_service.dart';
import 'package:yuelink/core/tun/desktop_tun_state.dart';

DesktopTunSnapshot _snap({
  bool hasAdmin = true,
  bool driverPresent = true,
  bool interfacePresent = true,
  bool routeOk = true,
  bool dnsOk = true,
  bool controllerOk = true,
  bool systemProxyEnabled = false,
  bool transportOk = true,
  bool googleOk = true,
  bool githubOk = true,
}) {
  return DesktopTunStateMachine.evaluate(
    platform: 'windows',
    mode: 'tun',
    tunStack: 'mixed',
    hasAdmin: hasAdmin,
    driverPresent: driverPresent,
    interfacePresent: interfacePresent,
    routeOk: routeOk,
    dnsOk: dnsOk,
    ipv6Enabled: false,
    controllerOk: controllerOk,
    systemProxyEnabled: systemProxyEnabled,
    proxyGuardActive: false,
    transportOk: transportOk,
    googleOk: googleOk,
    githubOk: githubOk,
  );
}

void main() {
  group('DesktopTunStateMachine', () {
    test('route failure is degraded, never running', () {
      final s = _snap(routeOk: false);
      expect(s.state, DesktopTunState.degraded);
      expect(s.runningVerified, isFalse);
      expect(s.errorClass, 'route_not_applied');
      expect(s.userMessage, contains('路由未接管'));
    });

    test('DNS probe failure alone does not degrade when transport works', () {
      // Regression: dns_ok is a single-domain probe (system lookup → fake-IP
      // expectation). It can flap when (a) macOS DNS cache returns a real
      // IP for a domain resolved before TUN was up, or (b) the probe domain
      // matches a `respect-rules: true` DIRECT rule. Both cases leave the
      // actual user traffic flowing through TUN — proven by googleOk /
      // githubOk which issue real HTTPS. Escalating to `dns_hijack_failed`
      // on dns_ok alone produced false alarms that misled users into
      // thinking switch-back-to-TUN was broken when it was working fine.
      final s = _snap(dnsOk: false, googleOk: true, githubOk: true);
      expect(s.state, DesktopTunState.running);
      expect(s.errorClass, 'ok');
    });

    test('DNS failure plus transport failure escalates to dns_hijack_failed', () {
      final s = _snap(
        dnsOk: false,
        googleOk: false,
        githubOk: false,
        transportOk: false,
      );
      expect(s.state, DesktopTunState.degraded);
      expect(s.runningVerified, isFalse);
      expect(s.errorClass, 'dns_hijack_failed');
      expect(s.userMessage, contains('DNS 接管失败'));
    });

    test('controller failure is not node failure', () {
      final s = _snap(controllerOk: false);
      expect(s.state, DesktopTunState.failed);
      expect(s.errorClass, 'controller_failed');
      expect(s.userMessage, contains('控制接口不可用'));
    });

    test('no privileged path shows missing_permission', () {
      // hasAdmin in this layer means "do we have a privileged path to
      // apply TUN routes/DNS" — the SCM service on Windows / launchd
      // helper on macOS / systemd unit on Linux. It is NOT a check
      // that the UI process itself runs as admin.
      final s = _snap(hasAdmin: false);
      expect(s.state, DesktopTunState.missingPermission);
      expect(s.errorClass, 'missing_permission');
      expect(s.userMessage, contains('管理员权限'));
    });

    test(
      'fully working TUN on Windows is running, even without UAC elevation',
      () {
        // Regression for the Windows service-mode false positive: when the
        // helper service is installed, hasAdmin is true regardless of
        // whether the UI process is elevated, so a TUN that has every
        // verifiable layer green must classify as running.
        final s = _snap(
          hasAdmin: true,
          driverPresent: true,
          interfacePresent: true,
          routeOk: true,
          dnsOk: true,
          controllerOk: true,
          systemProxyEnabled: false,
          transportOk: true,
          googleOk: true,
          githubOk: true,
        );
        expect(s.state, DesktopTunState.running);
        expect(s.errorClass, 'ok');
        expect(s.runningVerified, isTrue);
      },
    );

    test('Windows missing Wintun shows missing_driver', () {
      final s = _snap(driverPresent: false);
      expect(s.state, DesktopTunState.missingDriver);
      expect(s.errorClass, 'missing_driver');
      expect(s.userMessage, contains('驱动'));
    });

    test('Linux missing /dev/net/tun maps to missing_driver', () {
      final s = DesktopTunStateMachine.evaluate(
        platform: 'linux',
        mode: 'tun',
        tunStack: 'mixed',
        hasAdmin: true,
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
      );
      expect(s.errorClass, 'missing_driver');
    });

    test('system proxy conflict is explicit', () {
      final s = _snap(systemProxyEnabled: true);
      expect(s.state, DesktopTunState.degraded);
      expect(s.errorClass, 'system_proxy_conflict');
      expect(s.userMessage, contains('系统代理'));
    });

    test('AI/reality errors are not classified as TUN local failures', () {
      final ai = _snap();
      expect(ai.errorClass, isNot('ai_blocked'));
      expect(ai.errorClass, isNot('reality_auth_failed'));
    });

    test('cleanup failed is represented explicitly', () {
      const s = DesktopTunSnapshot(
        state: DesktopTunState.cleanupFailed,
        platform: 'macos',
        mode: 'tun',
        tunStack: 'mixed',
        hasAdmin: true,
        driverPresent: true,
        interfacePresent: true,
        routeOk: false,
        dnsOk: false,
        ipv6Enabled: false,
        controllerOk: false,
        systemProxyEnabled: true,
        proxyGuardActive: false,
        transportOk: false,
        googleOk: false,
        githubOk: false,
        errorClass: 'cleanup_failed',
        userMessage: 'TUN 停止后仍有残留',
        repairAction: 'cleanup_and_restart',
      );
      expect(s.needsRepair, isTrue);
      expect(s.runningVerified, isFalse);
    });
  });

  group('DesktopTunRepairService', () {
    test('repair does not loop level2 within 30 seconds', () async {
      var now = DateTime(2026, 5, 1, 12);
      final service = DesktopTunRepairService(
        now: () => now,
        sleep: (_) async {},
      );
      final plan = service.plan(_snap(controllerOk: false));
      var runs = 0;
      await service.runThrottled(plan, () async => runs++);
      await service.runThrottled(plan, () async => runs++);
      expect(runs, 1);
      now = now.add(const Duration(seconds: 31));
      await service.runThrottled(plan, () async => runs++);
      expect(runs, 2);
    });
  });
}
