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

  group('DesktopTunDiagnostics macOS route matching', () {
    test('returns the utun carrying mihomo split-default routes', () {
      // Captured from a real diagnostic bundle (yuelink-diagnostics-
      // 20260504_021022.txt) — utun6 holds the canonical 8-chunk
      // split-default mihomo installs on macOS.
      const netstat = '''
Internet:
Destination        Gateway            Flags               Netif Expire
default            192.168.86.1       UGScg                 en0
1                  198.18.0.1         UGSc                utun6
2/7                198.18.0.1         UGSc                utun6
4/6                198.18.0.1         UGSc                utun6
8/5                198.18.0.1         UGSc                utun6
16/4               198.18.0.1         UGSc                utun6
32/3               198.18.0.1         UGSc                utun6
64/2               198.18.0.1         UGSc                utun6
127                127.0.0.1          UCS                   lo0
128.0/1            198.18.0.1         UGSc                utun6
''';
      expect(
        DesktopTunDiagnostics.macosDefaultRouteTunInterface(netstat),
        'utun6',
      );
    });

    test('returns the utun for WireGuard-style 0/1 + 128.0/1 pair', () {
      const netstat = '''
Internet:
Destination        Gateway            Flags               Netif Expire
default            192.168.86.1       UGScg                 en0
0/1                10.0.0.1           UGSc                utun3
128.0/1            10.0.0.1           UGSc                utun3
''';
      expect(
        DesktopTunDiagnostics.macosDefaultRouteTunInterface(netstat),
        'utun3',
      );
    });

    test('returns null when no utun owns the default route', () {
      // Regression for the false positive in the May 4 2026 diagnostic:
      // the box has utun0..utun8 from other tunnels showing up only as
      // fe80:: link-local rows, none of which actually take 0/1, 128.0/1
      // or default. The old `out.contains("utun")` check returned true
      // here because the IPv6 routing table mentions every utun.
      const netstat = '''
Internet:
Destination        Gateway            Flags               Netif Expire
default            192.168.86.1       UGScg                 en0
127                127.0.0.1          UCS                   lo0
192.168.86         link#6             UCS                   en0

Internet6:
Destination                             Gateway                                 Flags               Netif Expire
fe80::%utun0/64                         fe80::1%utun0                           UcI                 utun0
fe80::%utun1/64                         fe80::1%utun1                           UcI                 utun1
fe80::%utun2/64                         fe80::1%utun2                           UcI                 utun2
''';
      expect(
        DesktopTunDiagnostics.macosDefaultRouteTunInterface(netstat),
        isNull,
      );
    });

    test('ignores default route owned by physical interface', () {
      const netstat = '''
Internet:
Destination        Gateway            Flags               Netif Expire
default            192.168.86.1       UGScg                 en0
''';
      expect(
        DesktopTunDiagnostics.macosDefaultRouteTunInterface(netstat),
        isNull,
      );
    });
  });

  group('DesktopTunDiagnostics fake-IP detection', () {
    test('recognizes 198.18.x.x fake-IP from mihomo default range', () {
      expect(
        DesktopTunDiagnostics.isFakeIpAddress(InternetAddress('198.18.0.1')),
        isTrue,
      );
      expect(
        DesktopTunDiagnostics.isFakeIpAddress(InternetAddress('198.18.255.42')),
        isTrue,
      );
    });

    test('recognizes 198.19.x.x as fake-IP (range future-proofing)', () {
      // mihomo allows fake-ip-range up to 198.18.0.0/15 — we don't want
      // a future range bump to silently turn the hijack probe into a
      // false negative.
      expect(
        DesktopTunDiagnostics.isFakeIpAddress(InternetAddress('198.19.0.5')),
        isTrue,
      );
    });

    test('rejects ordinary public IPv4 addresses', () {
      expect(
        DesktopTunDiagnostics.isFakeIpAddress(InternetAddress('142.250.74.78')),
        isFalse,
      );
      expect(
        DesktopTunDiagnostics.isFakeIpAddress(InternetAddress('8.8.8.8')),
        isFalse,
      );
    });

    test('rejects IPv4 outside the 198.18/15 fake-IP range', () {
      // Substring guards: 198.180.x.x or 198.1.x.x must not match the
      // `'198.18.'` / `'198.19.'` prefix check.
      expect(
        DesktopTunDiagnostics.isFakeIpAddress(InternetAddress('198.180.0.1')),
        isFalse,
      );
      expect(
        DesktopTunDiagnostics.isFakeIpAddress(InternetAddress('198.1.0.1')),
        isFalse,
      );
    });

    test('rejects IPv6 addresses regardless of value', () {
      expect(
        DesktopTunDiagnostics.isFakeIpAddress(InternetAddress('::1')),
        isFalse,
      );
    });
  });

  group('DesktopTunDiagnostics DNS hijack probe', () {
    test('reports hijack OK when system lookup returns a fake-IP', () async {
      var calls = 0;
      final diag = DesktopTunDiagnostics(
        hostResolver: (host) async {
          calls++;
          // First probe host already returns fake-IP — second probe must
          // be skipped (loop short-circuits on first success).
          return [InternetAddress('198.18.0.5')];
        },
      );
      expect(await diag.dnsHijackOkForTesting(), isTrue);
      expect(calls, 1);
    });

    test('falls through to second probe host when first answers DIRECT', () {
      // Regression: with respect-rules: true a single domain may hit a
      // DIRECT rule and resolve to its real IP. Probing two domains keeps
      // the check robust against per-domain rule decisions.
      return _expectHijack(
        responses: const {
          'www.google.com': ['142.250.74.78'], // DIRECT-resolved real IP
          'www.youtube.com': ['198.18.7.42'], // hijacked
        },
        expectedOk: true,
        expectedCalls: 2,
      );
    });

    test('reports hijack failed when no probe returns a fake-IP', () {
      // The whole point of the new probe — the previous `api.queryDns`
      // version reported OK here even though system DNS was bypassing
      // the TUN entirely.
      return _expectHijack(
        responses: const {
          'www.google.com': ['142.250.74.78'],
          'www.youtube.com': ['142.250.190.46'],
        },
        expectedOk: false,
        expectedCalls: 2,
      );
    });

    test('treats resolver errors as "not hijacked" but keeps probing', () {
      return _expectHijack(
        responses: const {
          'www.google.com': null, // throws
          'www.youtube.com': ['198.18.99.1'], // hijacked
        },
        expectedOk: true,
        expectedCalls: 2,
      );
    });

    test('all-error path returns false without raising', () {
      return _expectHijack(
        responses: const {'www.google.com': null, 'www.youtube.com': null},
        expectedOk: false,
        expectedCalls: 2,
      );
    });
  });

  group('DesktopTunDiagnostics Linux route matching', () {
    test('matches YueLink-named TUN device', () {
      const ipRoute = '''
default via 10.0.0.1 dev YueLink
192.168.1.0/24 dev wlp3s0 proto kernel
''';
      expect(
        DesktopTunDiagnostics.linuxRouteOutputHasYueLinkTun(
          ipRoute.toLowerCase(),
        ),
        isTrue,
      );
    });

    test('matches mihomo-named TUN device', () {
      const ipRoute = 'default via 10.0.0.1 dev mihomo metric 100\n';
      expect(
        DesktopTunDiagnostics.linuxRouteOutputHasYueLinkTun(
          ipRoute.toLowerCase(),
        ),
        isTrue,
      );
    });

    test('does not match generic tun0 from another VPN', () {
      // Regression: the previous `dev tun` substring matched any
      // `dev tun0`/`dev tun1` row from wg-quick or OpenVPN, even when
      // YueLink's own TUN was not up.
      const ipRoute = '''
default via 10.0.0.1 dev tun0
192.168.1.0/24 dev wlp3s0 proto kernel
''';
      expect(
        DesktopTunDiagnostics.linuxRouteOutputHasYueLinkTun(
          ipRoute.toLowerCase(),
        ),
        isFalse,
      );
    });
  });
}

/// Drives [DesktopTunDiagnostics.dnsHijackOkForTesting] with a scripted
/// resolver. Each entry in [responses] maps a probe host to either an IPv4
/// list (the resolver returns those addresses) or `null` (the resolver
/// throws, simulating NXDOMAIN / timeout). [expectedCalls] guards against
/// regressions in the short-circuit-on-success behaviour.
Future<void> _expectHijack({
  required Map<String, List<String>?> responses,
  required bool expectedOk,
  required int expectedCalls,
}) async {
  var calls = 0;
  final diag = DesktopTunDiagnostics(
    hostResolver: (host) async {
      calls++;
      final scripted = responses[host];
      if (scripted == null) {
        throw const SocketException('scripted resolver failure');
      }
      return scripted.map(InternetAddress.new).toList();
    },
  );
  expect(await diag.dnsHijackOkForTesting(), expectedOk);
  expect(calls, expectedCalls);
}
