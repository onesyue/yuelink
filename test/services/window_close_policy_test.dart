import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/platform/window_close_policy.dart';
import 'package:yuelink/core/providers/core_runtime_providers.dart';

void main() {
  group('shouldQuitOnWindowClose', () {
    group('Linux always quits (no tray to hide to)', () {
      for (final status in CoreStatus.values) {
        for (final behavior in const ['tray', 'exit', 'whatever']) {
          test('linux/$status/$behavior → quit', () {
            expect(
              shouldQuitOnWindowClose(
                platform: 'linux',
                status: status,
                behavior: behavior,
              ),
              isTrue,
            );
          });
        }
      }
    });

    group('Windows + running quits regardless of behavior (P0-3 carve-out)',
        () {
      // The exact branch the user reported: Win11 taskbar Close while
      // connected was being swallowed by the default 'tray' behaviour,
      // and yuelink.exe stayed in Task Manager.
      for (final behavior in const ['tray', 'exit', 'unset']) {
        test('windows/running/$behavior → quit', () {
          expect(
            shouldQuitOnWindowClose(
              platform: 'windows',
              status: CoreStatus.running,
              behavior: behavior,
            ),
            isTrue,
          );
        });
      }
    });

    group('Windows + non-running respects behavior', () {
      // When the VPN is stopped the existing default ("hide to tray on
      // X") is the user-friendly choice — they may want to keep the
      // app reachable from tray for a quick reconnect later.
      for (final status in const [
        CoreStatus.stopped,
        CoreStatus.starting,
        CoreStatus.stopping,
      ]) {
        test('windows/$status/tray → hide', () {
          expect(
            shouldQuitOnWindowClose(
              platform: 'windows',
              status: status,
              behavior: 'tray',
            ),
            isFalse,
          );
        });
        test('windows/$status/exit → quit', () {
          expect(
            shouldQuitOnWindowClose(
              platform: 'windows',
              status: status,
              behavior: 'exit',
            ),
            isTrue,
          );
        });
      }
    });

    group('macOS always respects behavior (no carve-out)', () {
      // macOS Cmd+W on the title-bar X is widely-understood to hide;
      // the OS has its own quit muscle-memory (Cmd+Q). Keep parity
      // with the pre-P0-3 contract.
      for (final status in CoreStatus.values) {
        test('macos/$status/tray → hide', () {
          expect(
            shouldQuitOnWindowClose(
              platform: 'macos',
              status: status,
              behavior: 'tray',
            ),
            isFalse,
          );
        });
        test('macos/$status/exit → quit', () {
          expect(
            shouldQuitOnWindowClose(
              platform: 'macos',
              status: status,
              behavior: 'exit',
            ),
            isTrue,
          );
        });
      }
    });

    test('unknown platform falls through to behavior (defensive)', () {
      expect(
        shouldQuitOnWindowClose(
          platform: 'fuchsia',
          status: CoreStatus.running,
          behavior: 'tray',
        ),
        isFalse,
      );
      expect(
        shouldQuitOnWindowClose(
          platform: 'fuchsia',
          status: CoreStatus.running,
          behavior: 'exit',
        ),
        isTrue,
      );
    });

    test('unknown behavior on macOS treated as not-exit (hide)', () {
      // Defensive: any behavior string other than 'exit' is treated as
      // hide. Catches typos in settings.json and old persisted values
      // from removed UI options.
      expect(
        shouldQuitOnWindowClose(
          platform: 'macos',
          status: CoreStatus.stopped,
          behavior: 'something-removed-in-v0.9',
        ),
        isFalse,
      );
    });
  });
}
