import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Ensures GeoIP/GeoSite data files exist in the mihomo home directory.
///
/// mihomo's own InitGeoIP/InitGeoSite also download on demand during rule
/// parsing, but that blocks core startup with no user-visible progress.
/// Pre-downloading in Dart lets us show a loading indicator and handle
/// failures gracefully before the core even starts.
class GeoDataService {
  GeoDataService._();

  /// Files required for geodata-mode: true.
  /// Keys are filenames in the mihomo homeDir, values are CDN URLs.
  static const _requiredFiles = {
    'GeoIP.dat':
        'https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat',
    'GeoSite.dat':
        'https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat',
    'country.mmdb':
        'https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb',
    'ASN.mmdb':
        'https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/GeoLite2-ASN.mmdb',
  };

  /// Check which geo files are missing.
  static Future<List<String>> missingFiles() async {
    final appDir = await getApplicationSupportDirectory();
    final missing = <String>[];
    for (final name in _requiredFiles.keys) {
      final file = File('${appDir.path}/$name');
      if (!file.existsSync() || file.lengthSync() == 0) {
        missing.add(name);
      }
    }
    return missing;
  }

  /// Download all missing geo data files.
  ///
  /// Returns the list of successfully downloaded file names.
  /// Files that already exist (and are non-empty) are skipped.
  /// Errors are logged but do not throw — the caller should check
  /// if critical files are still missing afterwards.
  static Future<List<String>> ensureFiles({
    void Function(String fileName)? onProgress,
  }) async {
    final appDir = await getApplicationSupportDirectory();
    final downloaded = <String>[];

    for (final entry in _requiredFiles.entries) {
      final file = File('${appDir.path}/${entry.key}');
      if (file.existsSync() && file.lengthSync() > 0) continue;

      onProgress?.call(entry.key);
      debugPrint('[GeoData] Downloading ${entry.key}...');

      try {
        final response = await http.get(
          Uri.parse(entry.value),
          headers: {'User-Agent': 'clash.meta'},
        ).timeout(const Duration(minutes: 10));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await file.writeAsBytes(response.bodyBytes);
          debugPrint('[GeoData] ${entry.key} OK '
              '(${(response.bodyBytes.length / 1024 / 1024).toStringAsFixed(1)} MB)');
          downloaded.add(entry.key);
        } else {
          debugPrint('[GeoData] ${entry.key} failed: '
              'HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes');
        }
      } catch (e) {
        debugPrint('[GeoData] ${entry.key} error: $e');
      }
    }

    return downloaded;
  }
}
