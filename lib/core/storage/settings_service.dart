import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'secure_storage_service.dart';

/// Persistent settings storage using a simple JSON file.
class SettingsService {
  static const _fileName = 'settings.json';
  static Map<String, dynamic>? _cache;

  // Serialize concurrent saves: each save waits for the previous to finish.
  // This prevents the race where two writes share the same .tmp path and the
  // second rename throws PathNotFoundException after the first already moved it.
  static Future<void> _saveGuard = Future.value();

  static Future<File> _getFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<Map<String, dynamic>> load() async {
    if (_cache != null) return _cache!;
    final file = await _getFile();
    if (!await file.exists()) {
      _cache = {};
      return _cache!;
    }
    try {
      _cache = json.decode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      // Corrupt JSON (crash during write, bad WebDAV sync) — fall back to empty.
      debugPrint('[SettingsService] corrupt settings.json, resetting to empty');
      _cache = {};
    }
    return _cache!;
  }

  /// Invalidate in-memory cache (e.g., after WebDAV download).
  static void invalidateCache() => _cache = null;

  static Future<void> save(Map<String, dynamic> settings) {
    _cache = settings;
    // Chain onto the previous save so concurrent calls never race on .tmp.
    _saveGuard = _saveGuard.then((_) async {
      final file = await _getFile();
      // Ensure parent directory exists (first run or after cleanup)
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // Atomic write: write to temp file then rename to prevent corruption
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json.encode(settings));
      await tmp.rename(file.path);
    }, onError: (_) {
      // Swallow errors in chained saves so _saveGuard never stays in a
      // rejected state (which would block all subsequent saves).
    });
    return _saveGuard;
  }

  static Future<void> set(String key, dynamic value) async {
    final settings = await load();
    settings[key] = value;
    await save(settings);
  }

  static Future<T?> get<T>(String key) async {
    final settings = await load();
    return settings[key] as T?;
  }

  // ── Theme ────────────────────────────────────────────────────────────────

  static Future<ThemeMode> getThemeMode() async {
    final value = await get<String>('themeMode');
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.dark;
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    await set('themeMode', mode.name);
  }

  // ── Active profile ───────────────────────────────────────────────────────

  static Future<String?> getActiveProfileId() async {
    return get<String>('activeProfileId');
  }

  static Future<void> setActiveProfileId(String? id) async {
    await set('activeProfileId', id);
  }

  // ── Routing mode (rule / global / direct) ───────────────────────────────

  static Future<String> getRoutingMode() async {
    return (await get<String>('routingMode')) ?? 'rule';
  }

  static Future<void> setRoutingMode(String mode) async {
    await set('routingMode', mode);
  }

  // ── Connection mode (tun / systemProxy) ─────────────────────────────────

  static Future<String> getConnectionMode() async {
    return (await get<String>('connectionMode')) ?? 'systemProxy';
  }

  static Future<void> setConnectionMode(String mode) async {
    await set('connectionMode', mode);
  }

  // ── Log level ────────────────────────────────────────────────────────────

  static Future<String> getLogLevel() async {
    return (await get<String>('logLevel')) ?? 'info';
  }

  static Future<void> setLogLevel(String level) async {
    await set('logLevel', level);
  }

  // ── Auto connect ─────────────────────────────────────────────────────────

  static Future<bool> getAutoConnect() async {
    return (await get<bool>('autoConnect')) ?? false;
  }

  static Future<void> setAutoConnect(bool value) async {
    await set('autoConnect', value);
  }

  // ── System proxy on connect (macOS / Windows) ────────────────────────────

  static Future<bool> getSystemProxyOnConnect() async {
    return (await get<bool>('systemProxyOnConnect')) ?? true;
  }

  static Future<void> setSystemProxyOnConnect(bool value) async {
    await set('systemProxyOnConnect', value);
  }

  // ── Auto-start on boot (macOS / Windows) ────────────────────────────────

  static Future<bool> getLaunchAtStartup() async {
    return (await get<bool>('launchAtStartup')) ?? false;
  }

  static Future<void> setLaunchAtStartup(bool value) async {
    await set('launchAtStartup', value);
  }

  // ── Language (zh / en) ──────────────────────────────────────────────────

  static Future<String> getLanguage() async {
    return (await get<String>('language')) ?? 'zh';
  }

  static Future<void> setLanguage(String langCode) async {
    await set('language', langCode);
  }

  // ── Close window behavior (desktop) ─────────────────────────────────────────

  /// Values: 'tray' (default) | 'exit'
  static Future<String> getCloseBehavior() async {
    return (await get<String>('closeBehavior')) ?? 'tray';
  }

  static Future<void> setCloseBehavior(String behavior) async {
    await set('closeBehavior', behavior);
  }

  // ── Toggle connection hotkey (desktop) ──────────────────────────────────────

  /// Stored as lowercase plus-separated string, e.g. "ctrl+alt+c".
  static Future<String> getToggleHotkey() async {
    return (await get<String>('toggleHotkey')) ?? 'ctrl+alt+c';
  }

  static Future<void> setToggleHotkey(String hotkey) async {
    await set('toggleHotkey', hotkey);
  }

  // ── Latency test URL ────────────────────────────────────────────────────

  static const _defaultTestUrl = 'https://www.gstatic.com/generate_204';

  static Future<String> getTestUrl() async {
    return (await get<String>('testUrl')) ?? _defaultTestUrl;
  }

  static Future<void> setTestUrl(String url) async {
    await set('testUrl', url);
  }

  // ── Daily traffic stats ──────────────────────────────────────────

  static String _dateKey(DateTime date) {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<Map<String, int>> getTodayTraffic() async {
    final key = _dateKey(DateTime.now());
    final settings = await load();
    return {
      'up': (settings['traffic_up_$key'] as int?) ?? 0,
      'down': (settings['traffic_down_$key'] as int?) ?? 0,
    };
  }

  static Future<void> saveTodayTraffic(int up, int down) async {
    final key = _dateKey(DateTime.now());
    final settings = await load();
    settings['traffic_up_$key'] = up;
    settings['traffic_down_$key'] = down;
    await save(settings);
  }

  // ── Android 分应用代理（Split Tunneling）────────────────────────────────

  static Future<String> getSplitTunnelMode() async {
    return (await get<String>('splitTunnelMode')) ?? 'all';
  }

  static Future<void> setSplitTunnelMode(String mode) async {
    await set('splitTunnelMode', mode);
  }

  static Future<List<String>> getSplitTunnelApps() async {
    final settings = await load();
    final raw = settings['splitTunnelApps'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  static Future<void> setSplitTunnelApps(List<String> apps) async {
    await set('splitTunnelApps', apps);
  }

  // ── Upstream proxy ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getUpstreamProxy() async {
    final settings = await load();
    final raw = settings['upstreamProxy'];
    if (raw is Map && raw['enabled'] == true) {
      return {
        'type': raw['type'] as String? ?? 'socks5',
        'server': raw['server'] as String? ?? '',
        'port': (raw['port'] as int?) ?? 1080,
      };
    }
    return null;
  }

  static Future<void> setUpstreamProxy({
    required bool enabled,
    required String type,
    required String server,
    required int port,
  }) async {
    await set('upstreamProxy', {
      'enabled': enabled,
      'type': type,
      'server': server,
      'port': port,
    });
  }

  // ── Expanded proxy groups ────────────────────────────────────────────────────

  static Future<List<String>> getExpandedGroups() async {
    final settings = await load();
    final raw = settings['expandedGroups'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  static Future<void> setExpandedGroups(List<String> groups) async {
    await set('expandedGroups', groups);
  }

  // ── Delay test results ───────────────────────────────────────────────────────

  static Future<Map<String, int>> getDelayResults() async {
    final settings = await load();
    final raw = settings['delayResults'];
    if (raw is Map) {
      // JSON decode may produce double for numeric values; safely convert to int
      return raw.map((k, v) => MapEntry(k as String, (v as num).toInt()));
    }
    return {};
  }

  static Future<void> setDelayResults(Map<String, int> results) async {
    await set('delayResults', results);
  }

  // ── Last tab index (Android process restore) ──────────────────────────────

  static Future<int> getLastTabIndex() async {
    return (await get<int>('lastTabIndex')) ?? 0;
  }

  static Future<void> setLastTabIndex(int index) async {
    await set('lastTabIndex', index);
  }

  static Future<List<int>> getBuiltTabs() async {
    final list = await get<List>('builtTabs');
    if (list == null) return [0];
    return list.cast<int>();
  }

  static Future<void> setBuiltTabs(List<int> tabs) async {
    await set('builtTabs', tabs);
  }

  // ── Onboarding ─────────────────────────────────────────────────────────────

  static Future<bool> getHasSeenOnboarding() async {
    return (await get<bool>('hasSeenOnboarding')) ?? false;
  }

  static Future<void> setHasSeenOnboarding(bool value) async {
    await set('hasSeenOnboarding', value);
  }

  // ── WebDAV (credentials stored in OS secure storage, not plain JSON) ────────

  static Future<Map<String, String>> getWebDavConfig() =>
      SecureStorageService.instance.getWebDavConfig();

  static Future<void> setWebDavConfig({
    required String url,
    required String username,
    required String password,
  }) =>
      SecureStorageService.instance.setWebDavConfig(
        url: url,
        username: username,
        password: password,
      );
}
