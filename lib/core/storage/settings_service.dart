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
  static const quicPolicyOff = 'off';
  static const quicPolicyGooglevideo = 'googlevideo';
  static const quicPolicyAll = 'all';
  static const defaultQuicPolicy = quicPolicyGooglevideo;

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

  /// Load with a hard wall-clock cap. Used by `main()` to keep
  /// `runApp()` reachable when a pathological cold-start I/O hang
  /// (Windows Defender scan, slow Keychain unlock, FUSE/SMB volume
  /// stuck) would otherwise block the Flutter root from instantiating
  /// — the "原生白屏" report that v1.0.22 P0-4 targets.
  ///
  /// Never throws. On timeout or exception, the cache is force-seeded
  /// to an empty map so subsequent [get] calls resolve to their
  /// per-getter defaults instead of re-blocking on the same hung
  /// future. Honours an existing populated cache if [load] already
  /// completed, so warm-paths are unaffected.
  static Future<Map<String, dynamic>> loadWithTimeout(Duration timeout) async {
    try {
      return await load().timeout(timeout);
    } catch (e) {
      debugPrint('[SettingsService] loadWithTimeout fallback: $e');
      _cache ??= <String, dynamic>{};
      return _cache!;
    }
  }

  /// Internal: actually write the current cache to disk. Atomic via
  /// tmp+rename. Chained on `_saveGuard` so concurrent flushes serialise.
  ///
  /// Windows note: rename fails with errno 32 ("file in use") when antivirus
  /// or another YueLink process is reading settings.json, and fails with
  /// errno 2 when the tmp has already been consumed by a previous flush
  /// (historical race before `_saveGuard` was chained). Both cases were
  /// responsible for ~55% of crash.log entries from Windows users. We now
  /// swallow the error locally, retry up to 3× with backoff, and never let
  /// a save failure propagate to UI callers — settings are best-effort and
  /// the next flush will pick up the same snapshot.
  static Future<void> _flushNow() async {
    _flushPending = false;
    final snapshot = _cache;
    if (snapshot == null) return;
    _saveGuard =
        _saveGuard.then((_) => _writeWithRetry(snapshot)).catchError((e) {
      debugPrint('[SettingsService] save failed (swallowed): $e');
    });
    return _saveGuard;
  }

  static Future<void> _writeWithRetry(Map<String, dynamic> snapshot) async {
    final file = await _getFile();
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final encoded = json.encode(snapshot);
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(encoded);
        await tmp.rename(file.path);
        return;
      } on FileSystemException catch (e) {
        lastError = e;
        // errno 2 (tmp missing) → previous flush already consumed it, retry
        // errno 32 (file in use) → antivirus/indexer has a handle, backoff
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
    // Last-resort fallback: writeAsString directly. Loses atomicity on crash
    // but is better than silently losing user settings across successive
    // flushes. Also bypasses the rename lock completely.
    try {
      await file.writeAsString(encoded, flush: true);
      debugPrint('[SettingsService] rename retries exhausted; direct write OK');
    } catch (e) {
      debugPrint('[SettingsService] rename + direct-write both failed: '
          'last_rename=$lastError direct=$e');
    }
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

  /// One-time migration (v1.0.16): force-reset persisted accent to Blue-500.
  /// Runs once per install — gated by `accentResetV1016` flag. After this
  /// fires, any subsequent user color choice persists normally.
  static Future<void> migrateAccentToBlueIfNeeded() async {
    final done = (await get<bool>('accentResetV1016')) ?? false;
    if (done) return;
    await setAccentColor(_defaultAccentHex);
    await set('accentResetV1016', true);
  }

  // ── Manual stop persistence (v1.0.21 hotfix) ────────────────────────────
  //
  // The in-memory `userStoppedProvider` survives a normal foreground/back
  // cycle but is wiped when Riverpod's ProviderScope is rebuilt — which
  // happens whenever Android kills the Flutter engine while the VPN
  // service + Go core continue running. On engine recreate the provider
  // resets to false; the resume health check then sees the still-alive
  // mihomo API and pulls the UI back to "running" — except the user had
  // explicitly tapped disconnect, so the system proxy / TUN fd are gone
  // and the network is dead. The persisted flag is the source of truth
  // across engine recreate; main.dart consults it on every resume.
  static const _kManualStopped = 'manualStopped';

  static Future<bool> getManualStopped() async =>
      (await get<bool>(_kManualStopped)) ?? false;

  /// Defaults to immediate flush — manual stop is exactly the moment the
  /// OS may kill us next (user putting the app away after disconnect),
  /// and the coalesced flush would lose the write. Pass `immediate: false`
  /// only when you've already validated the value will survive (the
  /// `false` write at start() is the typical case).
  static Future<void> setManualStopped(bool v, {bool immediate = true}) async {
    if (immediate) {
      await setImmediate(_kManualStopped, v);
    } else {
      await set(_kManualStopped, v);
    }
  }

  // ── Subscription sync interval ──────────────────────────────────────────

  /// Interval in hours: 0 = disabled, 1, 6, 12, 24, 48.
  static Future<int> getSubSyncInterval() async {
    return (await get<int>('subSyncInterval')) ?? 6;
  }

  static Future<void> setSubSyncInterval(int hours) async {
    await set('subSyncInterval', hours);
  }

  // ── Clash RESTful API secret ────────────────────────────────────────────
  // Mihomo's external-controller secret. Persisted once on first launch so
  // external tooling (yacd / metacubexd, both of which save the secret in
  // browser localStorage) doesn't need re-configuring every restart. If
  // the subscription YAML already declares a `secret:`, that value wins
  // — CoreManager reads it back via ConfigTemplate.getSecret and won't
  // overwrite the stored one.
  static Future<String?> getClashApiSecret() async {
    return get<String>('clashApiSecret');
  }

  static Future<void> setClashApiSecret(String secret) async {
    await set('clashApiSecret', secret);
  }

  // ── Theme ────────────────────────────────────────────────────────────────

  static Future<ThemeMode> getThemeMode() async {
    final value = await get<String>('themeMode');
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        // First launch — default to following the OS setting.
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

  // ── QUIC reject policy (off / googlevideo / all) ────────────────────────

  static Future<String> getQuicPolicy() async {
    return _normalizeQuicPolicy(await get<String>('quicPolicy'));
  }

  static Future<void> setQuicPolicy(String policy) async {
    await set('quicPolicy', _normalizeQuicPolicy(policy));
  }

  static String _normalizeQuicPolicy(String? policy) {
    switch (policy) {
      case quicPolicyOff:
      case quicPolicyGooglevideo:
      case quicPolicyAll:
        return policy!;
      default:
        return defaultQuicPolicy;
    }
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
    // Default `error` — mihomo's `info` / `warning` log every L4 connection
    // with `log.Warn(...)`, producing tens of thousands of lines per session.
    // A real user diag dump observed 13k+ warnings vs 1 actual crash, making
    // the real signal impossible to find. `error` keeps panics / startup
    // failures / CGO crashes visible while dropping the routing chatter.
    // Users who need verbose logs can switch via Settings → Log Level.
    return (await get<String>('logLevel')) ?? 'error';
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

  // ── Auto light-weight idle minutes (D-⑤ P4-5, desktop only) ────────────
  //
  // When > 0 and the app sits in tray (window hidden) for that many
  // minutes, lightWeightModeProvider flips true; consumers can dispose
  // heavy resources (chart timers, webview frames). 0 disables.
  // Default 0 — opt-in, since the unmount semantics are platform-fragile.

  static Future<int> getAutoLightWeightAfterMinutes() async {
    return (await get<int>('autoLightWeightAfterMinutes')) ?? 0;
  }

  static Future<void> setAutoLightWeightAfterMinutes(int value) async {
    await set('autoLightWeightAfterMinutes', value);
  }

  // ── Windows LAN compatibility mode (TUN strict-route off) ──────────────
  //
  // When true, desktop TUN config uses `strict-route: false` on Windows so
  // SMB / 远程桌面 / 网络打印机 / NAS web UI 可达内网。Default false keeps
  // the safer `strict-route: true` (yuelink's historical default).

  static Future<bool> getWindowsLanCompatibilityMode() async {
    return (await get<bool>('windowsLanCompatibilityMode')) ?? false;
  }

  static Future<void> setWindowsLanCompatibilityMode(bool value) async {
    await set('windowsLanCompatibilityMode', value);
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

  static Future<void> setTelemetryEnabled(bool v) => set('telemetryEnabled', v);

  /// Anonymous per-install client id (UUID v4). Generated lazily on first
  /// telemetry event; survives upgrades, resets on reinstall / storage wipe.
  static Future<String?> getTelemetryClientId() async =>
      get<String>('telemetryClientId');

  static Future<void> setTelemetryClientId(String v) =>
      set('telemetryClientId', v);
}
