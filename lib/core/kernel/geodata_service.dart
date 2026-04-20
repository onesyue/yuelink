import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../shared/error_logger.dart';
import '../../shared/event_log.dart';

/// Ensures GeoIP/GeoSite data files exist in the mihomo home directory.
///
/// Strategy:
/// 1. **Bundled assets** (primary) — geo files are packaged in the APK/IPA
///    during CI build. Copied to mihomo homeDir on first launch. Zero network
///    dependency, guarantees GEOIP/GEOSITE rules work immediately.
/// 2. **CDN download** (fallback) — if an asset is missing (dev builds without
///    geo files), tries downloading from multiple CDN mirrors.
/// 3. **mihomo auto-update** — `geo-auto-update: true` in config keeps files
///    fresh after initial setup.
class GeoDataService {
  GeoDataService._();

  /// Geo files: local filename → asset path.
  static const _bundledFiles = {
    'GeoIP.dat': 'assets/geodata/GeoIP.dat',
    'GeoSite.dat': 'assets/geodata/GeoSite.dat',
    'country.mmdb': 'assets/geodata/country.mmdb',
    'ASN.mmdb': 'assets/geodata/ASN.mmdb',
  };

  /// CDN mirrors for fallback download (when assets are not bundled).
  static const _mirrors = [
    'https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release',
    'https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release',
    'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest',
  ];

  /// Remote filename mapping (may differ from local names).
  static const _remoteNames = {
    'GeoIP.dat': 'geoip.dat',
    'GeoSite.dat': 'geosite.dat',
    'country.mmdb': 'country.mmdb',
    'ASN.mmdb': 'GeoLite2-ASN.mmdb',
  };

  /// Ensure all geo files exist in the mihomo home directory.
  ///
  /// 1. Copies from bundled assets (instant, no network)
  /// 2. Falls back to CDN download if asset not available
  /// Returns list of files that were installed.
  static Future<List<String>> ensureFiles() async {
    final appDir = await getApplicationSupportDirectory();
    final installed = <String>[];

    for (final entry in _bundledFiles.entries) {
      final localName = entry.key;
      final assetPath = entry.value;
      final destFile = File('${appDir.path}/$localName');

      // Skip if file already exists and is non-empty
      if (destFile.existsSync() && destFile.lengthSync() > 1024) continue;

      // Try 1: Copy from bundled asset
      if (await _copyFromAsset(assetPath, destFile)) {
        debugPrint('[GeoData] $localName copied from asset '
            '(${(destFile.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB)');
        installed.add(localName);
        continue;
      }

      // Try 2: Download from CDN mirrors
      debugPrint('[GeoData] $localName not in assets, trying CDN...');
      final remoteName = _remoteNames[localName] ?? localName;
      if (await _downloadFromMirrors(remoteName, destFile)) {
        debugPrint('[GeoData] $localName downloaded from CDN '
            '(${(destFile.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB)');
        installed.add(localName);
      } else {
        debugPrint('[GeoData] $localName FAILED — mihomo will retry at startup');
      }
    }

    if (installed.isNotEmpty) {
      debugPrint('[GeoData] Installed ${installed.length} files: $installed');
    }
    return installed;
  }

  /// Copy a bundled asset to a destination file.
  /// Returns false if the asset doesn't exist (e.g., dev builds).
  static Future<bool> _copyFromAsset(String assetPath, File dest) async {
    try {
      final data = await rootBundle.load(assetPath);
      await dest.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return true;
    } catch (e) {
      debugPrint('[GeoData] copyFromAsset failed: $e');
      EventLog.write('[Geodata] asset_copy_miss path=$assetPath err=$e');
      return false;
    }
  }

  /// Try downloading from CDN mirrors. First success wins.
  /// Total timeout: 60 seconds. Uses a write guard to prevent concurrent
  /// writes to the same file from parallel mirror downloads.
  static Future<bool> _downloadFromMirrors(
      String remoteName, File dest) async {
    try {
      final completer = Completer<bool>();
      var remaining = _mirrors.length;
      var written = false; // Guard: only the first successful download writes

      for (final mirror in _mirrors) {
        _tryDownload('$mirror/$remoteName', dest, () => written, () {
          written = true;
        }).then((ok) {
          if (ok && !completer.isCompleted) {
            completer.complete(true);
          } else {
            remaining--;
            if (remaining == 0 && !completer.isCompleted) {
              completer.complete(false);
            }
          }
        });
      }

      return await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => false,
      );
    } catch (e, st) {
      debugPrint('[GeoData] downloadFromMirrors failed: $e');
      ErrorLogger.captureException(e, st,
          source: 'GeodataService._downloadFromMirrors');
      return false;
    }
  }

  /// Force-download all geo files from CDN mirrors, overwriting existing files.
  ///
  /// Used for the "Update Now" button in Settings. Skips bundled assets and
  /// goes directly to CDN so the user always gets the latest version.
  /// Returns true only when all 4 files were successfully downloaded.
  static Future<bool> forceUpdate() async {
    final appDir = await getApplicationSupportDirectory();
    // Download to temp files first, then replace — avoids losing existing geo
    // files if CDN is unreachable (which would break core startup).
    int downloaded = 0;
    for (final entry in _remoteNames.entries) {
      final tmpFile = File('${appDir.path}/${entry.key}.tmp');
      if (await _downloadFromMirrors(entry.value, tmpFile)) {
        // Replace existing file only after successful download
        final destFile = File('${appDir.path}/${entry.key}');
        try {
          await tmpFile.rename(destFile.path);
        } catch (e) {
          debugPrint('[GeoData] rename failed, falling back to copy+delete: $e');
          EventLog.write('[Geodata] rename_fallback file=${entry.key} err=$e');
          // rename may fail cross-device; fallback to copy+delete
          await tmpFile.copy(destFile.path);
          await tmpFile.delete();
        }
        downloaded++;
      } else {
        // Clean up failed temp file
        try { if (tmpFile.existsSync()) await tmpFile.delete(); } catch (e) { debugPrint('[GeoData] tmp cleanup failed: $e'); EventLog.write('[Geodata] tmp_cleanup_failed file=${entry.key} err=$e'); }
      }
    }
    return downloaded == _remoteNames.length;
  }

  /// Returns the last-modified time of GeoIP.dat, or null if not present.
  static Future<DateTime?> lastUpdated() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final file = File('${appDir.path}/GeoIP.dat');
      if (!file.existsSync()) return null;
      return file.lastModifiedSync();
    } catch (e, st) {
      debugPrint('[GeoData] lastUpdated failed: $e');
      ErrorLogger.captureException(e, st,
          source: 'GeodataService.lastUpdated');
      return null;
    }
  }

  static Future<bool> _tryDownload(
    String url,
    File dest, [
    bool Function()? isWritten,
    void Function()? markWritten,
  ]) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'clash.meta'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.bodyBytes.length > 1024) {
        // Checksum verification against sidecar `.sha256sum` on the same
        // mirror. Fail-soft: a missing sidecar is logged but accepted (some
        // China CDNs don't mirror the sidecar); a PRESENT sidecar that
        // disagrees with the bytes is a hard fail and forces the outer loop
        // to try the next mirror — that's the MITM / corruption signal.
        final verdict = await _verifyMirrorChecksum(url, response.bodyBytes);
        if (verdict == _ChecksumVerdict.mismatch) {
          // Hard fail — bytes don't match the sidecar. Caller loops on.
          return false;
        }

        // Check if another mirror already wrote the file
        if (isWritten != null && isWritten()) return true;
        if (dest.existsSync() && dest.lengthSync() > 1024) return true;
        markWritten?.call();
        await dest.writeAsBytes(response.bodyBytes, flush: true);
        return true;
      }
    } catch (e) {
      debugPrint('[GeoData] download failed ($url): $e');
      EventLog.write('[Geodata] mirror_download_failed url=$url err=$e');
    }
    return false;
  }

  /// Fetch `<url>.sha256sum` from the same mirror and compare against the
  /// SHA-256 of [bytes]. Three outcomes:
  ///   * [_ChecksumVerdict.ok]       — sidecar present and digest matches.
  ///   * [_ChecksumVerdict.mismatch] — sidecar present and digest disagrees
  ///                                   (corruption / MITM). Hard fail.
  ///   * [_ChecksumVerdict.skipped]  — sidecar unreachable or unparseable.
  ///                                   Fail-soft: accept the file.
  static Future<_ChecksumVerdict> _verifyMirrorChecksum(
      String url, Uint8List bytes) async {
    final sumUrl = '$url.sha256sum';
    String sumBody;
    try {
      final sumResp = await http.get(
        Uri.parse(sumUrl),
        headers: {'User-Agent': 'clash.meta'},
      ).timeout(const Duration(seconds: 15));
      if (sumResp.statusCode != 200 || sumResp.body.trim().isEmpty) {
        EventLog.write(
            '[Geodata] checksum_skipped mirror=$sumUrl reason=http_${sumResp.statusCode}');
        return _ChecksumVerdict.skipped;
      }
      sumBody = sumResp.body;
    } catch (e) {
      EventLog.write('[Geodata] checksum_skipped mirror=$sumUrl reason=$e');
      return _ChecksumVerdict.skipped;
    }

    final expected = _parseSha256Line(sumBody);
    if (expected == null) {
      EventLog.write(
          '[Geodata] checksum_skipped mirror=$sumUrl reason=unparseable');
      return _ChecksumVerdict.skipped;
    }

    final actual = sha256.convert(bytes).toString();
    if (actual.toLowerCase() == expected.toLowerCase()) {
      EventLog.write(
          '[Geodata] checksum_ok mirror=$url len=${bytes.length} sha=$actual');
      return _ChecksumVerdict.ok;
    }

    // Mismatch is a real corruption/MITM signal — elevate to ErrorLogger
    // so it shows up in crash.log and the server aggregator.
    final err = StateError(
        '[Geodata] checksum mismatch url=$url expected=$expected actual=$actual');
    ErrorLogger.captureException(err, StackTrace.current,
        source: 'GeodataService._verifyMirrorChecksum');
    return _ChecksumVerdict.mismatch;
  }

  /// Parse a GNU `sha256sum` output line.
  ///
  /// Canonical format (one or many lines): `<64 hex chars><whitespace><name>`.
  /// We accept any line whose first token is 64 hex chars. Case-insensitive.
  /// Returns null when no line matches. Exposed via [verifyChecksumForTest]
  /// so unit tests don't need to spin up an HTTP server.
  @visibleForTesting
  static String? parseSha256Line(String body) => _parseSha256Line(body);

  static String? _parseSha256Line(String body) {
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      // Grab the first whitespace-separated token.
      final token = line.split(RegExp(r'\s+')).first;
      if (token.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token)) {
        return token;
      }
    }
    return null;
  }

  /// Test hook: pure verification without any network I/O.
  ///
  /// Returns true iff [digestLine] (raw contents of a `.sha256sum` sidecar)
  /// parses to a 64-hex digest that matches `sha256(bytes)`. False when
  /// parsing fails OR the digest disagrees — unit tests exercise both paths.
  @visibleForTesting
  static bool verifyChecksumForTest(List<int> bytes, String digestLine) {
    final expected = _parseSha256Line(digestLine);
    if (expected == null) return false;
    final actual = sha256.convert(bytes).toString();
    return actual.toLowerCase() == expected.toLowerCase();
  }
}

enum _ChecksumVerdict { ok, mismatch, skipped }
