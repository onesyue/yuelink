import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/providers/core_runtime_providers.dart';
import 'package:yuelink/app/app_tray_controller.dart';

/// v1.0.22 P2-2: lock the tray status line format that surfaces the
/// active routing + connection mode in the tray tooltip / menu
/// header. Pure-function contract — production wiring (provider
/// reads, listener triggers) is integration-shaped.

void main() {
  group('formatTrayStatusLine', () {
    test('not logged in → static label, ignores other state', () {
      expect(
        formatTrayStatusLine(
          isLoggedIn: false,
          status: CoreStatus.running,
          currentNode: 'HK-1',
          routingMode: 'rule',
          connectionMode: 'tun',
          isDesktop: true,
        ),
        'YueLink · 未登录',
      );
    });

    test('starting → connecting label', () {
      expect(
        formatTrayStatusLine(
          isLoggedIn: true,
          status: CoreStatus.starting,
          currentNode: null,
          routingMode: 'rule',
          connectionMode: 'tun',
          isDesktop: true,
        ),
        'YueLink · 连接中...',
      );
    });

    test('stopped → disconnected label', () {
      expect(
        formatTrayStatusLine(
          isLoggedIn: true,
          status: CoreStatus.stopped,
          currentNode: 'HK-1',
          routingMode: 'rule',
          connectionMode: 'tun',
          isDesktop: true,
        ),
        'YueLink · 未连接',
      );
    });

    test('stopping is treated as disconnected (not running)', () {
      expect(
        formatTrayStatusLine(
          isLoggedIn: true,
          status: CoreStatus.stopping,
          currentNode: 'HK-1',
          routingMode: 'rule',
          connectionMode: 'tun',
          isDesktop: true,
        ),
        'YueLink · 未连接',
      );
    });

    test('desktop running TUN + rule + node → full 5-part line', () {
      expect(
        formatTrayStatusLine(
          isLoggedIn: true,
          status: CoreStatus.running,
          currentNode: 'HK-1',
          routingMode: 'rule',
          connectionMode: 'tun',
          isDesktop: true,
        ),
        'YueLink · 已连接 · 规则 · TUN · HK-1',
      );
    });

    test('desktop running systemProxy + global + node', () {
      expect(
        formatTrayStatusLine(
          isLoggedIn: true,
          status: CoreStatus.running,
          currentNode: 'JP-Premium',
          routingMode: 'global',
          connectionMode: 'systemProxy',
          isDesktop: true,
        ),
        'YueLink · 已连接 · 全局 · 系统代理 · JP-Premium',
      );
    });

    test('desktop running direct + no node → omits node segment', () {
      expect(
        formatTrayStatusLine(
          isLoggedIn: true,
          status: CoreStatus.running,
          currentNode: null,
          routingMode: 'direct',
          connectionMode: 'tun',
          isDesktop: true,
        ),
        'YueLink · 已连接 · 直连 · TUN',
      );
    });

    test('desktop running with empty-string node → treated as no node', () {
      expect(
        formatTrayStatusLine(
          isLoggedIn: true,
          status: CoreStatus.running,
          currentNode: '',
          routingMode: 'rule',
          connectionMode: 'tun',
          isDesktop: true,
        ),
        'YueLink · 已连接 · 规则 · TUN',
      );
    });

    test('mobile running → omits TUN/系统代理 segment (implicit VPN)', () {
      // On Android/iOS the connection mode is always VPN+TUN at OS
      // level; surfacing "TUN" in the tray tooltip would be redundant.
      // Routing mode is still surfaced.
      expect(
        formatTrayStatusLine(
          isLoggedIn: true,
          status: CoreStatus.running,
          currentNode: 'HK-1',
          routingMode: 'rule',
          connectionMode: 'tun',
          isDesktop: false,
        ),
        'YueLink · 已连接 · 规则 · HK-1',
      );
    });

    test('long node name is truncated to 16 chars + ellipsis', () {
      expect(
        formatTrayStatusLine(
          isLoggedIn: true,
          status: CoreStatus.running,
          currentNode: 'A-very-long-node-name-that-exceeds-budget',
          routingMode: 'rule',
          connectionMode: 'tun',
          isDesktop: true,
        ),
        'YueLink · 已连接 · 规则 · TUN · A-very-long-node…',
      );
    });

    test('unknown routing mode falls through verbatim (defensive)', () {
      // Future routing modes added to mihomo upstream shouldn't crash
      // the tray label — they should just appear as their raw string.
      expect(
        formatTrayStatusLine(
          isLoggedIn: true,
          status: CoreStatus.running,
          currentNode: null,
          routingMode: 'experimental',
          connectionMode: 'tun',
          isDesktop: true,
        ),
        'YueLink · 已连接 · experimental · TUN',
      );
    });
  });
}
