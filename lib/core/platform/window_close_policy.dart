import '../providers/core_runtime_providers.dart';

/// Decision for the OS window-close button (X / taskbar Close / Cmd+W):
/// quit the process or hide to system tray?
///
/// v1.0.22 P0-3 added a Windows+running carve-out that force-quit when
/// the VPN was active, motivated by users who reported "无法退出" after
/// using the Win11 taskbar's right-click → Close window. The carve-out
/// turned out to break the opposite group: users who explicitly set
/// `closeBehavior='tray'` and expected the window to hide while their
/// VPN kept running. The reverse fix below honours user preference
/// strictly on Windows. The "无法退出" path is preserved through the
/// tray icon's right-click → Quit menu (always wired up on Windows).
///
/// Rule:
///   - Linux  → always quit (no system tray to hide to in the first
///     place; the existing `onWindowClose` already had this carve-out).
///   - macOS / Windows → respect [behavior]. `'exit'` quits, anything
///     else (including the default `'tray'`) hides. Identical contract
///     across desktop platforms with system trays.
///
/// Pure function — `platform` is a `Platform.operatingSystem` value
/// (`'windows'` / `'macos'` / `'linux'` / etc.) so tests can drive
/// every branch without touching `dart:io`.
bool shouldQuitOnWindowClose({
  required String platform,
  required CoreStatus status,
  required String behavior,
}) {
  if (platform == 'linux') return true;
  return behavior == 'exit';
}
