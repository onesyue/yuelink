import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/env_config.dart';
import '../core/storage/settings_service.dart';

/// Checks GitHub releases for a newer version of YueLink.
///
/// Only active when [EnvConfig.isStandalone] is true. Store builds
/// (App Store / Google Play) must not contain self-update logic.
class UpdateChecker {
  UpdateChecker._();
  static final instance = UpdateChecker._();

  static const _repoApi =
      'https://api.github.com/repos/onesyue/yuelink/releases/latest';

  /// Check for updates. Returns null if already on latest, check fails,
  /// version was skipped by user, or running in store mode.
  Future<UpdateInfo?> check({bool ignoreSkipped = false}) async {
    if (!EnvConfig.isStandalone) return null;

    try {
      final response = await http.get(
        Uri.parse(_repoApi),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final latestTag = data['tag_name'] as String? ?? '';
      final body = data['body'] as String? ?? '';
      final htmlUrl = data['html_url'] as String? ?? '';
      final publishedAt = data['published_at'] as String?;

      final latestVersion = latestTag.replaceFirst(RegExp(r'^v'), '');
      if (latestVersion.isEmpty) return null;

      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      if (!_isNewer(latestVersion, currentVersion)) return null;

      // Check if user has skipped this specific version
      if (!ignoreSkipped) {
        final skipped = await SettingsService.get<String>('skippedVersion');
        if (skipped == latestVersion) return null;
      }

      // Parse assets for direct download URL
      final assets = data['assets'] as List<dynamic>? ?? [];
      final downloadUrl = _findAssetUrl(assets);

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseNotes: body,
        releaseUrl: htmlUrl,
        downloadUrl: downloadUrl,
        publishedAt: publishedAt != null ? DateTime.tryParse(publishedAt) : null,
      );
    } catch (e) {
      debugPrint('[UpdateChecker] check failed: $e');
      return null;
    }
  }

  /// Mark a version as skipped — won't prompt again for this version.
  static Future<void> skipVersion(String version) async {
    await SettingsService.set('skippedVersion', version);
  }

  /// Clear skipped version (e.g., on manual "check for updates" tap).
  static Future<void> clearSkipped() async {
    await SettingsService.set('skippedVersion', null);
  }

  /// Find the download URL for the current platform from release assets.
  static String? _findAssetUrl(List<dynamic> assets) {
    final suffix = _platformSuffix();
    if (suffix == null) return null;

    for (final asset in assets) {
      final name = (asset as Map<String, dynamic>)['name'] as String? ?? '';
      if (name.toLowerCase().contains(suffix.toLowerCase())) {
        return asset['browser_download_url'] as String?;
      }
    }
    return null;
  }

  /// Returns the expected asset filename suffix for the current platform.
  static String? _platformSuffix() {
    if (Platform.isAndroid) return '.apk';
    if (Platform.isMacOS) return '.dmg';
    if (Platform.isWindows) return 'Setup.exe';
    if (Platform.isIOS) return '.ipa';
    return null;
  }

  /// Download update file with progress callback.
  /// Returns the local file path on success.
  static Future<String> download(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    IOSink? sink;
    File? file;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total = response.contentLength;
      final fileName = Uri.parse(url).pathSegments.last;
      final dir = await getTemporaryDirectory();
      file = File('${dir.path}/$fileName');

      sink = file.openWrite();
      var received = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }

      await sink.flush();
      await sink.close();
      sink = null; // mark as successfully closed
      return file.path;
    } catch (e) {
      // Close sink and delete partial file on failure
      try { await sink?.close(); } catch (e) { debugPrint('[UpdateChecker] sink close error: $e'); }
      try { if (file != null && file.existsSync()) file.deleteSync(); } catch (e) { debugPrint('[UpdateChecker] partial file cleanup error: $e'); }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Returns true if [candidate] is semantically newer than [current].
  static bool _isNewer(String candidate, String current) {
    final c = _parse(candidate);
    final cur = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (c[i] > cur[i]) return true;
      if (c[i] < cur[i]) return false;
    }
    return false;
  }

  static List<int> _parse(String v) {
    final parts = v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) { parts.add(0); }
    return parts;
  }
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String releaseUrl;
  final String? downloadUrl;
  final DateTime? publishedAt;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.releaseUrl,
    this.downloadUrl,
    this.publishedAt,
  });
}
