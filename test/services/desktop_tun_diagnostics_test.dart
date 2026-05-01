import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/tun/desktop_tun_diagnostics.dart';

void main() {
  group('DesktopTunDiagnostics Windows TUN matching', () {
    test('recognizes YueLink and upstream Meta Tunnel adapters', () {
      expect(
        DesktopTunDiagnostics.looksLikeWindowsTunInterfaceName('YueLink'),
        isTrue,
      );
      expect(
        DesktopTunDiagnostics.looksLikeWindowsTunInterfaceName('Meta Tunnel'),
        isTrue,
      );
      expect(
        DesktopTunDiagnostics.looksLikeWindowsTunInterfaceName('Meta'),
        isTrue,
      );
      expect(
        DesktopTunDiagnostics.looksLikeWindowsTunInterfaceName(
          'Wintun Userspace Tunnel',
        ),
        isTrue,
      );
    });

    test('does not treat ordinary Windows adapters as TUN', () {
      expect(
        DesktopTunDiagnostics.looksLikeWindowsTunInterfaceName(
          'Intel(R) Wi-Fi 6 AX201 160MHz',
        ),
        isFalse,
      );
      expect(
        DesktopTunDiagnostics.looksLikeWindowsTunInterfaceName(
          'Bluetooth Network Connection',
        ),
        isFalse,
      );
    });

    test('recognizes route print output for Meta Tunnel', () {
      const routePrint = '''
===========================================================================
Interface List
  3...........................Meta Tunnel
 11...70 d8 23 11 22 33 ......Intel(R) Wi-Fi 6 AX201 160MHz
===========================================================================
IPv4 Route Table
===========================================================================
''';
      expect(
        DesktopTunDiagnostics.windowsRouteOutputHasTun(routePrint),
        isTrue,
      );
    });

    test('recognizes netsh-style Meta interface name in route dumps', () {
      const routePrint = '''
Idx     Met         MTU          State                Name
---  ----------  ----------  ------------  ---------------------------
  3          25        1500  connected     Meta
 11          25        1500  connected     WLAN
''';
      expect(
        DesktopTunDiagnostics.windowsRouteOutputHasTun(routePrint),
        isTrue,
      );
    });

    test('does not treat WLAN-only route output as TUN', () {
      const routePrint = '''
Interface List
 11...70 d8 23 11 22 33 ......Intel(R) Wi-Fi 6 AX201 160MHz
IPv4 Route Table
''';
      expect(
        DesktopTunDiagnostics.windowsRouteOutputHasTun(routePrint),
        isFalse,
      );
    });
  });
}
