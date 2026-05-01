import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/tun/desktop_tun_diagnostics.dart';

void main() {
  group('DesktopTunDiagnostics privilege probe', () {
    test(
      'reports privileged when helper service is installed (no UAC needed)',
      () async {
        // Regression: a Windows user with the elevated SCM service installed
        // had TUN running cleanly (interface up, routes/DNS/Google/GitHub
        // verified) but the diagnostic still flipped state to
        // missing_permission because `_hasPrivilege` ran `net session`
        // against the un-elevated UI process. The helper IS the privileged
        // path on Windows just as on macOS/Linux — installation is the
        // boundary.
        var processCalled = false;
        final diag = DesktopTunDiagnostics(
          privilegedHelperProbe: () async => true,
          processRunner: (exe, args, timeout) async {
            processCalled = true;
            return ProcessResult(0, 1, '', 'must not be probed');
          },
        );
        expect(await diag.hasPrivilegeForTesting(), isTrue);
        expect(
          processCalled,
          isFalse,
          reason: 'helper-installed path must short-circuit before net session',
        );
      },
    );

    test(
      'falls back to net session on Windows when helper not installed',
      () async {
        if (!Platform.isWindows) return;
        var nseCalls = 0;
        final diag = DesktopTunDiagnostics(
          privilegedHelperProbe: () async => false,
          processRunner: (exe, args, timeout) async {
            nseCalls++;
            expect(exe, 'net');
            expect(args, ['session']);
            return ProcessResult(0, 0, '', '');
          },
        );
        expect(await diag.hasPrivilegeForTesting(), isTrue);
        expect(nseCalls, 1);
      },
    );

    test('non-desktop platforms always report false', () async {
      // Skip on the desktop platforms where the OS check actually runs.
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) return;
      final diag = DesktopTunDiagnostics(
        privilegedHelperProbe: () async => true,
      );
      expect(await diag.hasPrivilegeForTesting(), isFalse);
    });
  });

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
