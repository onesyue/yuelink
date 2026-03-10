import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Manages mihomo GeoIP / GeoSite database files.
///
/// mihomo requires these files for rule-based routing to work correctly.
/// They are stored in the app's support directory and updated on demand.
class GeoResourceService {
  GeoResourceService._();
  static final instance = GeoResourceService._();

  static const _kTimeout = Duration(seconds: 60);

  static const _resources = <String, String>{
    'geoip.dat': 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat',
    'geosite.dat': 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat',
    'country.mmdb': 'https://github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb',
  };

  Future<Directory> _getDir() async {
    final appDir = await getApplicationSupportDirectory();
    return appDir;
  }

  /// Metadata for a single geo resource file.
  Future<GeoFileInfo> getInfo(String fileName) async {
    final dir = await _getDir();
    final file = File('${dir.path}/$fileName');
    if (!await file.exists()) {
      return GeoFileInfo(name: fileName, exists: false);
    }
    final stat = await file.stat();
    return GeoFileInfo(
      name: fileName,
      exists: true,
      size: stat.size,
      modified: stat.modified,
    );
  }

  /// Info for all tracked geo resources.
  Future<List<GeoFileInfo>> getAllInfo() async {
    return Future.wait(_resources.keys.map(getInfo));
  }

  /// Download / update a single resource file.
  /// Returns true on success.
  Future<bool> update(String fileName) async {
    final url = _resources[fileName];
    if (url == null) return false;

    final dir = await _getDir();
    final tmpFile = File('${dir.path}/$fileName.tmp');

    try {
      final resp = await http.get(Uri.parse(url)).timeout(_kTimeout);
      if (resp.statusCode != 200) return false;
      await tmpFile.writeAsBytes(resp.bodyBytes);
      await tmpFile.rename('${dir.path}/$fileName');
      return true;
    } catch (_) {
      if (await tmpFile.exists()) await tmpFile.delete();
      return false;
    }
  }

  /// Update all geo resources in parallel.
  /// Returns a map of fileName → success.
  Future<Map<String, bool>> updateAll() async {
    final results = await Future.wait(
      _resources.keys.map((name) async => MapEntry(name, await update(name))),
    );
    return Map.fromEntries(results);
  }

  /// List of resource names managed by this service.
  List<String> get resourceNames => _resources.keys.toList();
}

class GeoFileInfo {
  final String name;
  final bool exists;
  final int size; // bytes
  final DateTime? modified;

  const GeoFileInfo({
    required this.name,
    required this.exists,
    this.size = 0,
    this.modified,
  });

  String get sizeFormatted {
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
