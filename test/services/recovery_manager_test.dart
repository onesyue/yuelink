import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/kernel/recovery_manager.dart';

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
}
