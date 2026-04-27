import 'dart:io';

import 'package:flutter/foundation.dart';

/// Append [entry] to [logFile], rotating the file when its size would
/// exceed [maxBytes] after the append.
///
/// v1.0.22 P3-B: `crash.log` previously appended without bound. A
/// tight crash loop (e.g. an unhandled exception inside a retry
/// scheduler that fires every ~100 ms) could grow the file to gigabytes
/// in minutes. This helper enforces the same shape Go-side
/// `core.log` already had: rotate to `<path>.1` (and onwards to
/// `<path>.<backups>` if requested) once the size cap trips, oldest
/// generation rolls off.
///
/// Mirrors core/hub.go:rotateLogFile naming + semantics so the
/// diagnostic-export expansion in
/// `lib/shared/log_export_sources.dart` can grow the same way for
/// crash.log later if needed.
///
/// Fail-soft: any IO error during rotation or append is swallowed —
/// the caller (typically inside an exception handler already) must
/// not be re-thrown into. Logged via [debugPrint] for development
/// visibility.
Future<void> appendWithRotation(
  File logFile,
  String entry, {
  int maxBytes = 1024 * 1024, // 1 MB default — small, focused crash trace
  int backups = 1,
}) async {
  try {
    if (await logFile.exists()) {
      final size = await logFile.length();
      // Rotate BEFORE the append so the post-write file is still
      // bounded by maxBytes. Without this an entry larger than
      // maxBytes would land in a freshly-rotated empty file (fine)
      // OR a large entry could push the live file well past maxBytes
      // before the next call notices.
      if (size + entry.length > maxBytes) {
        await _rotateGenerations(logFile.path, backups);
      }
    }
    await logFile.writeAsString(entry, mode: FileMode.append);
  } catch (e) {
    debugPrint('[RotatingLogFile] append failed: $e');
  }
}

/// Visible for tests — same routine appendWithRotation invokes.
@visibleForTesting
Future<void> rotateGenerations(String path, int backups) =>
    _rotateGenerations(path, backups);

Future<void> _rotateGenerations(String path, int backups) async {
  // Shift the historical sidecars: .(backups-1) → .backups, …,
  // .1 → .2. Oldest generation (now at .backups) rolls off because
  // the destination is overwritten.
  for (var i = backups - 1; i >= 1; i--) {
    final src = File('$path.$i');
    final dst = File('$path.${i + 1}');
    if (await src.exists()) {
      try {
        if (await dst.exists()) await dst.delete();
        await src.rename(dst.path);
      } catch (e) {
        debugPrint('[RotatingLogFile] shift $i→${i + 1} failed: $e');
      }
    }
  }
  // Rename the live file to .1 (or just delete it if backups == 0,
  // which discards the rotated content entirely — only useful when
  // the caller wants a hard size cap and doesn't need history).
  final live = File(path);
  if (!await live.exists()) return;
  if (backups <= 0) {
    try {
      await live.delete();
    } catch (e) {
      debugPrint('[RotatingLogFile] live delete failed: $e');
    }
    return;
  }
  final firstBackup = File('$path.1');
  try {
    if (await firstBackup.exists()) await firstBackup.delete();
    await live.rename(firstBackup.path);
  } catch (e) {
    debugPrint('[RotatingLogFile] live→.1 failed: $e');
  }
}
