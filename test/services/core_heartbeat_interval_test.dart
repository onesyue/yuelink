import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/managers/core_heartbeat_manager.dart';

void main() {
  group('CoreHeartbeatManager.intervalFor — reachability-aware cadence', () {
    test('foreground Wi-Fi → 15 s (responsive default)', () {
      expect(
        CoreHeartbeatManager.intervalFor(
          inBackground: false,
          transport: 'wifi',
        ),
        const Duration(seconds: 15),
      );
    });

    test('foreground cellular → 30 s (radio-dwell trade-off)', () {
      expect(
        CoreHeartbeatManager.intervalFor(
          inBackground: false,
          transport: 'cellular',
        ),
        const Duration(seconds: 30),
      );
    });

    test('background Wi-Fi → 60 s', () {
      expect(
        CoreHeartbeatManager.intervalFor(
          inBackground: true,
          transport: 'wifi',
        ),
        const Duration(seconds: 60),
      );
    });

    test('background cellular → 120 s (lowest power floor)', () {
      expect(
        CoreHeartbeatManager.intervalFor(
          inBackground: true,
          transport: 'cellular',
        ),
        const Duration(seconds: 120),
      );
    });

    test('unknown / "none" / blank transport collapses to Wi-Fi profile', () {
      // Defensive default: platforms that never fire `onTransportChanged`
      // (iOS, desktop) keep the responsive Wi-Fi cadence rather than
      // silently degrading to cellular timings.
      for (final t in const ['', 'none', 'wired', 'unknown', 'fubar']) {
        expect(
          CoreHeartbeatManager.intervalFor(
            inBackground: false,
            transport: t,
          ),
          const Duration(seconds: 15),
          reason: 'foreground $t should fall back to Wi-Fi cadence',
        );
        expect(
          CoreHeartbeatManager.intervalFor(
            inBackground: true,
            transport: t,
          ),
          const Duration(seconds: 60),
          reason: 'background $t should fall back to Wi-Fi cadence',
        );
      }
    });

    test('cellular foreground is exactly 2× Wi-Fi foreground', () {
      // Documented invariant: cellular cadence doubles the Wi-Fi value
      // because each radio wake on phones drains 5–10× more energy than
      // a Wi-Fi packet, but doubling alone (not 5×) keeps recovery
      // semantics within ~2.5 min after a real failure.
      final wifi = CoreHeartbeatManager.intervalFor(
        inBackground: false,
        transport: 'wifi',
      );
      final cellular = CoreHeartbeatManager.intervalFor(
        inBackground: false,
        transport: 'cellular',
      );
      expect(cellular.inSeconds, wifi.inSeconds * 2);
    });

    test('background cellular is exactly 2× background Wi-Fi', () {
      final wifi = CoreHeartbeatManager.intervalFor(
        inBackground: true,
        transport: 'wifi',
      );
      final cellular = CoreHeartbeatManager.intervalFor(
        inBackground: true,
        transport: 'cellular',
      );
      expect(cellular.inSeconds, wifi.inSeconds * 2);
    });
  });
}
