import '../providers/core_runtime_providers.dart';

/// Decision for the OS window-close button (X / taskbar Close / Cmd+W):
/// quit the process or hide to system tray?
///
/// v1.0.22 P0-3 narrows the previous "always honour close behaviour"
/// rule on Windows. The Win11 taskbar's right-click → Close window
/// dispatches the same window_manager `onWindowClose` callback as the
/// title-bar X, and many users have no other muscle-memory exit path
/// (no Alt+F4, no tray right-click → Quit). Pre-fix, "tray" behaviour
/// silently swallowed those clicks while the VPN kept running, and the
/// user reported "无法退出" because `yuelink.exe` lived on in Task
/// Manager indefinitely.
///
/// Rule:
///   - Linux  → always quit (no system tray to hide to in the first
///     place; the existing `onWindowClose` already had this carve-out).
///   - Windows + core running → quit. Trade-off accepted: clicking the
///     title-bar X with an active VPN now exits the app instead of
///     hiding it. Consistent with what users expect when they can see
///     the VPN status indicator and choose to close the window.
///   - Otherwise (macOS always, Windows-not-running) → respect
///     [behavior]. `'exit'` quits, anything else (including the
///     default `'tray'`) hides.
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
  if (platform == 'windows' && status == CoreStatus.running) return true;
  return behavior == 'exit';
}
