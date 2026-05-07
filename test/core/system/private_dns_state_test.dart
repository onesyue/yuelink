import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/system/private_dns_state.dart';

void main() {
  group('PrivateDnsState', () {
    test('bypassesTun is true ONLY for hostname mode (c.P3-1 contract)', () {
      // The whole point of mode-based dispatch — opportunistic mode is
      // common on Samsung etc. and must NOT trigger a strong banner.
      expect(
        const PrivateDnsState(mode: 'hostname', specifier: '1.1.1.1').bypassesTun,
        isTrue,
      );
      expect(
        const PrivateDnsState(mode: 'opportunistic').bypassesTun,
        isFalse,
      );
      expect(const PrivateDnsState(mode: 'off').bypassesTun, isFalse);
      expect(const PrivateDnsState(mode: 'unknown').bypassesTun, isFalse);
    });

    test('unknown sentinel is silent (no false-positive banner)', () {
      // Sentinel exists for non-Android platforms + OEM ROMs that block
      // Settings.Global reads. Must not surface as a warning.
      expect(PrivateDnsState.unknown().bypassesTun, isFalse);
    });

    test('equality is value-based on (mode, specifier)', () {
      const a = PrivateDnsState(mode: 'hostname', specifier: '1.1.1.1');
      const b = PrivateDnsState(mode: 'hostname', specifier: '1.1.1.1');
      const c = PrivateDnsState(mode: 'hostname', specifier: '8.8.8.8');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
