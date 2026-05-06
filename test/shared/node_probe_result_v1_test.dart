import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/node_telemetry.dart';
import 'package:yuelink/shared/telemetry.dart';

/// Closed-schema test for `node_probe_result_v1`.
///
/// The point of this event is that **dashboards and pipelines downstream
/// can rely on the field set never widening to include secrets**. If a
/// future change accidentally passes `server` or `uuid` through, this
/// test fails. Don't relax it — extend the whitelist instead, with an
/// explicit review of why the new field is privacy-safe.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync(
      'yuelink_probe_result_v1_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    Telemetry.setEnabled(true);
    NodeTelemetry.resetForTest();
  });

  tearDown(() {
    Telemetry.setEnabled(false);
  });

  Map<String, dynamic> onlyProbeEvent(int cursor) {
    return Telemetry.recentEvents()
        .skip(cursor)
        .firstWhere((e) => e['event'] == TelemetryEvents.nodeProbeResultV1);
  }

  test('classifyTarget covers the seven sites + transport bucket', () {
    expect(
      NodeTelemetry.classifyTarget('https://www.gstatic.com/generate_204'),
      'transport',
    );
    expect(NodeTelemetry.classifyTarget('https://www.google.com/'), 'google');
    expect(NodeTelemetry.classifyTarget('https://claude.ai/'), 'claude');
    expect(
      NodeTelemetry.classifyTarget('https://api.anthropic.com/v1/'),
      'claude',
    );
    expect(NodeTelemetry.classifyTarget('https://chatgpt.com/'), 'chatgpt');
    expect(NodeTelemetry.classifyTarget('https://chat.openai.com/'), 'chatgpt');
    expect(NodeTelemetry.classifyTarget('https://www.netflix.com/'), 'netflix');
    expect(NodeTelemetry.classifyTarget('https://www.youtube.com/'), 'youtube');
    expect(NodeTelemetry.classifyTarget('https://github.com/'), 'github');
    expect(NodeTelemetry.classifyTarget('https://example.com/'), 'other');
    expect(NodeTelemetry.classifyTarget('not-a-url'), 'other');
  });

  test('event payload is restricted to the closed whitelist', () {
    NodeTelemetry.recordInventory([
      {
        'name': 'TW-HY2',
        'type': 'hysteria2',
        'server': 'a.example.com',
        'port': 443,
        'sni': 'a.example.com',
        'password': 'secret-a',
        'xb_server_id': 127,
        'region': 'TW',
      },
    ]);
    final cursor = Telemetry.recentEvents().length;

    NodeTelemetry.recordProbeResultByName(
      name: 'TW-HY2',
      testUrl: 'https://www.gstatic.com/generate_204',
      delayMs: 142,
      group: '悦 · 自动选择',
      connectionMode: 'systemProxy',
      tunEnabled: false,
      tunStack: 'mixed',
      routeOk: true,
      dnsOk: true,
      controllerOk: true,
      coreVersion: 'v1.19.24',
    );

    final ev = onlyProbeEvent(cursor);

    // The envelope-level keys come from Telemetry.event() and are NOT
    // user-controlled props. They are: event, client_id, session_id, seq,
    // platform, version, ts. Everything else under the event is from
    // recordProbeResult's props.
    const envelope = {
      'event',
      'client_id',
      'session_id',
      'seq',
      'platform',
      'os_version',
      'version',
      'ts',
    };
    const allowedProps = {
      'fp',
      'type',
      'xb_server_id',
      'group',
      'node_name_hash',
      'target',
      'ok',
      'status',
      'latency_ms',
      'timeout_ms',
      'error_class',
      'status_code',
      'is_ai_target',
      'core_version',
      'connection_mode',
      'mode',
      'tun_enabled',
      'tun_stack',
      'route_ok',
      'dns_ok',
      'controller_ok',
      'network_type',
      'client_region',
      'exit_country',
      'exit_isp',
      'sample_rate',
    };
    final allowed = <String>{...envelope, ...allowedProps};
    final unexpected = ev.keys.toSet().difference(allowed);
    expect(
      unexpected,
      isEmpty,
      reason: 'event has fields outside the whitelist: $unexpected',
    );

    // Spot-check the values that ARE allowed.
    expect(ev['xb_server_id'], 127);
    expect(ev['target'], 'transport');
    expect(ev['ok'], isTrue);
    expect(ev['status'], 'ok');
    expect(ev['latency_ms'], 142);
    expect(ev['timeout_ms'], 5000);
    expect(ev['group'], '悦 · 自动选择');
    expect(ev['node_name_hash'], isA<String>());
    expect(ev['connection_mode'], 'systemProxy');
    expect(ev['mode'], 'system_proxy');
    expect(ev['tun_enabled'], isFalse);
    expect(ev['tun_stack'], 'mixed');
    expect(ev['route_ok'], isTrue);
    expect(ev['dns_ok'], isTrue);
    expect(ev['controller_ok'], isTrue);
    expect(ev['core_version'], 'v1.19.24');
    expect(ev['is_ai_target'], isFalse);
    expect(ev['sample_rate'], 1.0);
    expect(ev.containsKey('error_class'), isFalse);
  });

  test('failed probe carries error_class=timeout and clamps latency', () {
    NodeTelemetry.recordInventory([
      {
        'name': 'HK-Reality',
        'type': 'vless',
        'server': 'b.example.com',
        'port': 8443,
        'uuid': 'uuid-b',
        'sni': 'b.example.com',
        'xb_server_id': 88,
        'region': 'HK',
      },
    ]);
    final cursor = Telemetry.recentEvents().length;

    NodeTelemetry.recordProbeResultByName(
      name: 'HK-Reality',
      testUrl: 'https://claude.ai/',
      delayMs: -1,
      group: '悦 · AI',
      connectionMode: 'tun',
      tunEnabled: true,
      tunStack: 'mixed',
      routeOk: false,
      dnsOk: true,
      controllerOk: true,
      timeoutMs: 5000,
    );

    final ev = onlyProbeEvent(cursor);
    expect(ev['target'], 'claude');
    expect(ev['ok'], isFalse);
    expect(ev['status'], 'timeout');
    expect(ev['latency_ms'], 5000);
    expect(ev['timeout_ms'], 5000);
    expect(ev['error_class'], 'timeout');
    expect(ev['is_ai_target'], isTrue);
    expect(ev['mode'], 'tun');
    expect(ev['tun_enabled'], isTrue);
    expect(ev['route_ok'], isFalse);
  });

  test('repeated failed probes are rate limited by fp target and error', () {
    final cursor = Telemetry.recentEvents().length;

    for (var i = 0; i < 4; i++) {
      NodeTelemetry.recordProbeResult(
        fp: 'rate-limit-node',
        type: 'vless',
        target: 'transport',
        ok: false,
        latencyMs: 5000,
        errorClass: 'timeout',
      );
    }

    final events = Telemetry.recentEvents()
        .skip(cursor)
        .where((e) => e['event'] == TelemetryEvents.nodeProbeResultV1)
        .toList();
    expect(events, hasLength(3));
    expect(events.every((e) => e['error_class'] == 'timeout'), isTrue);
  });

  test('AI 403 is classified as ai_blocked, not node timeout', () {
    final cursor = Telemetry.recentEvents().length;
    NodeTelemetry.recordProbeResult(
      fp: 'abcdabcdabcdabcd',
      type: 'vless',
      group: 'AI',
      nodeNameHash: 'hashhashhashhash',
      target: 'chatgpt',
      ok: false,
      latencyMs: 320,
      timeoutMs: 5000,
      statusCode: 403,
      connectionMode: 'rule',
      networkType: 'wifi',
      sampleRate: 0.25,
    );

    final ev = onlyProbeEvent(cursor);
    expect(ev['target'], 'chatgpt');
    expect(ev['status_code'], 403);
    expect(ev['error_class'], 'ai_blocked');
    expect(ev['status'], 'ai_blocked');
    expect(ev['is_ai_target'], isTrue);
    expect(ev['mode'], 'rule');
    expect(ev['network_type'], 'wifi');
    expect(ev['sample_rate'], 0.25);
  });

  test('Reality auth failure has its own error class', () {
    final cursor = Telemetry.recentEvents().length;
    NodeTelemetry.recordProbeResult(
      fp: 'bbbbbbbbbbbbbbbb',
      type: 'vless',
      target: 'transport',
      ok: false,
      latencyMs: 5000,
      timeoutMs: 5000,
      errorClass: 'REALITY authentication failed',
    );

    final ev = onlyProbeEvent(cursor);
    expect(ev['error_class'], 'reality_auth_failed');
    expect(ev['status'], 'reality_auth_failed');
    expect(ev['is_ai_target'], isFalse);
  });

  test('event does NOT leak server / port / uuid / password / sni', () {
    NodeTelemetry.recordInventory([
      {
        'name': 'TW-HY2',
        'type': 'hysteria2',
        'server': 'a.example.com',
        'port': 443,
        'sni': 'a.example.com',
        'password': 'secret-a',
        'uuid': 'uuid-a',
        'public-key': 'pk-a',
        'short-id': 'sid-a',
        'xb_server_id': 127,
        'region': 'TW',
      },
    ]);
    final cursor = Telemetry.recentEvents().length;
    NodeTelemetry.recordProbeResultByName(
      name: 'TW-HY2',
      testUrl: 'https://www.gstatic.com/generate_204',
      delayMs: 100,
    );

    final ev = onlyProbeEvent(cursor);

    // No banned key may appear at any level of the event.
    const banned = [
      'server',
      'port',
      'uuid',
      'password',
      'passwd',
      'sni',
      'servername',
      'server-name',
      'host',
      'public-key',
      'publickey',
      'short-id',
      'shortid',
      'path',
      'private-key',
      'auth',
      'psk',
    ];
    for (final k in banned) {
      expect(
        ev.containsKey(k),
        isFalse,
        reason: 'banned key "$k" leaked into event',
      );
    }

    // No banned literal value either.
    final flatValues = ev.values.map((v) => v.toString()).toList();
    for (final secret in [
      'a.example.com',
      'secret-a',
      'uuid-a',
      'pk-a',
      'sid-a',
    ]) {
      for (final v in flatValues) {
        expect(
          v.contains(secret),
          isFalse,
          reason: 'secret "$secret" leaked in value "$v"',
        );
      }
    }
  });

  test('silently no-ops when the node is not in inventory', () {
    NodeTelemetry.resetForTest();
    final cursor = Telemetry.recentEvents().length;
    NodeTelemetry.recordProbeResultByName(
      name: 'unknown-node',
      testUrl: 'https://www.gstatic.com/generate_204',
      delayMs: 100,
    );
    final after = Telemetry.recentEvents().skip(cursor).toList();
    expect(
      after.where((e) => e['event'] == TelemetryEvents.nodeProbeResultV1),
      isEmpty,
    );
  });
}
