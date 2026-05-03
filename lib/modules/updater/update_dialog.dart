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
    if (Platform.isMacOS || Platform.isWindows) {
      final uri = Uri.file(path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await Process.run('cmd', ['/c', 'start', '', path]);
      }
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
