import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../l10n/app_strings.dart';
import '../models/profile.dart';
import 'config_template.dart';
import 'subscription_parser.dart';

/// Manages subscription profiles: download, store, update.
class ProfileService {
  static const _profilesFileName = 'profiles.json';
  static const _configDirName = 'configs';

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

  /// Load all saved profiles.
  /// JSON decode runs in a background Isolate to avoid jank on large index files.
  static Future<List<Profile>> loadProfiles() async {
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
  static Future<void> saveProfiles(List<Profile> profiles) async {
    final file = await _getProfilesFile();
    await file.writeAsString(
        json.encode(profiles.map((p) => p.toJson()).toList()));
  }

  /// Download a subscription and save the config content.
  ///
  /// If the subscription only provides proxies (no proxy-groups/rules),
  /// they are merged into the built-in default config template which
  /// includes all the proxy-groups, rules, and DNS settings.
  static Future<Profile> addProfile({
    required String name,
    required String url,
  }) async {
    final result = await _downloadConfig(url);
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    // Use subscription config directly if complete (normal case).
    // Only merge with fallback template if subscription has no groups/rules.
    String finalContent = result.content;
    if (!ConfigTemplate.isCompleteConfig(result.content)) {
      final fallback = await ConfigTemplate.loadFallbackTemplate();
      finalContent = ConfigTemplate.mergeIfNeeded(fallback, result.content);
    }

    final profile = Profile(
      id: id,
      name: name,
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

    final profiles = await loadProfiles();
    profiles.add(profile);
    await saveProfiles(profiles);

    return profile;
  }

  /// Update a subscription profile by re-downloading.
  static Future<Profile> updateProfile(Profile profile) async {
    final result = await _downloadConfig(profile.url);

    // Use subscription config directly if complete (normal case).
    // Only merge with fallback template if subscription has no groups/rules.
    String finalContent = result.content;
    if (!ConfigTemplate.isCompleteConfig(result.content)) {
      final fallback = await ConfigTemplate.loadFallbackTemplate();
      finalContent = ConfigTemplate.mergeIfNeeded(fallback, result.content);
    }

    profile.configContent = finalContent;
    profile.lastUpdated = DateTime.now();
    profile.subInfo = result.subInfo;

    final dir = await _getProfilesDir();
    await File('${dir.path}/${profile.id}.yaml')
        .writeAsString(finalContent);

    final profiles = await loadProfiles();
    final idx = profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) profiles[idx] = profile;
    await saveProfiles(profiles);

    return profile;
  }

  /// Import a local YAML file as a profile (no URL, no auto-update).
  static Future<Profile> addLocalProfile({
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

    final profiles = await loadProfiles();
    profiles.add(profile);
    await saveProfiles(profiles);

    return profile;
  }

  /// Delete a profile.
  static Future<void> deleteProfile(String id) async {
    final dir = await _getProfilesDir();
    final configFile = File('${dir.path}/$id.yaml');
    if (await configFile.exists()) {
      await configFile.delete();
    }
    final profiles = await loadProfiles();
    profiles.removeWhere((p) => p.id == id);
    await saveProfiles(profiles);
  }

  /// Load config content for a profile.
  static Future<String?> loadConfig(String id) async {
    final dir = await _getProfilesDir();
    final file = File('${dir.path}/$id.yaml');
    if (await file.exists()) {
      return file.readAsString();
    }
    return null;
  }

  /// Download config YAML from a subscription URL.
  /// Returns both the content and parsed subscription info from headers.
  static Future<_DownloadResult> _downloadConfig(String url) async {
    http.Response response;
    try {
      response = await http
          .get(
            Uri.parse(url),
            headers: {'User-Agent': AppConstants.userAgent},
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw Exception(S.current.errDownloadTimeout);
    } on SocketException catch (e) {
      final detail = e.message.isNotEmpty ? e.message : (e.address?.host ?? 'unknown');
      throw Exception(S.current.errNetworkError(detail));
    }

    if (response.statusCode != 200) {
      throw Exception(S.current.errDownloadHttpFailed(response.statusCode));
    }

    final subInfo = SubscriptionInfo.fromHeaders(response.headers);
    return _DownloadResult(content: response.body, subInfo: subInfo);
  }
}

class _DownloadResult {
  final String content;
  final SubscriptionInfo subInfo;
  _DownloadResult({required this.content, required this.subInfo});
}
