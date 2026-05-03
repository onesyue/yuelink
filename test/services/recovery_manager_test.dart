import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/kernel/recovery_manager.dart';
import 'package:yuelink/core/providers/core_provider.dart';
import 'package:yuelink/domain/models/traffic.dart';
import 'package:yuelink/domain/models/traffic_history.dart';

void main() {
  group('RecoveryManager.isAliveForPlatform', () {
    test('android trusts API availability over FFI running flag', () {
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: true,
          ffiRunning: false,
          isAndroid: true,
          isIOS: false,
        ),
        isTrue,
      );
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: false,
          ffiRunning: true,
          isAndroid: true,
          isIOS: false,
        ),
        isFalse,
      );
    });

    test('ios trusts API availability over FFI running flag', () {
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: true,
          ffiRunning: false,
          isAndroid: false,
          isIOS: true,
        ),
        isTrue,
      );
    });

    test('desktop requires both API and FFI health', () {
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: true,
          ffiRunning: true,
          isAndroid: false,
          isIOS: false,
        ),
        isTrue,
      );
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: true,
          ffiRunning: false,
          isAndroid: false,
          isIOS: false,
        ),
        isFalse,
      );
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: false,
          ffiRunning: true,
          isAndroid: false,
          isIOS: false,
        ),
        isFalse,
      );
    });
  });

  group('RecoveryManager.isAliveForMode', () {
    test(
      'desktop TUN service mode trusts API alone (mihomo in helper subprocess)',
      () {
        expect(
          RecoveryManager.isAliveForMode(
            apiOk: true,
            ffiRunning: false,
            isAndroid: false,
            isIOS: false,
            isDesktopTunService: true,
          ),
          isTrue,
          reason:
              'desktop service-mode TUN: in-app FFI is always false but '
              'apiOk=true means the helper-hosted core is healthy',
        );
        expect(
          RecoveryManager.isAliveForMode(
            apiOk: false,
            ffiRunning: false,
            isAndroid: false,
            isIOS: false,
            isDesktopTunService: true,
          ),
          isFalse,
        );
      },
    );

    test('desktop non-TUN still requires both API and FFI', () {
      expect(
        RecoveryManager.isAliveForMode(
          apiOk: true,
          ffiRunning: false,
          isAndroid: false,
          isIOS: false,
          isDesktopTunService: false,
        ),
        isFalse,
      );
      expect(
        RecoveryManager.isAliveForMode(
          apiOk: true,
          ffiRunning: true,
          isAndroid: false,
          isIOS: false,
          isDesktopTunService: false,
        ),
        isTrue,
      );
    });

    test('android/ios still trust API regardless of desktop flag', () {
      expect(
        RecoveryManager.isAliveForMode(
          apiOk: true,
          ffiRunning: false,
          isAndroid: true,
          isIOS: false,
          isDesktopTunService: false,
        ),
        isTrue,
      );
      expect(
        RecoveryManager.isAliveForMode(
          apiOk: true,
          ffiRunning: false,
          isAndroid: false,
          isIOS: true,
          isDesktopTunService: false,
        ),
        isTrue,
      );
    });
  });

  group('resetCoreToStopped (S3 batch4b regression lock)', () {
    // The previous shape of `RecoveryManager.resetToStopped` took
    // `StateController<X>` parameters and the convenience wrapper used
    // `(ref as dynamic).read(...)` to satisfy them — that dynamic cast
    // hid the real type from analyze. After the StateProvider → Notifier
    // migration in S3 batch4b, `ref.read(provider.notifier)` returns a
    // typed Notifier (e.g. `CoreStatusNotifier`) rather than a
    // StateController, and the old write style (`.state = X`) raises
    // NoSuchMethodError at runtime. This test mutates the four runtime
    // providers, calls the helper, and asserts every one is back to its
    // default — it would crash on the pre-fix code.

    test(
      'resets core/traffic/history/historyVersion to defaults',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Force every target provider off its default value so the reset
        // is observable.
        container.read(coreStatusProvider.notifier).set(CoreStatus.running);
        container
            .read(trafficProvider.notifier)
            .set(const Traffic(up: 1234, down: 5678));
        final dirtyHistory = TrafficHistory()..add(1, 2);
        container.read(trafficHistoryProvider.notifier).set(dirtyHistory);
        container.read(trafficHistoryVersionProvider.notifier).set(42);

        // Sanity: the mutations actually landed.
        expect(container.read(coreStatusProvider), CoreStatus.running);
        expect(container.read(trafficProvider).up, 1234);
        expect(container.read(trafficHistoryProvider).version, 1);
        expect(container.read(trafficHistoryVersionProvider), 42);

        // Skip the platform proxy clear so the test stays hermetic — the
        // CoreLifecycleManager.stopCoreForRecovery() call inside is
        // already fire-and-forget (.catchError) and a no-op in mock mode.
        resetCoreToStopped(container, clearDesktopProxy: false);

        expect(container.read(coreStatusProvider), CoreStatus.stopped);
        expect(container.read(trafficProvider), const Traffic());
        expect(container.read(trafficHistoryProvider).version, 0);
        expect(container.read(trafficHistoryVersionProvider), 0);
      },
    );
  });
}
