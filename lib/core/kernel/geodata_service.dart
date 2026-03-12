import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
    } catch (_) {
      return false;
    }
  }

  /// Try downloading from CDN mirrors. First success wins.
  /// Total timeout: 60 seconds.
  static Future<bool> _downloadFromMirrors(
      String remoteName, File dest) async {
    try {
      final completer = Completer<bool>();
      var remaining = _mirrors.length;

      for (final mirror in _mirrors) {
        _tryDownload('$mirror/$remoteName', dest).then((ok) {
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
    } catch (_) {
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
    // Delete existing files so _tryDownload doesn't skip them
    for (final name in _bundledFiles.keys) {
      final f = File('${appDir.path}/$name');
      try {
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    int downloaded = 0;
    for (final entry in _remoteNames.entries) {
      final destFile = File('${appDir.path}/${entry.key}');
      if (await _downloadFromMirrors(entry.value, destFile)) downloaded++;
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
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _tryDownload(String url, File dest) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'clash.meta'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.bodyBytes.length > 1024) {
        if (dest.existsSync() && dest.lengthSync() > 1024) return true;
        await dest.writeAsBytes(response.bodyBytes, flush: true);
        return true;
      }
    } catch (_) {}
    return false;
  }
}
