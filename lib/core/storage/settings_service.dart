import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'secure_storage_service.dart';

/// Persistent settings storage using a simple JSON file.
class SettingsService {
  static const _fileName = 'settings.json';
  static Map<String, dynamic>? _cache;

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
    _cache = json.decode(await file.readAsString()) as Map<String, dynamic>;
    return _cache!;
  }

  /// Invalidate in-memory cache (e.g., after WebDAV download).
  static void invalidateCache() => _cache = null;

  static Future<void> save(Map<String, dynamic> settings) async {
    _cache = settings;
    final file = await _getFile();
    // Atomic write: write to temp file then rename to prevent corruption
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json.encode(settings));
    await tmp.rename(file.path);
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
        return ThemeMode.system;
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
    return (await get<bool>('autoConnect')) ?? true;
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
