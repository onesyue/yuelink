import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// In-app one-shot replacement for the DMG-shipped `fix-gatekeeper.command`.
///
/// macOS attaches `com.apple.quarantine` xattr to any app downloaded from
/// the internet (including in-app self-updates). Even after the user grants
/// "Open" once, every fresh download brings the flag back and the user
/// re-experiences "YueLink can't be opened because Apple cannot verify it".
///
/// The fix is a one-line `xattr -cr /Applications/YueLink.app`, but it
/// needs root because /Applications is system-owned. Pre-fix we shipped
/// a `.command` shell script in the DMG; users who closed the DMG window
/// after copying the app couldn't find it. This in-app surface routes
/// through `osascript … with administrator privileges`, which triggers
/// the standard macOS password dialog and runs the same command.
///
/// The `.command` script in the DMG is intentionally kept as the
/// belt-and-suspenders fallback for the "app won't even launch" case
/// (where this in-app code can't run at all).
class MacOSGatekeeper {
  MacOSGatekeeper._();

  /// Resolve the running app's `.app` bundle path.
  ///
  /// `Platform.resolvedExecutable` on macOS is
  /// `/path/to/YueLink.app/Contents/MacOS/YueLink`. We chop at `.app/`
  /// to recover the bundle root. Returns null when the binary is being
  /// run outside an `.app` (e.g. `flutter run` against a debug build) —
  /// callers should treat that as "not applicable, hide the option".
  static String? bundlePath() {
    if (!Platform.isMacOS) return null;
    final exe = Platform.resolvedExecutable;
    const marker = '.app/';
    final idx = exe.indexOf(marker);
    if (idx == -1) return null;
    // Trim the trailing slash so the path matches what the user sees in
    // Finder ("/Applications/YueLink.app").
    return exe.substring(0, idx + marker.length - 1);
  }

  /// Whether the running `.app` still carries the quarantine xattr.
  ///
  /// `xattr -p` exits 0 if the attribute exists, 1 otherwise (and other
  /// non-zero codes if xattr itself fails — treat those as "unknown,
  /// don't bother the user"). Cheap, non-privileged read.
  static Future<bool> hasQuarantine() async {
    final path = bundlePath();
    if (path == null) return false;
    try {
      final r = await Process.run(
        'xattr',
        ['-p', 'com.apple.quarantine', path],
      ).timeout(const Duration(seconds: 5));
      return r.exitCode == 0;
    } on TimeoutException {
      return false;
    } catch (e) {
      debugPrint('[Gatekeeper] hasQuarantine error: $e');
      return false;
    }
  }

  /// Run `xattr -cr <bundle>` with administrator privileges via osascript.
  ///
  /// macOS shows the standard password dialog (or Touch ID on supported
  /// hardware). On user-cancel osascript exits with code 1; on any other
  /// failure it surfaces the underlying tool's exit code. We just report
  /// success/failure — caller handles the toast.
  ///
  /// 60 s timeout covers a slow user typing their password; longer than
  /// that and the dialog has effectively been ignored, surface as a
  /// failure so the UI doesn't spin forever.
  static Future<bool> removeQuarantine() async {
    final path = bundlePath();
    if (path == null) return false;
    // Quote the path inside the inner shell command. The bundle name has
    // no spaces today but defensively escaping any `"` that snuck in
    // keeps the AppleScript well-formed for unusual install locations.
    final escaped = path.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final script =
        'do shell script "xattr -cr \\"$escaped\\"" with administrator privileges';
    try {
      final r = await Process.run('osascript', ['-e', script])
          .timeout(const Duration(seconds: 60));
      if (r.exitCode == 0) return true;
      debugPrint('[Gatekeeper] osascript exit=${r.exitCode} stderr=${r.stderr}');
      return false;
    } on TimeoutException {
      debugPrint('[Gatekeeper] removeQuarantine timed out (user idle?)');
      return false;
    } catch (e) {
      debugPrint('[Gatekeeper] removeQuarantine error: $e');
      return false;
    }
  }
}
