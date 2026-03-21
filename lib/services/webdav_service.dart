import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/storage/settings_service.dart';

/// WebDAV-based sync for profiles, settings, and subscription config files.
///
/// Uploads/downloads:
///   {webdav_url}/yuelink/profiles.json   — subscription index
///   {webdav_url}/yuelink/settings.json   — app settings
///   {webdav_url}/yuelink/configs/*.yaml  — subscription config files
class WebDavService {
  WebDavService._();
  static final instance = WebDavService._();

  static const _remotePath = 'yuelink';
  static const _configsDir = 'configs';
  static const _kTimeout = Duration(seconds: 30);

  Map<String, String> _authHeaders(String username, String password) {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return {
      'Authorization': 'Basic $credentials',
      'Content-Type': 'application/octet-stream',
    };
  }

  Uri _uri(String baseUrl, String file) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(
        file.isEmpty ? '$base$_remotePath/' : '$base$_remotePath/$file');
  }

  Future<http.Response> _request(String method, Uri url,
      {Map<String, String>? headers, List<int>? body}) async {
    final req = http.Request(method, url);
    if (headers != null) req.headers.addAll(headers);
    if (body != null) req.bodyBytes = body;
    final streamedResponse =
        await req.send().timeout(_kTimeout);
    return http.Response.fromStream(streamedResponse);
  }

  /// Upload profiles, settings, and all subscription configs to WebDAV.
  Future<void> upload() async {
    final cfg = await SettingsService.getWebDavConfig();
    final url = cfg['url']!;
    if (url.isEmpty) throw Exception('WebDAV URL not configured');

    final h = _authHeaders(cfg['username']!, cfg['password']!);
    final appDir = await getApplicationSupportDirectory();

    // Ensure remote base directory exists
    await _request('MKCOL', _uri(url, ''), headers: h);

    // Upload index files
    for (final name in ['profiles.json', 'settings.json']) {
      final file = File('${appDir.path}/$name');
      if (!await file.exists()) continue;
      final resp = await _request('PUT', _uri(url, name),
          headers: h, body: await file.readAsBytes());
      if (resp.statusCode >= 400) {
        throw Exception('Upload $name failed: HTTP ${resp.statusCode}');
      }
    }

    // Ensure remote configs sub-directory exists
    await _request('MKCOL', _uri(url, '$_configsDir/'), headers: h);

    // Upload all config YAML files
    final configsDir = Directory('${appDir.path}/$_configsDir');
    if (await configsDir.exists()) {
      await for (final entity in configsDir.list()) {
        if (entity is! File) continue;
        final fileName = entity.uri.pathSegments.last;
        if (!fileName.endsWith('.yaml')) continue;
        final resp = await _request(
          'PUT',
          _uri(url, '$_configsDir/$fileName'),
          headers: h,
          body: await entity.readAsBytes(),
        );
        if (resp.statusCode >= 400) {
          throw Exception('Upload config $fileName failed: HTTP ${resp.statusCode}');
        }
      }
    }
  }

  /// Download profiles, settings, and subscription configs from WebDAV.
  Future<void> download() async {
    final cfg = await SettingsService.getWebDavConfig();
    final url = cfg['url']!;
    if (url.isEmpty) throw Exception('WebDAV URL not configured');

    final h = _authHeaders(cfg['username']!, cfg['password']!);
    final appDir = await getApplicationSupportDirectory();

    // Download index files — download profiles.json first so settings.json
    // invalidation doesn't leave a stale-read window.
    for (final name in ['profiles.json', 'settings.json']) {
      final resp = await _request('GET', _uri(url, name), headers: h);
      if (resp.statusCode == 200) {
        await File('${appDir.path}/$name').writeAsBytes(resp.bodyBytes);
      }
    }

    // Invalidate settings cache AFTER writing settings.json
    SettingsService.invalidateCache();

    // Download config YAML files by reading the profiles index
    final profilesFile = File('${appDir.path}/profiles.json');
    if (await profilesFile.exists()) {
      try {
        final list =
            (jsonDecode(await profilesFile.readAsString()) as List);
        final configsDir = Directory('${appDir.path}/$_configsDir');
        await configsDir.create(recursive: true);

        for (final item in list) {
          final id = (item as Map<String, dynamic>)['id'] as String?;
          if (id == null) continue;
          final fileName = '$id.yaml';
          final resp = await _request(
            'GET',
            _uri(url, '$_configsDir/$fileName'),
            headers: h,
          );
          if (resp.statusCode == 200) {
            await File('${configsDir.path}/$fileName')
                .writeAsBytes(resp.bodyBytes);
          }
        }
      } catch (e) {
        debugPrint('[WebdavService] profiles.json parse failed: $e');
      }
    }
  }

  /// Test WebDAV connection. Returns true if reachable.
  Future<bool> testConnection() async {
    final cfg = await SettingsService.getWebDavConfig();
    final url = cfg['url']!;
    if (url.isEmpty) return false;
    try {
      final base = url.endsWith('/') ? url : '$url/';
      final resp = await http
          .head(Uri.parse(base),
              headers: _authHeaders(cfg['username']!, cfg['password']!))
          .timeout(const Duration(seconds: 5));
      return resp.statusCode < 400;
    } catch (e) {
      debugPrint('[WebdavService] testConnection failed: $e');
      return false;
    }
  }
}
