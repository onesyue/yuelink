import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../constants.dart';
import '../../core/kernel/config_template.dart';
import '../../domain/models/profile.dart';
import '../../l10n/app_strings.dart';
import '../../shared/formatters/subscription_parser.dart';

/// Manages subscription profiles: download, store, update, delete.
///
/// This is the canonical implementation. [ProfileService] delegates to a
/// static instance of this class for backward compatibility with callers
/// that use `ProfileService.staticMethod()` (including main.dart).
class ProfileRepository {
  const ProfileRepository();

  // ── Constants ──────────────────────────────────────────────────────────

  static const _profilesFileName = 'profiles.json';
  static const _configDirName = 'configs';

  // ── Mutex ──────────────────────────────────────────────────────────────

  /// Mutex to prevent concurrent index file mutations (load→modify→save race).
  static Completer<void>? _indexLock;

  static Future<T> _withIndexLock<T>(Future<T> Function() action) async {
    while (_indexLock != null) {
      await _indexLock!.future;
    }
    _indexLock = Completer<void>();
    try {
      return await action();
    } finally {
      _indexLock!.complete();
      _indexLock = null;
    }
  }

  // ── File paths ─────────────────────────────────────────────────────────

  static Future<Directory> _getProfilesDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/$_configDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _getProfilesFile() async {
    final appDir = await getApplicationSupportDirectory();
    return File('${appDir.path}/$_profilesFileName');
  }

  // ── Public API ─────────────────────────────────────────────────────────

  /// Load all saved profiles.
  /// JSON decode runs in a background Isolate to avoid jank on large index files.
  Future<List<Profile>> loadProfiles() async {
    final file = await _getProfilesFile();
    if (!await file.exists()) return [];
    final jsonStr = await file.readAsString();
    return Isolate.run(() {
      final list = json.decode(jsonStr) as List;
      return list
          .map((e) => Profile.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Save profiles index.
  /// JSON encode runs in a background Isolate to avoid jank.
  Future<void> saveProfiles(List<Profile> profiles) async {
    final file = await _getProfilesFile();
    final jsonList = profiles.map((p) => p.toJson()).toList();
    final encoded = await Isolate.run(() => json.encode(jsonList));
    await file.writeAsString(encoded);
  }

  /// Download a subscription and save the config content.
  ///
  /// If the subscription only provides proxies (no proxy-groups/rules),
  /// they are merged into the built-in default config template which
  /// includes all the proxy-groups, rules, and DNS settings.
  ///
  /// [proxyPort] — pass the running core's mixed-port so the download
  /// goes through the local proxy (needed on Android where the app is
  /// excluded from VPN).
  Future<Profile> addProfile({
    required String name,
    required String url,
    int? proxyPort,
  }) async {
    final result = await _downloadConfig(url, proxyPort: proxyPort);
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    // Heavy config processing in background isolate to prevent ANR
    final fallback = ConfigTemplate.isCompleteConfig(result.content)
        ? null
        : await ConfigTemplate.loadFallbackTemplate();
    final finalContent = await Isolate.run(() {
      if (fallback != null) {
        return ConfigTemplate.mergeIfNeeded(fallback, result.content);
      }
      return result.content;
    });

    // Use fetched name from headers if user didn't provide one
    final effectiveName = name.isNotEmpty
        ? name
        : (result.subInfo.profileTitle ?? _nameFromUrl(url));

    final profile = Profile(
      id: id,
      name: effectiveName,
      url: url,
      configContent: finalContent,
      lastUpdated: DateTime.now(),
      subInfo: result.subInfo,
      updateInterval: result.subInfo.updateInterval != null
          ? Duration(hours: result.subInfo.updateInterval!)
          : const Duration(hours: 24),
    );

    final dir = await _getProfilesDir();
    await File('${dir.path}/$id.yaml').writeAsString(finalContent);

    await _withIndexLock(() async {
      final profiles = await loadProfiles();
      profiles.add(profile);
      await saveProfiles(profiles);
    });

    return profile;
  }

  /// Update a subscription profile by re-downloading.
  Future<Profile> updateProfile(Profile profile, {int? proxyPort}) async {
    final result = await _downloadConfig(profile.url, proxyPort: proxyPort);

    // Heavy config processing in background isolate to prevent ANR
    final fallback = ConfigTemplate.isCompleteConfig(result.content)
        ? null
        : await ConfigTemplate.loadFallbackTemplate();
    final String finalContent = await Isolate.run(() {
      if (fallback != null) {
        return ConfigTemplate.mergeIfNeeded(fallback, result.content);
      }
      return result.content;
    });

    profile.configContent = finalContent;
    profile.lastUpdated = DateTime.now();
    profile.subInfo = result.subInfo;

    final dir = await _getProfilesDir();
    await File('${dir.path}/${profile.id}.yaml')
        .writeAsString(finalContent);

    await _withIndexLock(() async {
      final profiles = await loadProfiles();
      final idx = profiles.indexWhere((p) => p.id == profile.id);
      if (idx >= 0) profiles[idx] = profile;
      await saveProfiles(profiles);
    });

    return profile;
  }

  /// Import a local YAML file as a profile (no URL, no auto-update).
  Future<Profile> addLocalProfile({
    required String name,
    required String configContent,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    String finalContent = configContent;
    if (!ConfigTemplate.isCompleteConfig(configContent)) {
      final fallback = await ConfigTemplate.loadFallbackTemplate();
      finalContent = ConfigTemplate.mergeIfNeeded(fallback, configContent);
    }

    final profile = Profile(
      id: id,
      name: name,
      url: '', // no remote URL
      configContent: finalContent,
      lastUpdated: DateTime.now(),
      subInfo: SubscriptionInfo(),
      updateInterval: Duration.zero, // never auto-update
    );

    final dir = await _getProfilesDir();
    await File('${dir.path}/$id.yaml').writeAsString(finalContent);

    await _withIndexLock(() async {
      final profiles = await loadProfiles();
      profiles.add(profile);
      await saveProfiles(profiles);
    });

    return profile;
  }

  /// Delete a profile.
  Future<void> deleteProfile(String id) async {
    final dir = await _getProfilesDir();
    final configFile = File('${dir.path}/$id.yaml');
    if (await configFile.exists()) {
      await configFile.delete();
    }
    await _withIndexLock(() async {
      final profiles = await loadProfiles();
      profiles.removeWhere((p) => p.id == id);
      await saveProfiles(profiles);
    });
  }

  /// Load config content for a profile.
  Future<String?> loadConfig(String id) async {
    final dir = await _getProfilesDir();
    final file = File('${dir.path}/$id.yaml');
    if (await file.exists()) {
      return file.readAsString();
    }
    return null;
  }

  /// Fetch subscription name from URL headers without downloading the full config.
  /// Returns the name from `profile-title` or `content-disposition`, or null.
  Future<String?> fetchSubscriptionName(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('User-Agent', AppConstants.userAgent);
        final response =
            await request.close().timeout(const Duration(seconds: 10));
        final headers = <String, String>{};
        response.headers.forEach((name, values) {
          headers[name] = values.join(', ');
        });
        await response.drain<void>();
        final info = SubscriptionInfo.fromHeaders(headers);
        return info.profileTitle;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('[ProfileRepository] fetchSubscriptionName failed: $e');
      return null;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /// Download config YAML from a subscription URL.
  /// Returns both the content and parsed subscription info from headers.
  ///
  /// When [proxyPort] is provided (core is running), the download goes
  /// through the local proxy first. If that fails, falls back to direct
  /// download. This is critical on Android: the app itself is excluded
  /// from VPN (addDisallowedApplication), so direct HTTP requests bypass
  /// the proxy. If the subscription URL is behind a firewall, direct
  /// download fails while proxied download succeeds.
  static Future<_DownloadResult> _downloadConfig(
    String url, {
    int? proxyPort,
  }) async {
    http.Response response;

    // Try proxied download first, fall back to direct on failure
    if (proxyPort != null && proxyPort > 0) {
      try {
        response = await _downloadViaProxy(url, proxyPort);
      } catch (e) {
        debugPrint(
            '[ProfileRepository] Proxied download failed ($e), falling back to direct');
        response = await _downloadDirect(url);
      }
    } else {
      response = await _downloadDirect(url);
    }

    if (response.statusCode != 200) {
      throw Exception(S.current.errDownloadHttpFailed(response.statusCode));
    }

    final subInfo = SubscriptionInfo.fromHeaders(response.headers);
    return _DownloadResult(content: response.body, subInfo: subInfo);
  }

  /// Download via local proxy.
  static Future<http.Response> _downloadViaProxy(String url, int port) async {
    final client = HttpClient();
    client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', AppConstants.userAgent);
      final ioResponse =
          await request.close().timeout(const Duration(seconds: 30));
      final body = await ioResponse.transform(utf8.decoder).join();
      final headers = <String, String>{};
      ioResponse.headers.forEach((name, values) {
        headers[name] = values.join(', ');
      });
      return http.Response(body, ioResponse.statusCode, headers: headers);
    } finally {
      client.close();
    }
  }

  /// Download directly (no proxy).
  static Future<http.Response> _downloadDirect(String url) async {
    try {
      return await http
          .get(
            Uri.parse(url),
            headers: {'User-Agent': AppConstants.userAgent},
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw Exception(S.current.errDownloadTimeout);
    } on SocketException catch (e) {
      final detail =
          e.message.isNotEmpty ? e.message : (e.address?.host ?? 'unknown');
      throw Exception(S.current.errNetworkError(detail));
    }
  }

  /// Fallback name from URL hostname when headers don't provide a name.
  static String _nameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // Use hostname without common prefixes
      var host = uri.host;
      if (host.startsWith('www.')) host = host.substring(4);
      if (host.isNotEmpty) return host;
    } catch (e) {
      debugPrint('[ProfileRepository] _nameFromUrl parse failed: $e');
    }
    return 'Subscription';
  }
}

class _DownloadResult {
  final String content;
  final SubscriptionInfo subInfo;
  _DownloadResult({required this.content, required this.subInfo});
}

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => const ProfileRepository());
