import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

class LogExportResult {
  final bool saved;
  final bool cancelled;
  final String? path;
  final String? error;

  const LogExportResult._({
    required this.saved,
    required this.cancelled,
    this.path,
    this.error,
  });

  factory LogExportResult.savedAt(String path) =>
      LogExportResult._(saved: true, cancelled: false, path: path);
  factory LogExportResult.userCancelled() =>
      const LogExportResult._(saved: false, cancelled: true);
  factory LogExportResult.failed(String error) =>
      LogExportResult._(saved: false, cancelled: false, error: error);
}

/// Save a text/binary blob to a user-visible location on every platform.
///
/// - Android: SAF picker (Storage Access Framework) — user usually chooses
///   `Download/`. The file is written via the system content provider, so it
///   is reachable from any file manager and from Files-on-PC over USB/MTP.
/// - iOS: Files app picker — iCloud Drive / On My iPhone / third-party
///   document providers.
/// - macOS / Windows / Linux: native Save As dialog, defaulting to Downloads.
class LogExportService {
  static Future<LogExportResult> saveText({
    required String fileName,
    required String content,
    String? dialogTitle,
  }) {
    return saveBytes(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      dialogTitle: dialogTitle,
    );
  }

  static Future<LogExportResult> saveBytes({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
  }) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final path = await FilePicker.platform.saveFile(
          fileName: fileName,
          bytes: bytes,
          dialogTitle: dialogTitle,
        );
        if (path == null) return LogExportResult.userCancelled();
        return LogExportResult.savedAt(path);
      }

      String? initialDir;
      try {
        final downloads = await getDownloadsDirectory();
        initialDir = downloads?.path;
      } catch (_) {}
      final path = await FilePicker.platform.saveFile(
        fileName: fileName,
        dialogTitle: dialogTitle,
        initialDirectory: initialDir,
        bytes: bytes,
      );
      if (path == null) return LogExportResult.userCancelled();
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() == 0) {
        await file.writeAsBytes(bytes, flush: true);
      }
      return LogExportResult.savedAt(path);
    } catch (e) {
      return LogExportResult.failed(e.toString());
    }
  }
}
