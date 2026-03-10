import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'settings_service.dart';

/// WebDAV-based sync for profiles and settings.
///
/// Uploads/downloads two files:
///   {webdav_url}/yuelink/profiles.json  — subscription index
///   {webdav_url}/yuelink/settings.json  — app settings
class WebDavService {
  WebDavService._();
  static final instance = WebDavService._();

  static const _remotePath = 'yuelink';

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
    return http.Response.fromStream(await req.send());
  }

  /// Upload profiles and settings to WebDAV.
  Future<void> upload() async {
    final cfg = await SettingsService.getWebDavConfig();
    final url = cfg['url']!;
    if (url.isEmpty) throw Exception('WebDAV URL not configured');

    final h = _authHeaders(cfg['username']!, cfg['password']!);
    final appDir = await getApplicationSupportDirectory();

    // Ensure remote directory exists
    await _request('MKCOL', _uri(url, ''), headers: h);

    for (final name in ['profiles.json', 'settings.json']) {
      final file = File('${appDir.path}/$name');
      if (!await file.exists()) continue;
      final resp = await _request('PUT', _uri(url, name),
          headers: h, body: await file.readAsBytes());
      if (resp.statusCode >= 400) {
        throw Exception('Upload $name failed: ${resp.statusCode}');
      }
    }
  }

  /// Download profiles and settings from WebDAV.
  Future<void> download() async {
    final cfg = await SettingsService.getWebDavConfig();
    final url = cfg['url']!;
    if (url.isEmpty) throw Exception('WebDAV URL not configured');

    final h = _authHeaders(cfg['username']!, cfg['password']!);
    final appDir = await getApplicationSupportDirectory();

    for (final name in ['settings.json', 'profiles.json']) {
      final resp = await http.get(_uri(url, name), headers: h);
      if (resp.statusCode == 200) {
        await File('${appDir.path}/$name').writeAsBytes(resp.bodyBytes);
      }
    }
    // Invalidate settings cache so the new values load on next access
    SettingsService.invalidateCache();
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
    } catch (_) {
      return false;
    }
  }
}
