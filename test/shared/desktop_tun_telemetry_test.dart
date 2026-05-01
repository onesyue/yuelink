import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/tun/desktop_tun_state.dart';
import 'package:yuelink/core/tun/desktop_tun_telemetry.dart';
import 'package:yuelink/shared/telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('yuelink_tun_tel_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  setUp(() => Telemetry.setEnabled(true));
  tearDown(() => Telemetry.setEnabled(false));

  test('desktop_tun_health_snapshot_v1 has no sensitive route/DNS detail', () {
    final cursor = Telemetry.recentEvents().length;
    final snapshot = DesktopTunStateMachine.evaluate(
      platform: 'windows',
      mode: 'tun',
      tunStack: 'mixed',
      hasAdmin: false,
      driverPresent: false,
      interfacePresent: false,
      routeOk: false,
      dnsOk: false,
      ipv6Enabled: true,
      controllerOk: false,
      systemProxyEnabled: true,
      proxyGuardActive: true,
      transportOk: false,
      googleOk: false,
      githubOk: false,
    );

    DesktopTunTelemetry.healthSnapshot(snapshot);
    final event = Telemetry.recentEvents()
        .skip(cursor)
        .firstWhere(
          (e) => e['event'] == TelemetryEvents.desktopTunHealthSnapshotV1,
        );

    const allowed = {
      'event',
      'client_id',
      'session_id',
      'seq',
      'platform',
      'os_version',
      'version',
      'ts',
      'core_version',
      'tun_stack',
      'mode',
      'state',
      'has_admin',
      'driver_present',
      'interface_present',
      'route_ok',
      'dns_ok',
      'ipv6_enabled',
      'controller_ok',
      'system_proxy_enabled',
      'proxy_guard_active',
      'transport_ok',
      'google_ok',
      'github_ok',
      'error_class',
      'elapsed_ms',
      'repair_action',
      'sample_rate',
    };
    expect(event.keys.toSet().difference(allowed), isEmpty);
    for (final banned in const [
      'server',
      'port',
      'uuid',
      'password',
      'publicKey',
      'shortId',
      'sni',
      'dns_servers',
      'route_table',
      'interface_list',
      'subscription',
    ]) {
      expect(event.containsKey(banned), isFalse);
    }
  });
}
