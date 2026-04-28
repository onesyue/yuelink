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

    group('Windows respects behavior in every status', () {
      // Reverse of v1.0.22 P0-3 carve-out. The user-reported regression:
      // explicit `closeBehavior='tray'` was being overridden when the VPN
      // was running, so closing the window force-quit instead of hiding.
      // The "无法退出" group is now served by the tray right-click → Quit
      // menu, identical to macOS muscle-memory.
      for (final status in CoreStatus.values) {
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

    group('macOS respects behavior in every status', () {
      // macOS Cmd+W on the title-bar X is widely-understood to hide;
      // the OS has its own quit muscle-memory (Cmd+Q). Identical
      // contract to Windows post-revert.
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

    test('unknown behavior treated as not-exit (hide)', () {
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
      expect(
        shouldQuitOnWindowClose(
          platform: 'windows',
          status: CoreStatus.running,
          behavior: 'something-removed-in-v0.9',
        ),
        isFalse,
      );
    });
  });
}
