import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android YueLinkVpnService route/proxy defaults', () {
    late final String source;

    setUpAll(() {
      source = File(
        'android/app/src/main/kotlin/com/yueto/yuelink/YueLinkVpnService.kt',
      ).readAsStringSync();
    });

    test('uses Clash Meta style public IPv4 route split, not blunt default', () {
      expect(source, contains('PUBLIC_IPV4_ROUTES'));
      expect(source, contains('addPublicIpv4Routes(builder)'));
      expect(source, isNot(contains('.addRoute("0.0.0.0", 0)')));
      expect(source, contains('"10.*"'));
      expect(source, contains('"192.168.*"'));
    });

    test('advertises per-VPN HTTP proxy with local bypasses on Android Q+', () {
      expect(source, contains('builder.setHttpProxy'));
      expect(source, contains('ProxyInfo.buildDirectProxy'));
      expect(source, contains('VPN_HTTP_PROXY_EXCLUSIONS'));
      expect(source, contains('"169.254.*"'));
    });
  });
}
