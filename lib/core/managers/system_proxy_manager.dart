import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../shared/error_logger.dart';
import '../../shared/event_log.dart';
import '../storage/settings_service.dart';

/// Manages OS-level system proxy on macOS / Windows / Linux.
///
/// Pure utility class — no Riverpod state, no app dependencies.
/// Holds a couple of small static caches:
///   - verification result (60 s TTL)
///   - network services list (5 min TTL on macOS)
///
/// Was inlined in [CoreActions] before the manager split — extracted so the
/// heartbeat can call into it directly without importing the provider layer,
/// and so the proxy logic can be unit-tested in isolation.
class SystemProxyManager {
  SystemProxyManager._();

  // ── Verification cache ──────────────────────────────────────────────────
  static bool? _verifyCached;
  static DateTime? _verifyCachedAt;
  static int? _verifyCachedPort;
  static const _verifyCacheTtl = Duration(seconds: 60);

  /// Drop the verification cache so the next call to [verify] hits the OS.
  /// Call this immediately after [set] / [clear] so a previous "no" doesn't
  /// linger.
  static void invalidateVerifyCache() {
    _verifyCached = null;
    _verifyCachedAt = null;
    _verifyCachedPort = null;
  }

  // ── Network services list cache (macOS) ─────────────────────────────────
  static List<String>? _cachedNetworkServices;
  static DateTime? _networkServicesCachedAt;
  static const _networkServicesCacheTtl = Duration(minutes: 5);

  /// Drop the macOS network-services cache. Call on app resume from
  /// background or after the user toggles a network service in System
  /// Settings.
  static void invalidateNetworkServicesCache() {
    _cachedNetworkServices = null;
    _networkServicesCachedAt = null;
  }

  // ── Set system proxy ────────────────────────────────────────────────────

  // ── Dirty flag ──────────────────────────────────────────────────────────
  // Cross-session flag: set to true the moment we've asked the OS to point
  // its system proxy at us; cleared only after a successful [clear]. If the
  // app dies via SIGKILL / power loss without clearing, the OS is left with
  // a dangling 127.0.0.1:7890 and every HTTP client on the machine looks
  // broken. At next cold start [cleanupIfDirty] reasserts clear.
  static const _kDirtyFlagKey = 'systemProxyDirty';

  /// Persist the "system proxy is currently pointing at us" flag. Uses
  /// `setImmediate` so the write survives a power loss that happens
  /// microseconds after networksetup returns success.
  static Future<void> _markDirty() async {
    await SettingsService.setImmediate(_kDirtyFlagKey, true);
  }

  static Future<void> _markClean() async {
    await SettingsService.set(_kDirtyFlagKey, false);
  }

  /// Call once at app cold start (before core starts). If we crashed while
  /// holding the system proxy last session, wipe it now so the user's other
  /// HTTP clients don't see a dead 127.0.0.1:7890.
  static Future<void> cleanupIfDirty() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    final dirty = (await SettingsService.get<bool>(_kDirtyFlagKey)) ?? false;
    if (!dirty) return;
    debugPrint('[SystemProxy] dirty flag set at startup — '
        'previous session did not cleanly clear proxy; clearing now');
    await clear();
    await _markClean();
  }

  /// Configure the OS system proxy to point at 127.0.0.1:[mixedPort].
  /// Returns true on success. On macOS verifies via `scutil --proxy` after
  /// setting; on Windows updates the registry; on Linux uses gsettings/kde.
  static Future<bool> set(int mixedPort) async {
    bool ok;
    if (Platform.isMacOS) {
      ok = await _setMacOS(mixedPort);
    } else if (Platform.isWindows) {
      ok = await _setWindows(mixedPort);
    } else if (Platform.isLinux) {
      ok = await _setLinux(mixedPort);
    } else {
      return false;
    }
    if (ok) await _markDirty();
    return ok;
  }

  static Future<bool> _setMacOS(int mixedPort) async {
    final services = await _listNetworkServices();
    if (services.isEmpty) {
      debugPrint('[SystemProxy] No network services found');
      return false;
    }
    var anySuccess = false;
    for (final svc in services) {
      try {
        final results = await Future.wait([
          Process.run('networksetup',
              ['-setwebproxy', svc, '127.0.0.1', '$mixedPort']),
          Process.run('networksetup',
              ['-setsecurewebproxy', svc, '127.0.0.1', '$mixedPort']),
          Process.run('networksetup',
              ['-setsocksfirewallproxy', svc, '127.0.0.1', '$mixedPort']),
        ]);
        final allOk = results.every((r) => r.exitCode == 0);
        if (!allOk) {
          for (final r in results) {
            if (r.exitCode != 0) {
              debugPrint('[SystemProxy] networksetup failed for $svc: '
                  'exit=${r.exitCode} stderr=${r.stderr}');
            }
          }
        }
        await Future.wait([
          Process.run('networksetup', ['-setwebproxystate', svc, 'on']),
          Process.run('networksetup', ['-setsecurewebproxystate', svc, 'on']),
          Process.run(
              'networksetup', ['-setsocksfirewallproxystate', svc, 'on']),
        ]);
        if (allOk) anySuccess = true;
      } catch (e) {
        debugPrint('[SystemProxy] Failed to set proxy for $svc: $e');
        EventLog.write('[SysProxy] setMacOS svc=$svc err=$e');
      }
    }
    if (anySuccess) {
      invalidateVerifyCache();
      final verified = await verify(mixedPort);
      if (!verified) {
        debugPrint('[SystemProxy] WARNING: proxy set commands succeeded '
            'but verification failed');
      }
      return verified;
    }
    return false;
  }

  static Future<bool> _setWindows(int mixedPort) async {
    const regKey =
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    final r1 = await Process.run('reg', [
      'add', regKey, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f',
    ]);
    final r2 = await Process.run('reg', [
      'add', regKey, '/v', 'ProxyServer', '/t', 'REG_SZ',
      '/d', '127.0.0.1:$mixedPort', '/f',
    ]);
    final r3 = await Process.run('reg', [
      'add', regKey, '/v', 'ProxyOverride', '/t', 'REG_SZ',
      '/d',
      'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>',
      '/f',
    ]);
    if (r1.exitCode != 0 || r2.exitCode != 0) {
      debugPrint('[SystemProxy] Windows registry update failed: '
          'r1=${r1.exitCode} r2=${r2.exitCode} r3=${r3.exitCode}');
      return false;
    }
    _notifyWindowsProxyChanged();
    return true;
  }

  /// Set Linux system proxy via gsettings (GNOME) or kwriteconfig (KDE).
  static Future<bool> _setLinux(int mixedPort) async {
    // Try GNOME gsettings first (works on GNOME, Cinnamon, Budgie, Unity)
    try {
      final r1 = await Process.run('gsettings', [
        'set', 'org.gnome.system.proxy', 'mode', "'manual'",
      ]);
      if (r1.exitCode == 0) {
        await Future.wait([
          Process.run('gsettings', [
            'set', 'org.gnome.system.proxy.http', 'host', "'127.0.0.1'",
          ]),
          Process.run('gsettings', [
            'set', 'org.gnome.system.proxy.http', 'port', '$mixedPort',
          ]),
          Process.run('gsettings', [
            'set', 'org.gnome.system.proxy.https', 'host', "'127.0.0.1'",
          ]),
          Process.run('gsettings', [
            'set', 'org.gnome.system.proxy.https', 'port', '$mixedPort',
          ]),
          Process.run('gsettings', [
            'set', 'org.gnome.system.proxy.socks', 'host', "'127.0.0.1'",
          ]),
          Process.run('gsettings', [
            'set', 'org.gnome.system.proxy.socks', 'port', '$mixedPort',
          ]),
        ]);
        debugPrint('[SystemProxy] Linux GNOME proxy set to port $mixedPort');
        return true;
      }
    } catch (e) {
      debugPrint('[SystemProxy] gsettings not available: $e');
      EventLog.write('[SysProxy] setLinux gsettings_unavailable err=$e');
    }

    // Fallback: KDE kwriteconfig5/6
    for (final cmd in ['kwriteconfig6', 'kwriteconfig5']) {
      try {
        final r = await Process.run(cmd, [
          '--file', 'kioslaverc',
          '--group', 'Proxy Settings',
          '--key', 'ProxyType', '1',
        ]);
        if (r.exitCode == 0) {
          await Future.wait([
            Process.run(cmd, [
              '--file', 'kioslaverc',
              '--group', 'Proxy Settings',
              '--key', 'httpProxy', 'http://127.0.0.1:$mixedPort',
            ]),
            Process.run(cmd, [
              '--file', 'kioslaverc',
              '--group', 'Proxy Settings',
              '--key', 'httpsProxy', 'http://127.0.0.1:$mixedPort',
            ]),
            Process.run(cmd, [
              '--file', 'kioslaverc',
              '--group', 'Proxy Settings',
              '--key', 'socksProxy', 'socks://127.0.0.1:$mixedPort',
            ]),
          ]);
          // Notify KDE to reload
          try {
            await Process.run('dbus-send', [
              '--type=signal',
              '/KIO/Scheduler',
              'org.kde.KIO.Scheduler.reparseSlaveConfiguration',
              'string:',
            ]);
          } catch (e) {
            EventLog.write('[SysProxy] setLinux dbus_notify err=$e');
          }
          debugPrint('[SystemProxy] Linux KDE proxy set via $cmd');
          return true;
        }
      } catch (e) {
        EventLog.write('[SysProxy] setLinux kde_cmd=$cmd err=$e');
        continue;
      }
    }

    debugPrint('[SystemProxy] Linux: no supported desktop environment found');
    return false;
  }

  // ── Clear system proxy ──────────────────────────────────────────────────

  /// Disable system proxy on macOS / Windows / Linux. Idempotent.
  /// Always clears the dirty flag even if the underlying commands fail —
  /// retry loops on a broken machine aren't useful here.
  static Future<void> clear() async {
    try {
      await _doClear();
    } finally {
      await _markClean();
    }
  }

  static Future<void> _doClear() async {
    if (Platform.isMacOS) {
      final services = await _listNetworkServices();
      for (final svc in services) {
        try {
          await Future.wait([
            Process.run('networksetup', ['-setwebproxystate', svc, 'off']),
            Process.run(
                'networksetup', ['-setsecurewebproxystate', svc, 'off']),
            Process.run(
                'networksetup', ['-setsocksfirewallproxystate', svc, 'off']),
          ]);
        } catch (e) {
          debugPrint('[SystemProxy] Failed to clear proxy for $svc: $e');
          EventLog.write('[SysProxy] clearMacOS svc=$svc err=$e');
        }
      }
    } else if (Platform.isWindows) {
      const regKey =
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
      final r = await Process.run('reg', [
        'add', regKey, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f',
      ]);
      if (r.exitCode != 0) {
        debugPrint('[SystemProxy] Windows registry clear failed: ${r.stderr}');
      }
      await Process.run('reg', ['delete', regKey, '/v', 'ProxyOverride', '/f']);
      _notifyWindowsProxyChanged();
    } else if (Platform.isLinux) {
      try {
        await Process.run('gsettings', [
          'set', 'org.gnome.system.proxy', 'mode', "'none'",
        ]);
      } catch (e) {
        EventLog.write('[SysProxy] clearLinux gsettings_unavailable err=$e');
      }
      for (final cmd in ['kwriteconfig6', 'kwriteconfig5']) {
        try {
          await Process.run(cmd, [
            '--file', 'kioslaverc',
            '--group', 'Proxy Settings',
            '--key', 'ProxyType', '0',
          ]);
        } catch (e) {
          EventLog.write('[SysProxy] clearLinux kde_cmd=$cmd err=$e');
          continue;
        }
        break;
      }
    }
  }

  // ── Verify system proxy ─────────────────────────────────────────────────

  /// Verify the OS system proxy is actually pointing to our [mixedPort].
  /// Cached for [_verifyCacheTtl] to keep heartbeat overhead minimal.
  ///
  /// macOS: parses `scutil --proxy` (one subprocess instead of N+1).
  /// Windows: reads two registry values.
  /// Linux: reads gsettings.
  static Future<bool> verify(int mixedPort) async {
    if (_verifyCached != null &&
        _verifyCachedPort == mixedPort &&
        _verifyCachedAt != null &&
        DateTime.now().difference(_verifyCachedAt!) < _verifyCacheTtl) {
      return _verifyCached!;
    }

    bool result;
    if (Platform.isMacOS) {
      result = await _verifyMacOSScutil(mixedPort);
    } else if (Platform.isWindows) {
      result = await _verifyWindowsRegistry(mixedPort);
    } else if (Platform.isLinux) {
      result = await _verifyLinuxGsettings(mixedPort);
    } else {
      result = true;
    }

    _verifyCached = result;
    _verifyCachedAt = DateTime.now();
    _verifyCachedPort = mixedPort;
    return result;
  }

  static Future<bool> _verifyMacOSScutil(int mixedPort) async {
    try {
      final r = await Process.run('scutil', ['--proxy']);
      final out = r.stdout as String;
      final httpEnabled = RegExp(r'HTTPEnable\s*:\s*1').hasMatch(out);
      final httpsEnabled = RegExp(r'HTTPSEnable\s*:\s*1').hasMatch(out);
      if (!httpEnabled && !httpsEnabled) {
        debugPrint('[SystemProxy] scutil: HTTP/HTTPS proxy not enabled');
        return false;
      }
      final portMatch = RegExp(r'HTTPPort\s*:\s*(\d+)').firstMatch(out);
      final port = portMatch != null ? int.tryParse(portMatch.group(1)!) : null;
      if (port != mixedPort) {
        debugPrint('[SystemProxy] scutil: port mismatch '
            '(got $port, expected $mixedPort)');
        return false;
      }
      return true;
    } catch (e, st) {
      debugPrint('[SystemProxy] scutil error: $e');
      EventLog.write('[SysProxy] verifyMacOS scutil_error err=$e');
      ErrorLogger.captureException(e, st,
          source: 'SystemProxyManager._verifyMacOSScutil');
      return false;
    }
  }

  static Future<bool> _verifyWindowsRegistry(int mixedPort) async {
    try {
      const regKey =
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
      final r1 =
          await Process.run('reg', ['query', regKey, '/v', 'ProxyEnable']);
      final o1 = r1.stdout as String;
      if (!o1.contains('0x1')) return false;
      final r2 =
          await Process.run('reg', ['query', regKey, '/v', 'ProxyServer']);
      final o2 = r2.stdout as String;
      if (!o2.contains('127.0.0.1:$mixedPort')) {
        debugPrint('[SystemProxy] Windows proxy changed, no longer '
            'pointing to port $mixedPort');
        return false;
      }
      return true;
    } catch (e, st) {
      debugPrint('[SystemProxy] Windows verify error: $e');
      EventLog.write('[SysProxy] verifyWindows reg_query_error err=$e');
      ErrorLogger.captureException(e, st,
          source: 'SystemProxyManager._verifyWindowsRegistry');
      return false;
    }
  }

  static Future<bool> _verifyLinuxGsettings(int mixedPort) async {
    try {
      final r = await Process.run(
        'gsettings',
        ['get', 'org.gnome.system.proxy', 'mode'],
      );
      final mode = (r.stdout as String).trim();
      if (mode != "'manual'") return false;
      final r2 = await Process.run(
        'gsettings',
        ['get', 'org.gnome.system.proxy.http', 'port'],
      );
      final port = int.tryParse((r2.stdout as String).trim()) ?? 0;
      return port == mixedPort;
    } catch (e) {
      EventLog.write('[SysProxy] verifyLinux gsettings_unavailable err=$e');
      return true; // gsettings not available — can't verify
    }
  }

  // ── macOS TUN DNS management ────────────────────────────────────────────
  // When TUN is enabled, mihomo hijacks DNS via dns-hijack: [any:53] but
  // macOS may still try to resolve via the original DNS servers configured
  // on the active interface, causing DNS leaks. We set system DNS to public
  // resolvers on TUN start and restore on TUN stop.

  static final Map<String, String> _savedDnsServers = {};

  /// Set macOS system DNS to public resolvers for TUN mode.
  static Future<void> setTunDns() async {
    if (!Platform.isMacOS) return;
    final services = await _listNetworkServices();
    _savedDnsServers.clear();
    for (final svc in services) {
      try {
        final result =
            await Process.run('networksetup', ['-getdnsservers', svc]);
        final output = (result.stdout as String).trim();
        _savedDnsServers[svc] = output;
        await Process.run('networksetup', [
          '-setdnsservers',
          svc,
          '114.114.114.114',
          '223.5.5.5',
          '8.8.8.8',
        ]);
        debugPrint(
            '[TunDns] set DNS for $svc (was: ${output.split('\n').first})');
      } catch (e) {
        debugPrint('[TunDns] failed to set DNS for $svc: $e');
        EventLog.write('[SysProxy] setTunDns svc=$svc err=$e');
      }
    }
  }

  /// Restore macOS system DNS to original values after TUN stop.
  static Future<void> restoreTunDns() async {
    if (!Platform.isMacOS) return;
    for (final entry in _savedDnsServers.entries) {
      try {
        final svc = entry.key;
        final original = entry.value;
        if (original.contains("any DNS Servers") || original.isEmpty) {
          await Process.run('networksetup', ['-setdnsservers', svc, 'Empty']);
        } else {
          final servers = original
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          await Process.run(
              'networksetup', ['-setdnsservers', svc, ...servers]);
        }
        debugPrint('[TunDns] restored DNS for $svc');
      } catch (e) {
        debugPrint('[TunDns] failed to restore DNS for ${entry.key}: $e');
        EventLog.write('[SysProxy] restoreTunDns svc=${entry.key} err=$e');
      }
    }
    _savedDnsServers.clear();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Notify WinINet/WinHTTP that system proxy settings changed. Without this,
  /// some apps won't pick up the change until restart.
  static Future<void> _notifyWindowsProxyChanged() async {
    const ps = 'Add-Type -TypeDefinition @"'
        '\nusing System; using System.Runtime.InteropServices;'
        '\npublic class WinINet {'
        '\n  [DllImport("wininet.dll", SetLastError=true)]'
        '\n  public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);'
        '\n}'
        '\n"@;'
        '\n[WinINet]::InternetSetOption([IntPtr]::Zero,39,[IntPtr]::Zero,0);'
        '\n[WinINet]::InternetSetOption([IntPtr]::Zero,37,[IntPtr]::Zero,0)';
    try {
      await Process.run('powershell', ['-NoProfile', '-Command', ps]);
    } catch (e) {
      EventLog.write('[SysProxy] notifyWindowsProxyChanged err=$e');
    }
  }

  /// Enumerate active network services on macOS, with a 5-minute cache.
  static Future<List<String>> _listNetworkServices() async {
    if (_cachedNetworkServices != null &&
        _networkServicesCachedAt != null &&
        DateTime.now().difference(_networkServicesCachedAt!) <
            _networkServicesCacheTtl) {
      return _cachedNetworkServices!;
    }
    try {
      final result =
          await Process.run('networksetup', ['-listallnetworkservices']);
      final services = (result.stdout as String)
          .split('\n')
          .skip(1) // First line is the header notice
          .map((l) => l.startsWith('*') ? l.substring(1).trim() : l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      _cachedNetworkServices = services;
      _networkServicesCachedAt = DateTime.now();
      return services;
    } catch (e, st) {
      // `networksetup` ships with macOS — reaching this branch means the
      // user's system is broken in an unusual way. Falling back to
      // ['Wi-Fi'] means Ethernet/VPN interfaces will silently miss the
      // proxy setting; surface the reason so "proxy on but some traffic
      // bypasses" is debuggable.
      debugPrint('[SystemProxy] networksetup -listallnetworkservices failed: '
          '$e — falling back to [Wi-Fi]');
      EventLog.write('[SysProxy] listNetworkServices fallback_to_wifi err=$e');
      ErrorLogger.captureException(e, st,
          source: 'SystemProxyManager._listNetworkServices');
      return ['Wi-Fi'];
    }
  }
}
