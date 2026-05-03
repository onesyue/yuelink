import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/app_strings.dart';
import '../../shared/app_notifier.dart';
import '../../shared/rich_content.dart';
import '../../theme.dart';
import 'update_checker.dart';

/// Show the version-up dialog for [info]. Used both from Settings →
/// Check Updates AND from the launch-time toast tap handler in
/// `main.dart` (issue #4 — make the "new version" capsule actionable
/// instead of forcing the user back into Settings to act on it).
///
/// Self-contained: takes a single BuildContext (any Material ancestor
/// works — `navigatorKey.currentContext` is fine) and the
/// [UpdateInfo] payload returned by `UpdateChecker.check`.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  final s = S.of(context);
  var downloading = false;
  double progress = 0;
  String? error;

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) {
        return AlertDialog(
          title: Text('${s.updateAvailable} v${info.latestVersion}'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (info.releaseNotes.isNotEmpty) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: RichContent(
                        content: info.releaseNotes,
                        textStyle: YLText.body.copyWith(
                          color: YLColors.zinc500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (downloading) ...[
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress > 0
                        ? '${(progress * 100).toStringAsFixed(0)}%'
                        : s.updateDownloading,
                    style: YLText.caption.copyWith(color: YLColors.zinc500),
                  ),
                ],
                if (error != null) ...[
                  Text(
                    error!,
                    style: YLText.caption.copyWith(color: YLColors.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: downloading ? null : () => Navigator.pop(ctx),
              child: Text(s.cancel),
            ),
            if (info.downloadUrl != null)
              FilledButton(
                onPressed: downloading
                    ? null
                    : () async {
                        setDialog(() {
                          downloading = true;
                          error = null;
                          progress = 0;
                        });
                        try {
                          // Pass the manifest's sha256 so the downloaded
                          // file is verified against tampering. If the
                          // hash mismatches, download() throws and the
                          // partial file is deleted.
                          final path = await UpdateChecker.download(
                            info.downloadUrl!,
                            expectedSha256: info.sha256,
                            onProgress: (received, total) {
                              if (total > 0) {
                                setDialog(() => progress = received / total);
                              }
                            },
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _openDownloadedUpdate(info, path);
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialog(() {
                              downloading = false;
                              error = '${s.updateDownloadFailed}: $e';
                            });
                          }
                        }
                      },
                child: Text(s.updateDownload),
              )
            else
              // Fallback: open GitHub release page if no asset found
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse(info.releaseUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                child: Text(s.updateDownload),
              ),
          ],
        );
      },
    ),
  );
}

Future<void> _openDownloadedUpdate(UpdateInfo info, String path) async {
  final s = S.current;
  try {
    if (Platform.isAndroid) {
      const channel = MethodChannel('com.yueto.yuelink/vpn');
      await channel.invokeMethod('installApk', {'path': path});
      AppNotifier.success(s.updateInstalling);
      return;
    }
    if (Platform.isMacOS) {
      // Auto-install path: mount the DMG, copy YueLink.app over the
      // running bundle, unmount, schedule a relaunch, exit. Falls back
      // to "just open the DMG and let the user drag it" on any failure
      // (non-/Applications install, missing .app inside DMG, hdiutil
      // unavailable, etc.) so the worst case still matches the
      // pre-fix behaviour rather than leaving the user stranded.
      final autoOk = await _macosInstallFromDmg(path);
      if (autoOk) return;
      // Fallback: open the DMG so the user can drag manually.
      await _openWithDefaultHandler(path);
      AppNotifier.info(s.updateInstalling);
      return;
    }
    if (Platform.isWindows) {
      // Windows installer (.exe via Inno Setup) is the user-facing
      // experience here. Could shell out with /SILENT for invisible
      // install, but a silent rewrite of the running app is more
      // surprising than helpful — let the installer surface itself.
      await _openWithDefaultHandler(path);
      AppNotifier.success(s.updateInstalling);
      return;
    }
    if (Platform.isLinux) {
      // .deb / .rpm / .AppImage — let the desktop environment pick the
      // right tool (gdebi / gnome-software / dnfdragora / file manager).
      // xdg-open is the universal entry point on Linux desktops.
      final result = await Process.run('xdg-open', [path]);
      if (result.exitCode != 0) {
        throw ProcessException(
          'xdg-open',
          [path],
          result.stderr.toString().trim(),
          result.exitCode,
        );
      }
      AppNotifier.success(s.updateInstalling);
      return;
    }
    if (Platform.isIOS) {
      // iOS can't sideload .ipa files from inside another app — App Store
      // and TrollStore are the only install paths. Open the GitHub
      // release page so the user can do it manually.
      if (info.releaseUrl.isNotEmpty) {
        await launchUrl(
          Uri.parse(info.releaseUrl),
          mode: LaunchMode.externalApplication,
        );
        AppNotifier.info(s.installIpaHint);
        return;
      }
      AppNotifier.error(s.installIosManual);
      return;
    }
    AppNotifier.error(s.installUnsupported);
  } catch (e) {
    AppNotifier.error('${s.updateDownloadFailed}: $e');
  }
}

/// Open [path] with the OS default handler (Finder on macOS, shell on
/// Windows). `launchUrl(file://…)` is the preferred path; falls through
/// to `open` / `start` only if launchUrl rejects the URI (rare on
/// modern Flutter, but kept for resilience on Linux/older macOS).
Future<void> _openWithDefaultHandler(String path) async {
  final uri = Uri.file(path);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
    return;
  }
  if (Platform.isMacOS) {
    await Process.run('open', [path]);
    return;
  }
  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', path]);
    return;
  }
}

/// macOS auto-install pipeline. Returns true on success (caller should
/// stop — relaunch is in flight), false to fall back to "just open the
/// DMG" so the user can finish manually.
///
/// Steps (each one yields a clean rollback):
///   1. Resolve the running .app bundle path from
///      [Platform.resolvedExecutable].
///   2. `hdiutil attach -nobrowse -noautoopen` the DMG → captured
///      mount point.
///   3. Locate `YueLink.app` at the mount root.
///   4. Atomic-ish swap onto /Applications (or wherever the running
///      bundle lives): rsync into a sibling dir, swap with mv, blow
///      away the old.
///   5. `hdiutil detach`.
///   6. Strip com.apple.quarantine off the new bundle so Gatekeeper
///      doesn't re-prompt for password (the auto-repair flow handles
///      it on next launch too, but skipping the dialog is nicer).
///   7. Spawn a detached `sleep 1; open <bundle>` so the relaunch
///      survives [exit].
///   8. Quit current process via `exit(0)`.
///
/// Bails on the very first failure — never partially writes into the
/// running bundle.
Future<bool> _macosInstallFromDmg(String dmgPath) async {
  if (!Platform.isMacOS) return false;
  String? mountPoint;
  try {
    final bundlePath = _runningMacAppBundle();
    if (bundlePath == null) {
      debugPrint(
        '[Updater] macOS auto-install: not running from a .app bundle '
        '(probably flutter run / debug) — falling back to manual open',
      );
      return false;
    }

    // Step 2: mount.
    final attach = await Process.run('hdiutil', [
      'attach',
      '-nobrowse',
      '-noautoopen',
      '-readonly',
      '-plist',
      dmgPath,
    ]);
    if (attach.exitCode != 0) {
      debugPrint('[Updater] hdiutil attach failed: ${attach.stderr}');
      return false;
    }
    mountPoint = _parseHdiutilMountPoint(attach.stdout as String);
    if (mountPoint == null || !Directory(mountPoint).existsSync()) {
      debugPrint('[Updater] could not parse mount point from hdiutil plist');
      return false;
    }

    // Step 3: locate the .app inside the mount.
    final mountedApp = Directory('$mountPoint/YueLink.app');
    if (!mountedApp.existsSync()) {
      debugPrint('[Updater] no YueLink.app at mount root $mountPoint');
      return false;
    }

    // Step 4: stage + swap. Stage path = "<bundlePath>.new"; final
    // swap = mv old aside, mv new into place, rm aside. macOS won't
    // let us rm the running bundle while it's executing, but moving
    // it works.
    final stagedPath = '$bundlePath.new-${DateTime.now().millisecondsSinceEpoch}';
    final ditto = await Process.run('ditto', [mountedApp.path, stagedPath]);
    if (ditto.exitCode != 0) {
      debugPrint('[Updater] ditto staging failed: ${ditto.stderr}');
      try {
        if (Directory(stagedPath).existsSync()) {
          Directory(stagedPath).deleteSync(recursive: true);
        }
      } catch (_) {}
      return false;
    }

    final asidePath =
        '$bundlePath.old-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await Directory(bundlePath).rename(asidePath);
    } catch (e) {
      debugPrint('[Updater] move-aside running bundle failed: $e');
      try {
        Directory(stagedPath).deleteSync(recursive: true);
      } catch (_) {}
      return false;
    }

    try {
      await Directory(stagedPath).rename(bundlePath);
    } catch (e) {
      debugPrint('[Updater] swap-in new bundle failed: $e');
      // Roll the running bundle back so we don't strand the user.
      try {
        await Directory(asidePath).rename(bundlePath);
      } catch (_) {}
      return false;
    }

    // Step 6: clean off quarantine — best-effort, not fatal.
    try {
      await Process.run('xattr', ['-dr', 'com.apple.quarantine', bundlePath]);
    } catch (_) {}

    // Step 5 (deferred until after swap): unmount.
    try {
      await Process.run('hdiutil', ['detach', '-quiet', mountPoint]);
    } catch (_) {}
    mountPoint = null;

    // Best-effort cleanup of the moved-aside old bundle. Failure is
    // benign — leftover .old-* dirs can be cleaned up by the user, and
    // the next update will move-aside again with a fresh timestamp.
    try {
      await Directory(asidePath).delete(recursive: true);
    } catch (e) {
      debugPrint('[Updater] old-bundle cleanup failed (benign): $e');
    }

    // Step 7: spawn detached relaunch script.
    await Process.start(
      'sh',
      [
        '-c',
        // 0.8 s gives our exit() time to release window/tray
        // resources; `open -n` allows a fresh process if a stale
        // tray icon were still hanging around.
        'sleep 0.8; /usr/bin/open "$bundlePath"',
      ],
      mode: ProcessStartMode.detached,
    );

    AppNotifier.success(S.current.updateInstalling);

    // Step 8: quit. Use a small delay so the success toast has a frame
    // to render before the process disappears.
    Future<void>.delayed(const Duration(milliseconds: 200), () => exit(0));
    return true;
  } catch (e) {
    debugPrint('[Updater] macOS auto-install threw: $e');
    if (mountPoint != null) {
      try {
        await Process.run('hdiutil', ['detach', '-force', mountPoint]);
      } catch (_) {}
    }
    return false;
  }
}

/// Resolve the .app bundle path of the currently-running process.
/// Returns null when the executable isn't inside a `.app` (debug
/// `flutter run` from a build dir, raw CLI launches, etc.).
String? _runningMacAppBundle() {
  final exe = Platform.resolvedExecutable;
  // Layout: /path/to/Foo.app/Contents/MacOS/Foo
  // Walk up until we find a path ending in `.app`. Bail if we don't
  // find one within a few levels — guards against pathological loops.
  var dir = File(exe).parent;
  for (var i = 0; i < 5; i++) {
    if (dir.path.endsWith('.app')) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

/// Pull the `mount-point` value out of `hdiutil attach -plist` output.
/// The plist lists every entity created (the disk image itself, plus
/// any partitions); we want the one with a non-empty `mount-point`.
/// Plist parsing via regex is acceptable here because the format is
/// generated by hdiutil and not user-controlled.
String? _parseHdiutilMountPoint(String plist) {
  final re = RegExp(
    r'<key>mount-point</key>\s*<string>([^<]+)</string>',
    caseSensitive: false,
  );
  final m = re.firstMatch(plist);
  if (m == null) return null;
  final value = m.group(1)?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}
