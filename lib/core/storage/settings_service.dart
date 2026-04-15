import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent settings storage using a simple JSON file.
///
/// Write strategy: every `set()` updates the in-memory cache immediately
/// (so subsequent `get()` calls see the new value with no latency) but
/// COALESCES the disk write into a single flush ~250 ms later. Bursts of
/// updates — speed-test rounds, group expand/collapse spam, tab switches —
/// all collapse into one atomic file rewrite instead of N rewrites.
///
/// `setImmediate()` is available for the rare cases where the caller needs
/// the write to hit disk before continuing (e.g. before triggering an
/// elevation prompt that may kill the process).
class SettingsService {
  static const _fileName = 'settings.json';
  static const _flushInterval = Duration(milliseconds: 250);

  static Map<String, dynamic>? _cache;

  // Serialize concurrent saves: each save waits for the previous to finish.
  // Prevents .tmp path races where two writes share the same temp file
  // and the second rename throws PathNotFoundException.
  static Future<void> _saveGuard = Future.value();

  // Coalescing flush state
  static Timer? _flushTimer;
  static bool _flushPending = false;

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
    } catch (e) {
      // Corrupt JSON (for example after an interrupted write) — fall back to empty.
      debugPrint(
          '[SettingsService] corrupt settings.json ($e), resetting to empty');
      _cache = {};
    }
    return _cache!;
  }

  /// Invalidate the in-memory cache so the next read comes from disk.
  static void invalidateCache() => _cache = null;

  /// Internal: actually write the current cache to disk. Atomic via
  /// tmp+rename. Chained on `_saveGuard` so concurrent flushes serialise.
  static Future<void> _flushNow() async {
    _flushPending = false;
    final snapshot = _cache;
    if (snapshot == null) return;
    _saveGuard = _saveGuard.then((_) async {
      final file = await _getFile();
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json.encode(snapshot));
      await tmp.rename(file.path);
    }, onError: (e) {
      debugPrint('[SettingsService] save failed: $e');
    });
    return _saveGuard;
  }

  /// Schedule a coalesced flush. Multiple set() calls within
  /// [_flushInterval] all collapse into one disk write.
  static void _scheduleFlush() {
    if (_flushPending) {
      // Already scheduled, restart the timer to extend the coalescing window.
      _flushTimer?.cancel();
      _flushTimer = Timer(_flushInterval, () => unawaited(_flushNow()));
      return;
    }
    _flushPending = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushInterval, () => unawaited(_flushNow()));
  }

  /// Replace the entire settings map and schedule a coalesced flush.
  /// Kept for backwards compatibility — most callers should use [set].
  static Future<void> save(Map<String, dynamic> settings) async {
    _cache = settings;
    _scheduleFlush();
    return _saveGuard;
  }

  /// Set a single key and schedule a coalesced flush. The in-memory cache
  /// is updated synchronously so subsequent `get()` returns the new value
  /// immediately.
  static Future<void> set(String key, dynamic value) async {
    final settings = await load();
    settings[key] = value;
    _scheduleFlush();
  }

  /// Force an immediate flush, bypassing the coalescing timer. Use this
  /// before risky operations (osascript elevation, app quit) where you
  /// can't afford to lose the write.
  static Future<void> flush() async {
    _flushTimer?.cancel();
    if (_flushPending || _cache != null) {
      await _flushNow();
    }
  }

  /// Like [set] but flushes immediately. Use only when latency matters
  /// (e.g. about to trigger a privileged operation that may kill the app).
  static Future<void> setImmediate(String key, dynamic value) async {
    final settings = await load();
    settings[key] = value;
    await _flushNow();
  }

  static Future<T?> get<T>(String key) async {
    final settings = await load();
    return settings[key] as T?;
  }

  // ── Accent color ─────────────────────────────────────────────────────────

  /// Default accent: Blue-500 (#3B82F6), stored as hex string without '#'.
  static const _defaultAccentHex = '3B82F6';

  static Future<String> getAccentColor() async {
    return (await get<String>('accentColor')) ?? _defaultAccentHex;
  }

  static Future<void> setAccentColor(String hex) async {
    await set('accentColor', hex);
  }

  // ── Subscription sync interval ──────────────────────────────────────────

  /// Interval in hours: 0 = disabled, 1, 6, 12, 24, 48.
  static Future<int> getSubSyncInterval() async {
    return (await get<int>('subSyncInterval')) ?? 6;
  }

  static Future<void> setSubSyncInterval(int hours) async {
    await set('subSyncInterval', hours);
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

  // ── Scene mode (daily / ai / streaming / gaming) ────────────────────────

  static Future<String> getSceneMode() async {
    return (await get<String>('sceneMode')) ?? 'daily';
  }

  static Future<void> setSceneMode(String mode) async {
    await set('sceneMode', mode);
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

  // ── Desktop TUN stack (mixed / system / gvisor) ─────────────────────────

  static Future<String> getDesktopTunStack() async {
    return (await get<String>('desktopTunStack')) ?? 'mixed';
  }

  static Future<void> setDesktopTunStack(String stack) async {
    await set('desktopTunStack', stack);
  }

  // ── Desktop TUN bypass (route exclusion) ────────────────────────────────

  /// Get TUN bypass addresses (IP-CIDR list, e.g. ["192.168.0.0/16"]).
  static Future<List<String>> getTunBypassAddresses() async {
    final raw = await get<List<dynamic>>('tunBypassAddresses');
    return raw?.cast<String>() ?? [];
  }

  static Future<void> setTunBypassAddresses(List<String> addrs) async {
    await set('tunBypassAddresses', addrs);
  }

  /// Get TUN bypass processes (process name list, e.g. ["ssh", "Parallels"]).
  static Future<List<String>> getTunBypassProcesses() async {
    final raw = await get<List<dynamic>>('tunBypassProcesses');
    return raw?.cast<String>() ?? [];
  }

  static Future<void> setTunBypassProcesses(List<String> procs) async {
    await set('tunBypassProcesses', procs);
  }

  // ── Desktop Service Mode auth token / port / socket ─────────────────────
  // macOS / Linux: socket path is the auth boundary (peer-cred check on
  //                the helper side); token + port are unused.
  // Windows:       token + port (HTTP loopback) is the auth boundary; socket
  //                path is unused.

  static Future<String?> getServiceAuthToken() async {
    return get<String>('serviceAuthToken');
  }

  static Future<void> setServiceAuthToken(String? token) async {
    await set('serviceAuthToken', token);
  }

  static Future<int?> getServicePort() async {
    return get<int>('servicePort');
  }

  static Future<void> setServicePort(int port) async {
    await set('servicePort', port);
  }

  /// Absolute path to the Unix domain socket the helper listens on
  /// (macOS / Linux only). Set at install time, read by the Dart client
  /// on every IPC call.
  static Future<String?> getServiceSocketPath() async {
    return get<String>('serviceSocketPath');
  }

  static Future<void> setServiceSocketPath(String? path) async {
    await set('serviceSocketPath', path);
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

  // ── Android Quick Settings tile — show node/region in subtitle ───────────
  //
  // When on, the tile subtitle reads "🇭🇰 香港" instead of "已连接". Default
  // is off because the Quick Settings panel is visible to anyone who pulls
  // down the notification shade, and the user may not want the node
  // visible there.

  static Future<bool> getTileShowNodeInfo() async {
    return (await get<bool>('tileShowNodeInfo')) ?? false;
  }

  static Future<void> setTileShowNodeInfo(bool value) async {
    await set('tileShowNodeInfo', value);
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
      'up': (settings['traffic_up_$key'] as num?)?.toInt() ?? 0,
      'down': (settings['traffic_down_$key'] as num?)?.toInt() ?? 0,
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

  // ── Smart Select cache ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getSmartSelectCache() async {
    final settings = await load();
    final raw = settings['smartSelectCache'];
    if (raw is Map<String, dynamic>) return raw;
    return null;
  }

  static Future<void> setSmartSelectCache(Map<String, dynamic> cache) async {
    await set('smartSelectCache', cache);
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
    return list.map((e) => (e as num).toInt()).toList();
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

  // ── Anonymous telemetry (opt-in, default OFF) ───────────────────────────

  static Future<bool> getTelemetryEnabled() async =>
      (await get<bool>('telemetryEnabled')) ?? false;

  static Future<void> setTelemetryEnabled(bool v) =>
      set('telemetryEnabled', v);
}
