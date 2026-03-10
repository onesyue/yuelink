import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
    await file.writeAsString(json.encode(settings));
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
    return (await get<String>('connectionMode')) ?? 'tun';
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

  // ── Subscription auto-update interval (hours, 0 = disabled) ─────────────

  static Future<int> getAutoUpdateInterval() async {
    return (await get<int>('autoUpdateInterval')) ?? 24;
  }

  static Future<void> setAutoUpdateInterval(int hours) async {
    await set('autoUpdateInterval', hours);
  }

  // ── WebDAV ───────────────────────────────────────────────────────────────

  static Future<Map<String, String>> getWebDavConfig() async {
    final settings = await load();
    return {
      'url': (settings['webdavUrl'] as String?) ?? '',
      'username': (settings['webdavUsername'] as String?) ?? '',
      'password': (settings['webdavPassword'] as String?) ?? '',
    };
  }

  static Future<void> setWebDavConfig({
    required String url,
    required String username,
    required String password,
  }) async {
    final settings = await load();
    settings['webdavUrl'] = url;
    settings['webdavUsername'] = username;
    settings['webdavPassword'] = password;
    await save(settings);
  }
}
