import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/env_config.dart';
import '../../core/storage/settings_service.dart';
import '../../shared/error_logger.dart';
import '../../shared/event_log.dart';

/// Checks for a newer version of YueLink, fetching an `update.json` manifest
/// from one of several mirror endpoints (CDN → ghproxy → github raw → github
/// API), so users behind GFW can still receive updates when the GitHub API is
/// blocked.
///
/// Manifest format (published as a single asset on the fixed `updater` tag):
///
///     {
///       "version": "1.0.13",
///       "publishedAt": "2026-04-11T00:00:00Z",
///       "notes": "...",
///       "releaseUrl": "https://github.com/.../releases/tag/v1.0.13",
///       "platforms": {
///         "android-arm64-v8a": { "url": "...", "sha256": "..." },
///         "android-armeabi-v7a": { "url": "...", "sha256": "..." },
///         "android-x86_64": { "url": "...", "sha256": "..." },
///         "android-universal": { "url": "...", "sha256": "..." },
///         "ios": { "url": "...", "sha256": "..." },
///         "macos-universal": { "url": "...", "sha256": "..." },
///         "windows-amd64-setup": { "url": "...", "sha256": "..." },
///         "windows-amd64-portable": { "url": "...", "sha256": "..." },
///         "linux-amd64-appimage": { "url": "...", "sha256": "..." }
///       }
///     }
///
/// Only active when [EnvConfig.isStandalone] is true. Store builds (App Store
/// / Google Play) must not contain self-update logic.
class UpdateChecker {
  UpdateChecker._();
  static final instance = UpdateChecker._();

  // ── Settings keys ─────────────────────────────────────────────────────────
  /// 'stable' (default) → only v* releases. 'pre' → also pick up `pre` tags.
  static const kUpdateChannel = 'updateChannel';
  /// Whether to auto-check for updates on app startup. Default true.
  static const kAutoCheckUpdates = 'autoCheckUpdates';
  /// ISO-8601 timestamp of the last successful manifest fetch (success OR
  /// "no update available"). Set on every check.
  static const kLastUpdateCheck = 'lastUpdateCheck';

  // ── Mirror endpoints (tried in order; first success wins) ─────────────────
  // The fixed `updater` tag carries two assets: update.json (stable channel)
  // and update-pre.json (pre-release channel). We try a CDN (jsdelivr) first
  // because it's reliably reachable inside China, then a GitHub HTTP proxy,
  // then raw github content as a last resort. The legacy /releases/latest
  // API call is the final fallback so users on builds older than the
  // manifest rollout still receive updates.
  static List<String> _endpointsForChannel(String channel) {
    final filename = channel == 'pre' ? 'update-pre.json' : 'update.json';
    return [
      // jsDelivr CDN
      'https://cdn.jsdelivr.net/gh/onesyue/yuelink@updater/$filename',
      // ghproxy mirrors (rotate every few months — keep two)
      'https://gh-proxy.com/https://github.com/onesyue/yuelink/releases/download/updater/$filename',
      'https://ghfast.top/https://github.com/onesyue/yuelink/releases/download/updater/$filename',
      // Direct GitHub release asset
      'https://github.com/onesyue/yuelink/releases/download/updater/$filename',
    ];
  }

  static const _legacyApi =
      'https://api.github.com/repos/onesyue/yuelink/releases/latest';

  /// Check for updates. Returns null if already on latest, check fails,
  /// version was skipped by user, or running in store mode.
  ///
  /// [auto] is set to true by the on-startup check; the manual "Check for
  /// updates" button passes false. When [auto] is true, the check is skipped
  /// entirely if the user disabled `autoCheckUpdates`.
  Future<UpdateInfo?> check({
    bool ignoreSkipped = false,
    bool auto = false,
  }) async {
    if (!EnvConfig.isStandalone) return null;
    if (auto) {
      final enabled =
          (await SettingsService.get<bool>(kAutoCheckUpdates)) ?? true;
      if (!enabled) return null;
    }

    final channel =
        (await SettingsService.get<String>(kUpdateChannel)) ?? 'stable';
    final manifest = await _fetchManifest(channel: channel);

    // Record the last check timestamp regardless of channel result, so the
    // settings page can show "Last checked: N minutes ago".
    await SettingsService.set(
      kLastUpdateCheck,
      DateTime.now().toIso8601String(),
    );

    if (manifest == null) {
      return _legacyCheck(
        ignoreSkipped: ignoreSkipped,
        reportErrors: !auto,
      );
    }

    final latestVersion =
        (manifest['version'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
    if (latestVersion.isEmpty) return null;

    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    if (!_isNewer(latestVersion, currentVersion)) return null;

    if (!ignoreSkipped) {
      final skipped = await SettingsService.get<String>('skippedVersion');
      if (skipped == latestVersion) return null;
    }

    final platforms =
        (manifest['platforms'] as Map<String, dynamic>?) ?? const {};
    final key = _platformKey();
    final asset = key == null ? null : platforms[key] as Map<String, dynamic>?;

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseNotes: manifest['notes'] as String? ?? '',
      releaseUrl: manifest['releaseUrl'] as String? ?? '',
      downloadUrl: asset?['url'] as String?,
      sha256: asset?['sha256'] as String?,
      publishedAt: DateTime.tryParse(manifest['publishedAt'] as String? ?? ''),
    );
  }

  /// Try each manifest endpoint in order. Returns the first successful JSON
  /// payload, or null if all of them failed. For the `pre` channel we try
  /// the pre-release manifest first; if it doesn't exist on any endpoint, we
  /// fall back to the stable manifest so the user is never stuck.
  Future<Map<String, dynamic>?> _fetchManifest({
    required String channel,
  }) async {
    final endpoints = _endpointsForChannel(channel);
    for (final url in endpoints) {
      try {
        final r = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));
        if (r.statusCode != 200) continue;
        final data = json.decode(r.body);
        if (data is Map<String, dynamic> && data['version'] is String) {
          debugPrint('[UpdateChecker] manifest OK from $url');
          return data;
        }
      } catch (e) {
        debugPrint('[UpdateChecker] manifest failed at $url: $e');
        EventLog.write('[Updater] manifest_fetch_failed url=$url err=$e');
      }
    }
    // Fallback to stable if pre-release manifest is missing entirely.
    if (channel == 'pre') {
      debugPrint('[UpdateChecker] pre-release manifest unavailable, '
          'falling back to stable');
      return _fetchManifest(channel: 'stable');
    }
    return null;
  }

  /// Last-resort: hit the GitHub Releases API directly. Used when the manifest
  /// is unavailable from every mirror (e.g. before the first manifest is
  /// published, or during a CI hiccup).
  ///
  /// [reportErrors] controls whether the exception-catch forwards to
  /// ErrorLogger. True only on user-initiated checks where the user is
  /// waiting for a result — on startup auto-check, GitHub API
  /// unreachability is both expected (GFW) and invisible to the user,
  /// so we downgrade to EventLog to avoid remote telemetry noise.
  Future<UpdateInfo?> _legacyCheck({
    required bool ignoreSkipped,
    required bool reportErrors,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(_legacyApi),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 8));
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

      if (!ignoreSkipped) {
        final skipped = await SettingsService.get<String>('skippedVersion');
        if (skipped == latestVersion) return null;
      }

      final assets = data['assets'] as List<dynamic>? ?? [];
      final downloadUrl = _findLegacyAssetUrl(assets);

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseNotes: body,
        releaseUrl: htmlUrl,
        downloadUrl: downloadUrl,
        publishedAt:
            publishedAt != null ? DateTime.tryParse(publishedAt) : null,
      );
    } catch (e, st) {
      debugPrint('[UpdateChecker] legacy check failed: $e');
      if (reportErrors) {
        ErrorLogger.captureException(e, st,
            source: 'UpdateChecker._legacyCheck');
      } else {
        EventLog.write('[Updater] legacy_check_failed_auto err=$e');
      }
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

  /// Read the current update channel ('stable' | 'pre'). Default 'stable'.
  static Future<String> getChannel() async {
    return (await SettingsService.get<String>(kUpdateChannel)) ?? 'stable';
  }

  /// Set the update channel.
  static Future<void> setChannel(String channel) async {
    await SettingsService.set(kUpdateChannel, channel);
  }

  /// Whether auto-check on startup is enabled. Default true.
  static Future<bool> getAutoCheck() async {
    return (await SettingsService.get<bool>(kAutoCheckUpdates)) ?? true;
  }

  /// Toggle auto-check on startup.
  static Future<void> setAutoCheck(bool enabled) async {
    await SettingsService.set(kAutoCheckUpdates, enabled);
  }

  /// Last successful manifest fetch timestamp (null if never checked).
  static Future<DateTime?> getLastCheck() async {
    final raw = await SettingsService.get<String>(kLastUpdateCheck);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  // ── Platform key resolution ───────────────────────────────────────────────

  /// Returns the manifest `platforms` key matching the current process,
  /// e.g. `linux-arm64-deb` or `windows-amd64-setup`. Returns null when the
  /// platform is unknown.
  static String? _platformKey() {
    final arch = _archSlug();
    if (Platform.isAndroid) {
      // For Android we prefer the user's installed ABI; default to universal
      // when we can't tell so the user always gets *something*.
      return 'android-${_androidAbi()}';
    }
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos-universal';
    if (Platform.isWindows) return 'windows-$arch-setup';
    if (Platform.isLinux) {
      // Release only ships AppImage. Distro-native .deb / .rpm were removed
      // from the matrix — keep the updater pointed at the real asset so
      // users don't get a dead link on Debian/Fedora hosts.
      return 'linux-$arch-appimage';
    }
    return null;
  }

  static String _archSlug() {
    // Dart has no first-class CPU arch field. Best we can do is parse
    // Platform.version (e.g. "3.6.0 ... linux_arm64").
    final v = Platform.version.toLowerCase();
    if (v.contains('arm64') || v.contains('aarch64')) return 'arm64';
    if (v.contains('x86_64') || v.contains('x64') || v.contains('amd64')) {
      return 'amd64';
    }
    if (v.contains('arm')) return 'armeabi-v7a';
    return 'amd64';
  }

  static String _androidAbi() {
    final v = Platform.version.toLowerCase();
    if (v.contains('arm64') || v.contains('aarch64')) return 'arm64-v8a';
    if (v.contains('x86_64') || v.contains('x64')) return 'x86_64';
    if (v.contains('arm')) return 'armeabi-v7a';
    return 'universal';
  }

  /// Legacy asset suffix matching (used by the GitHub API fallback path).
  static String? _findLegacyAssetUrl(List<dynamic> assets) {
    final suffix = _legacyPlatformSuffix();
    if (suffix == null) return null;
    for (final asset in assets) {
      final name = (asset as Map<String, dynamic>)['name'] as String? ?? '';
      if (name.toLowerCase().contains(suffix.toLowerCase())) {
        return asset['browser_download_url'] as String?;
      }
    }
    return null;
  }

  static String? _legacyPlatformSuffix() {
    if (Platform.isAndroid) {
      // Detect the actual installed ABI instead of hardcoding arm64-v8a.
      // armv7 / x86_64 / universal users would otherwise download a binary
      // their device can't execute.
      return 'android-${_androidAbi()}.apk';
    }
    if (Platform.isMacOS) return '.dmg';
    if (Platform.isWindows) return 'setup.exe';
    if (Platform.isIOS) return '.ipa';
    if (Platform.isLinux) return '.AppImage';
    return null;
  }

  // ── Download with optional sha256 verification ────────────────────────────

  /// Download an update file with progress callback.
  ///
  /// If [expectedSha256] is provided, the downloaded file is verified against
  /// it and a [SecurityException] is thrown on mismatch (the partial file is
  /// then deleted to prevent installing tampered content).
  static Future<String> download(
    String url, {
    String? expectedSha256,
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
      sink = null;

      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        final actual = await _sha256OfFile(file);
        if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
          try {
            file.deleteSync();
          } catch (_) {}
          throw const SecurityException(
            'Downloaded file SHA-256 does not match the manifest. '
            'The download may have been tampered with — refusing to install.',
          );
        }
      }
      return file.path;
    } catch (e) {
      try {
        await sink?.close();
      } catch (e) {
        debugPrint('[UpdateChecker] sink close error: $e');
        EventLog.write('[Updater] sink_close_failed err=$e');
      }
      try {
        if (file != null && file.existsSync()) file.deleteSync();
      } catch (e) {
        debugPrint('[UpdateChecker] partial file cleanup error: $e');
        EventLog.write('[Updater] partial_cleanup_failed err=$e');
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  static Future<String> _sha256OfFile(File f) async {
    final digest = await sha256.bind(f.openRead()).first;
    return digest.toString();
  }

  // ── Version comparison ────────────────────────────────────────────────────

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
    final parts = v
        .split(RegExp(r'[.\-+]'))
        .take(3)
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }
}

/// Thrown when a downloaded file fails its SHA-256 integrity check.
class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String releaseUrl;
  final String? downloadUrl;
  final String? sha256;
  final DateTime? publishedAt;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.releaseUrl,
    this.downloadUrl,
    this.sha256,
    this.publishedAt,
  });
}
