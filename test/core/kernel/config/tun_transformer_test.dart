import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:yuelink/core/kernel/config/tun_transformer.dart';
import 'package:yuelink/core/kernel/config_template.dart';

/// Tests for [TunTransformer.buildDesktopTunYaml] (b.P2-2 builder) and
/// [TunTransformer.ensureDesktopTun] (b.P2-1 lanCompatMode plumbing).
///
/// Two invariants to lock:
///
///   1. **Builder is pure**. No SettingsService access, no Riverpod, no
///      I/O. All user preferences come in as parameters.
///   2. **Cold-start composes the builder**. Anything `ensureDesktopTun`
///      emits in its tun: section must be byte-identical to what
///      `buildDesktopTunYaml` produces, so any future hot-switch path
///      that calls the builder directly cannot drift.
void main() {
  group('TunTransformer.buildDesktopTunYaml', () {
    test('produces a valid YAML fragment', () {
      final yaml = TunTransformer.buildDesktopTunYaml(stack: 'mixed');
      // Wrap in a top-level key to make it a complete YAML document.
      expect(() => loadYaml(yaml), returnsNormally);
    });

    test('starts with `tun:` header and ends with newline', () {
      final yaml = TunTransformer.buildDesktopTunYaml(stack: 'mixed');
      expect(yaml, startsWith('tun:\n'));
      expect(yaml, endsWith('\n'));
    });

    test('contains the safety-critical keys we never want to lose', () {
      final yaml = TunTransformer.buildDesktopTunYaml(stack: 'mixed');
      // Without these entries the desktop TUN leaks IPv6 / loses DNS
      // hijack. They are baseline for desktop and must always be emitted.
      expect(yaml, contains('enable: true'));
      expect(yaml, contains('auto-route: true'));
      expect(yaml, contains('auto-detect-interface: true'));
      expect(yaml, contains('inet6-address:'));
      expect(yaml, contains('fdfe:dcba:9876::1/126'));
      expect(yaml, contains('dns-hijack:'));
      expect(yaml, contains('any:53'));
      expect(yaml, contains('tcp://any:53'));
      expect(yaml, contains('mtu:'));
    });

    test('normalises unknown stack to mixed', () {
      expect(
        TunTransformer.buildDesktopTunYaml(stack: 'unknown-value'),
        contains('stack: mixed'),
      );
    });

    test('preserves system and gvisor stacks verbatim', () {
      expect(
        TunTransformer.buildDesktopTunYaml(stack: 'system'),
        contains('stack: system'),
      );
      expect(
        TunTransformer.buildDesktopTunYaml(stack: 'gvisor'),
        contains('stack: gvisor'),
      );
    });

    test('emits bypassAddresses as route-exclude-address when non-empty', () {
      final yaml = TunTransformer.buildDesktopTunYaml(
        stack: 'mixed',
        bypassAddresses: ['192.168.50.0/24', '10.42.0.0/16'],
      );
      expect(yaml, contains('route-exclude-address:'));
      expect(yaml, contains('- 192.168.50.0/24'));
      expect(yaml, contains('- 10.42.0.0/16'));
    });

    test('omits route-exclude-address block when bypass list empty', () {
      final yaml = TunTransformer.buildDesktopTunYaml(stack: 'mixed');
      expect(yaml, isNot(contains('route-exclude-address:')));
    });

    test('is deterministic — same input ⇒ byte-identical output', () {
      final a = TunTransformer.buildDesktopTunYaml(
        stack: 'mixed',
        bypassAddresses: ['10.0.0.0/8'],
        windowsLanCompatibilityMode: true,
      );
      final b = TunTransformer.buildDesktopTunYaml(
        stack: 'mixed',
        bypassAddresses: ['10.0.0.0/8'],
        windowsLanCompatibilityMode: true,
      );
      expect(b, equals(a));
    });

    test('strict-route reflects (isWindows && !lanCompatMode)', () {
      final off = TunTransformer.buildDesktopTunYaml(
        stack: 'mixed',
        windowsLanCompatibilityMode: false,
      );
      final on = TunTransformer.buildDesktopTunYaml(
        stack: 'mixed',
        windowsLanCompatibilityMode: true,
      );
      if (Platform.isWindows) {
        // P2-1 contract: Windows + lanCompat off → safer strict-route on
        expect(off, contains('strict-route: true'));
        // Windows + lanCompat on → relax for LAN access
        expect(on, contains('strict-route: false'));
      } else {
        // Non-Windows: strict-route is always false regardless of toggle
        expect(off, contains('strict-route: false'));
        expect(on, contains('strict-route: false'));
      }
    });

    // ── Platform-injected tests (cover all 6 combinations on any host) ──
    // CI runs on Mac/Linux; without injection the Windows branch was
    // never exercised. Use TunPlatform overrides to force each.

    test('Windows + lanCompat OFF → strict-route: true (override)', () {
      final yaml = TunTransformer.buildDesktopTunYaml(
        stack: 'mixed',
        windowsLanCompatibilityMode: false,
        platformOverrideForTest: TunPlatform.windows,
      );
      expect(yaml, contains('strict-route: true'));
      expect(yaml, contains('device: YueLink')); // Win emits device:
    });

    test('Windows + lanCompat ON → strict-route: false (override)', () {
      final yaml = TunTransformer.buildDesktopTunYaml(
        stack: 'mixed',
        windowsLanCompatibilityMode: true,
        platformOverrideForTest: TunPlatform.windows,
      );
      expect(yaml, contains('strict-route: false'));
      expect(yaml, contains('device: YueLink'));
    });

    test('Linux + lanCompat (any) → strict-route: false (override)', () {
      for (final lanCompat in const [true, false]) {
        final yaml = TunTransformer.buildDesktopTunYaml(
          stack: 'mixed',
          windowsLanCompatibilityMode: lanCompat,
          platformOverrideForTest: TunPlatform.linux,
        );
        expect(yaml, contains('strict-route: false'),
            reason: 'Linux must always emit strict-route: false; '
                'lanCompat=$lanCompat case');
        expect(yaml, contains('device: YueLink'));
      }
    });

    test('macOS + lanCompat (any) → strict-route: false (override)', () {
      for (final lanCompat in const [true, false]) {
        final yaml = TunTransformer.buildDesktopTunYaml(
          stack: 'mixed',
          windowsLanCompatibilityMode: lanCompat,
          platformOverrideForTest: TunPlatform.macos,
        );
        expect(yaml, contains('strict-route: false'));
        expect(yaml, isNot(contains('device:')),
            reason: 'macOS must NOT emit `device:` line (mihomo derives '
                'utun on the fly)');
      }
    });

    test('computeStrictRoute pure logic (4 combinations)', () {
      expect(
        TunTransformer.computeStrictRoute(
          isWindows: true, windowsLanCompatibilityMode: false),
        isTrue,
      );
      expect(
        TunTransformer.computeStrictRoute(
          isWindows: true, windowsLanCompatibilityMode: true),
        isFalse,
      );
      expect(
        TunTransformer.computeStrictRoute(
          isWindows: false, windowsLanCompatibilityMode: false),
        isFalse,
      );
      expect(
        TunTransformer.computeStrictRoute(
          isWindows: false, windowsLanCompatibilityMode: true),
        isFalse,
      );
    });
  });

  group('TunTransformer.ensureDesktopTun (cold-start orchestration)', () {
    const minimalConfig = '''
mixed-port: 7890
proxies: []
proxy-groups: []
rules: []
''';

    test('output contains the builder\'s tun: section verbatim', () {
      // P2-2 invariant: cold start must compose the builder, not
      // reimplement TUN field selection. Hot-switch paths that call the
      // builder directly therefore stay byte-identical to cold-start.
      final builderYaml = TunTransformer.buildDesktopTunYaml(stack: 'mixed');
      final fullConfig = TunTransformer.ensureDesktopTun(
        minimalConfig,
        'mixed',
      );
      // Strip trailing newline for sub-string match (full config has more
      // content after the tun: section in some orderings, but the tun:
      // block as a whole must appear).
      expect(
        fullConfig.contains(builderYaml),
        isTrue,
        reason:
            'ensureDesktopTun did not compose buildDesktopTunYaml verbatim — '
            'P2-2 invariant broken. Hot-switch path will diverge from cold '
            'start. Fix: route ensureDesktopTun through buildDesktopTunYaml.',
      );
    });

    test('threads lanCompatMode through to the builder', () {
      final off = TunTransformer.ensureDesktopTun(
        minimalConfig,
        'mixed',
        windowsLanCompatibilityMode: false,
      );
      final on = TunTransformer.ensureDesktopTun(
        minimalConfig,
        'mixed',
        windowsLanCompatibilityMode: true,
      );
      if (Platform.isWindows) {
        expect(off, contains('strict-route: true'));
        expect(on, contains('strict-route: false'));
      } else {
        // Outputs differ only by params on Windows; on other hosts the
        // strict-route line is identical. Test still verifies the param
        // is accepted without error.
        expect(off, contains('strict-route: false'));
        expect(on, contains('strict-route: false'));
      }
    });

    test('flips top-level ipv6 to true (TUN needs AAAA processing)', () {
      // ScalarTransformers.ensureIpv6 sets `ipv6: false` globally; on
      // desktop TUN we must override to `ipv6: true` or AAAA queries are
      // refused and the IPv6 hijack is dead on arrival.
      final out = TunTransformer.ensureDesktopTun(
        '''
mixed-port: 7890
ipv6: false
''',
        'mixed',
      );
      expect(out, contains('ipv6: true'));
    });

    test('removes any pre-existing tun: section (no double-write)', () {
      const withStaleTun = '''
mixed-port: 7890
tun:
  enable: false
  stack: system
''';
      final out = TunTransformer.ensureDesktopTun(withStaleTun, 'mixed');
      // Only one tun: top-level header should remain.
      final tunMatches = RegExp(r'^tun:', multiLine: true).allMatches(out);
      expect(tunMatches.length, 1);
    });
  });

  group('ConfigTemplate.process — lanCompat end-to-end (b.P2-1 plumbing)', () {
    const minimalConfig = '''
mixed-port: 7890
proxies: []
proxy-groups:
  - name: PROXY
    type: select
    proxies: [DIRECT]
rules:
  - MATCH,PROXY
''';

    test('windowsLanCompatibilityMode flag flows from process() to YAML', () {
      // E2E: this is the assertion the in-document blocker review asked
      // for — without it, a future refactor could drop the parameter on
      // any of `process` / `ensureDesktopTun` / `buildDesktopTunYaml`
      // and Windows users would silently get the wrong strict-route
      // value with no test failure.
      final off = ConfigTemplate.process(
        minimalConfig,
        connectionMode: 'tun',
      );
      final on = ConfigTemplate.process(
        minimalConfig,
        connectionMode: 'tun',
        windowsLanCompatibilityMode: true,
      );

      if (Platform.isWindows) {
        expect(off, contains('strict-route: true'));
        expect(on, contains('strict-route: false'));
      } else {
        // On Mac/Linux CI the host can't observe the Windows-specific
        // toggle. We still verify the parameter is accepted and the
        // resulting YAML is valid + contains a tun: section, so
        // signature regressions are caught.
        expect(off, contains('strict-route: false'));
        expect(on, contains('strict-route: false'));
        expect(() => loadYaml(on), returnsNormally);
      }
      // Both outputs always have a tun: section in tun mode.
      expect(off, contains('\ntun:\n'));
      expect(on, contains('\ntun:\n'));
    });

    test('systemProxy mode disables tun regardless of lanCompat flag', () {
      final out = ConfigTemplate.process(
        minimalConfig,
        connectionMode: 'systemProxy',
        windowsLanCompatibilityMode: true,
      );
      // tun.enable should be absent / false; the section is removed for
      // systemProxy. Loose check: full block was not added.
      expect(out, isNot(contains('strict-route: true')));
    });
  });
}
