import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ffi/core_controller.dart';
import '../domain/models/traffic.dart';
import '../domain/models/traffic_history.dart';
import '../providers/proxy_provider.dart';
import '../l10n/app_strings.dart';
import '../shared/app_notifier.dart';
import '../shared/event_log.dart';
import '../core/kernel/core_manager.dart';
import '../infrastructure/datasources/mihomo_api.dart';

// Re-export traffic stream providers and chart UI state
// (defined in modules/dashboard to avoid circular imports)
export '../modules/dashboard/providers/traffic_providers.dart';


// ------------------------------------------------------------------
// App background state (battery optimization)
// ------------------------------------------------------------------

/// True when the app is in the background (paused/hidden/inactive).
/// Stream providers watch this to pause WebSocket connections and reduce
/// heartbeat frequency, significantly reducing battery drain on Android.
final appInBackgroundProvider = StateProvider<bool>((ref) => false);

// ------------------------------------------------------------------
// Core state
// ------------------------------------------------------------------

enum CoreStatus { stopped, starting, running, stopping }

final coreStatusProvider =
    StateProvider<CoreStatus>((ref) => CoreStatus.stopped);

/// Last startup error message — shown on dashboard when core fails to start.
final coreStartupErrorProvider = StateProvider<String?>((ref) => null);

/// Whether the core is running in mock mode (no native library).
final isMockModeProvider = Provider<bool>((ref) {
  return CoreManager.instance.isMockMode;
});

/// The MihomoApi client for data operations.
final mihomoApiProvider = Provider<MihomoApi>((ref) {
  return CoreManager.instance.api;
});

// ------------------------------------------------------------------
// Settings-backed providers
// ------------------------------------------------------------------

/// Routing mode: "rule" | "global" | "direct"
final routingModeProvider = StateProvider<String>((ref) => 'rule');

/// Connection mode: "tun" | "systemProxy"
final connectionModeProvider = StateProvider<String>((ref) => 'systemProxy');

/// Log level: "info" | "debug" | "warning" | "error" | "silent"
final logLevelProvider = StateProvider<String>((ref) => 'info');

/// Whether to auto-set system proxy on connect (desktop only)
final systemProxyOnConnectProvider = StateProvider<bool>((ref) => true);

/// Whether to auto-connect on startup
final autoConnectProvider = StateProvider<bool>((ref) => false);

/// Set to true when the user explicitly stops the VPN.
/// Prevents auto-connect from re-enabling on app resume.
/// Reset on next explicit start.
final userStoppedProvider = StateProvider<bool>((ref) => false);

// ------------------------------------------------------------------
// Core actions
// ------------------------------------------------------------------

final coreActionsProvider = Provider<CoreActions>((ref) => CoreActions(ref));

class CoreActions {
  final Ref ref;
  CoreActions(this.ref);

  Future<bool> start(String configYaml) async {
    debugPrint('[CoreActions] start() called, config length: ${configYaml.length}');
    ref.read(userStoppedProvider.notifier).state = false;
    ref.read(coreStatusProvider.notifier).state = CoreStatus.starting;
    ref.read(coreStartupErrorProvider.notifier).state = null;

    final manager = CoreManager.instance;

    try {
      // Start Core — all steps (including VPN permission) are tracked inside CoreManager
      final ok = await manager.start(configYaml);
      if (!ok) {
        ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
        final report = manager.lastReport;
        final detail = report?.failureSummary ?? S.current.errCoreStartFailed;
        ref.read(coreStartupErrorProvider.notifier).state = detail;
        EventLog.write('[Core] connect_fail detail=${detail.split('\n').first}');
        AppNotifier.error(detail);
        return false;
      }

      ref.read(coreStatusProvider.notifier).state = CoreStatus.running;
      EventLog.write('[Core] connect_ok');
      AppNotifier.success(S.current.msgConnected);

      // 3. Apply routing mode (non-blocking — errors logged, not thrown)
      await _applyRoutingMode(manager);

      // 4. System proxy (desktop, real mode only — mock has no proxy port)
      if (!manager.isMockMode &&
          (Platform.isMacOS || Platform.isWindows) &&
          ref.read(systemProxyOnConnectProvider)) {
        await applySystemProxy();
      }

      // Trigger initial proxy data fetch
      ref.read(proxyGroupsProvider.notifier).refresh();

      return true;
    } catch (e, st) {
      debugPrint('[CoreActions] start() error: $e\n$st');
      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;

      // Use the startup report for a precise error message
      final report = manager.lastReport;
      final detail = report?.failureSummary ?? e.toString().split('\n').first;
      ref.read(coreStartupErrorProvider.notifier).state = detail;
      AppNotifier.error(detail);
      return false;
    }
  }

  /// Apply saved routing mode to the running core, then read back the actual
  /// mode and sync to [routingModeProvider] in case the config overrode it.
  Future<void> _applyRoutingMode(CoreManager manager) async {
    final savedMode = ref.read(routingModeProvider);
    try {
      if (savedMode != 'rule') {
        await manager.api.setRoutingMode(savedMode);
      }
      final actual = await manager.api.getRoutingMode();
      debugPrint('[CoreActions] routingMode: saved=$savedMode, actual=$actual');
      // Sync UI to what mihomo is actually running
      if (actual != savedMode) {
        ref.read(routingModeProvider.notifier).state = actual;
      }
    } catch (e) {
      debugPrint('[CoreActions] setRoutingMode error: $e');
    }
  }

  Future<void> stop() async {
    ref.read(userStoppedProvider.notifier).state = true;
    ref.read(coreStatusProvider.notifier).state = CoreStatus.stopping;

    try {
      // Always clear system proxy on stop — even if the user disabled
      // "set system proxy on connect", a previous session may have set it.
      if (Platform.isMacOS || Platform.isWindows) {
        await clearSystemProxy();
      }

      final manager = CoreManager.instance;
      await manager.stop();

      AppNotifier.info(S.current.msgDisconnected);
    } catch (e) {
      debugPrint('[CoreActions] stop error: $e');
      AppNotifier.error(S.current.errStopFailed);
    } finally {
      // Always reset state — even if stop() throws, the core is no longer
      // in a usable running state and the UI must reflect that.
      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
      ref.read(trafficProvider.notifier).state = const Traffic();
      ref.read(trafficHistoryProvider.notifier).state = TrafficHistory();
      ref.read(trafficHistoryVersionProvider.notifier).state = 0;
      // Clear delay state so stale "testing" badges don't appear after
      // subscription sync (which calls stop() + start() + refresh()).
      ref.read(delayResultsProvider.notifier).state = {};
      ref.read(delayTestingProvider.notifier).state = {};
    }
  }

  Future<void> toggle(String configYaml) async {
    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.running) {
      await stop();
    } else if (status == CoreStatus.stopped) {
      await start(configYaml);
    }
  }

  Future<bool> applySystemProxy() async {
    final port = CoreManager.instance.mixedPort;
    final ok = await _setSystemProxy(port);
    if (!ok) {
      debugPrint('[CoreActions] System proxy setup failed for port $port');
      AppNotifier.warning(S.current.errSystemProxyFailed);
    }
    return ok;
  }

  Future<void> clearSystemProxy() async {
    await clearSystemProxyStatic();
  }

  static Future<bool> _setSystemProxy(int mixedPort) async {
    if (Platform.isMacOS) {
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
          // Enable each proxy type
          await Future.wait([
            Process.run('networksetup', ['-setwebproxystate', svc, 'on']),
            Process.run('networksetup',
                ['-setsecurewebproxystate', svc, 'on']),
            Process.run('networksetup',
                ['-setsocksfirewallproxystate', svc, 'on']),
          ]);
          if (allOk) anySuccess = true;
        } catch (e) {
          debugPrint('[SystemProxy] Failed to set proxy for $svc: $e');
        }
      }
      // Verify the proxy was actually set
      if (anySuccess) {
        final verified = await verifySystemProxy(mixedPort);
        if (!verified) {
          debugPrint('[SystemProxy] WARNING: proxy set commands succeeded '
              'but verification failed');
        }
        return verified;
      }
      return false;
    } else if (Platform.isWindows) {
      const regKey =
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
      final r1 = await Process.run('reg', [
        'add', regKey,
        '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f'
      ]);
      final r2 = await Process.run('reg', [
        'add', regKey,
        '/v', 'ProxyServer', '/t', 'REG_SZ',
        '/d', '127.0.0.1:$mixedPort', '/f'
      ]);
      // Bypass list: skip proxy for localhost, LAN, and local addresses
      final r3 = await Process.run('reg', [
        'add', regKey,
        '/v', 'ProxyOverride', '/t', 'REG_SZ',
        '/d', 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*'
            ';172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*'
            ';172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*'
            ';192.168.*;<local>',
        '/f'
      ]);
      if (r1.exitCode != 0 || r2.exitCode != 0) {
        debugPrint('[SystemProxy] Windows registry update failed: '
            'r1=${r1.exitCode} r2=${r2.exitCode} r3=${r3.exitCode}');
        return false;
      }
      // Notify WinINet of the proxy change so browsers pick it up immediately
      _notifyWindowsProxyChanged();
      return true;
    }
    return false;
  }

  /// Verify that system proxy is actually pointing to our port.
  /// Returns true if at least one interface has our proxy set (macOS),
  /// or the registry points to our port (Windows).
  static Future<bool> verifySystemProxy(int mixedPort) async {
    if (Platform.isMacOS) {
      try {
        final services = await _listNetworkServices();
        final verified = <String>[];
        final missing = <String>[];
        for (final svc in services) {
          final result = await Process.run(
              'networksetup', ['-getwebproxy', svc]);
          final output = result.stdout as String;
          if (output.contains('Enabled: Yes') &&
              output.contains('Port: $mixedPort')) {
            verified.add(svc);
          } else {
            missing.add(svc);
          }
        }
        if (verified.isNotEmpty) {
          debugPrint('[SystemProxy] Proxy active on: ${verified.join(', ')} '
              '(port $mixedPort)');
          if (missing.isNotEmpty) {
            debugPrint('[SystemProxy] Not set on: ${missing.join(', ')} '
                '(inactive interfaces)');
          }
          return true;
        }
        debugPrint('[SystemProxy] Verification failed: no service has '
            'proxy set to port $mixedPort');
        return false;
      } catch (e) {
        debugPrint('[SystemProxy] Verification error: $e');
        return false;
      }
    } else if (Platform.isWindows) {
      try {
        const regKey =
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
        final r1 = await Process.run('reg', ['query', regKey, '/v', 'ProxyEnable']);
        final o1 = r1.stdout as String;
        // Enabled value shows as "0x1" in reg query output
        if (!o1.contains('0x1')) return false;
        final r2 = await Process.run('reg', ['query', regKey, '/v', 'ProxyServer']);
        final o2 = r2.stdout as String;
        if (!o2.contains('127.0.0.1:$mixedPort')) {
          debugPrint('[SystemProxy] Windows proxy server changed, '
              'no longer pointing to port $mixedPort');
          return false;
        }
        return true;
      } catch (e) {
        debugPrint('[SystemProxy] Windows verification error: $e');
        return false;
      }
    }
    return true;
  }

  static Future<void> clearSystemProxyStatic() async {
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
        }
      }
    } else if (Platform.isWindows) {
      const regKey =
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
      final r = await Process.run('reg', [
        'add', regKey,
        '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f'
      ]);
      if (r.exitCode != 0) {
        debugPrint('[SystemProxy] Windows registry clear failed: ${r.stderr}');
      }
      // Also remove bypass list
      await Process.run('reg', [
        'delete', regKey, '/v', 'ProxyOverride', '/f'
      ]);
      // Notify WinINet of the proxy change
      _notifyWindowsProxyChanged();
    }
  }

  /// Notify WinINet/WinHTTP that system proxy settings changed.
  /// Without this, some apps won't pick up the change until restart.
  static Future<void> _notifyWindowsProxyChanged() async {
    // InternetSetOption with INTERNET_OPTION_SETTINGS_CHANGED (39) and
    // INTERNET_OPTION_REFRESH (37) via PowerShell P/Invoke.
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
    } catch (_) {}
  }

  /// Enumerate all active network services on macOS.
  static Future<List<String>> _listNetworkServices() async {
    try {
      final result =
          await Process.run('networksetup', ['-listallnetworkservices']);
      return (result.stdout as String)
          .split('\n')
          .skip(1) // First line is the header notice
          .map((l) => l.startsWith('*') ? l.substring(1).trim() : l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return ['Wi-Fi']; // Fallback
    }
  }
}

// ------------------------------------------------------------------
// Recovery guard — prevents heartbeat/listeners from interfering
// ------------------------------------------------------------------

/// True while Android background→foreground recovery is in progress.
/// Heartbeat and status listeners must check this before resetting state,
/// otherwise they race with the recovery logic in _onAppResumed().
final recoveryInProgressProvider = StateProvider<bool>((ref) => false);

// ------------------------------------------------------------------
// Core heartbeat — detects unexpected crashes
// ------------------------------------------------------------------

/// Periodically pings the core API while running.
/// If the API stops responding (3 consecutive failures), automatically
/// transitions state to stopped so the UI reflects the real situation.
final coreHeartbeatProvider = Provider<void>((ref) {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return;

  final manager = CoreManager.instance;
  if (manager.isMockMode) return; // mock never crashes

  // Battery optimization: reduce heartbeat frequency when app is in background.
  // 10s foreground → 60s background. Re-evaluates when appInBackgroundProvider changes.
  final inBackground = ref.watch(appInBackgroundProvider);
  final interval = Duration(seconds: inBackground ? 60 : 10);

  var failures = 0;
  var proxyCheckTick = 0;
  final timer = Timer.periodic(interval, (_) async {
    // Skip heartbeat while recovery is in progress — the recovery logic
    // handles state transitions. Without this guard, heartbeat can
    // accumulate failures during recovery and reset state prematurely.
    if (ref.read(recoveryInProgressProvider)) {
      debugPrint('[Heartbeat] skipped — recovery in progress');
      return;
    }

    // On iOS, Go core runs in the PacketTunnel extension process — FFI
    // isRunning only reflects the main process and is always false.
    // Use API availability as the sole health indicator on iOS.
    final ffiRunning = Platform.isIOS || CoreController.instance.isRunning;
    final apiOk = await manager.api.isAvailable();

    if (apiOk && ffiRunning) {
      failures = 0;

      // Every 30s on desktop, check if another proxy client stole our system proxy.
      // If detected, stop the core gracefully — let the newer client take over.
      if (Platform.isMacOS || Platform.isWindows) {
        proxyCheckTick++;
        if (proxyCheckTick >= 3) {
          proxyCheckTick = 0;
          if (ref.read(systemProxyOnConnectProvider)) {
            final port = manager.mixedPort;
            final proxyOk = await CoreActions.verifySystemProxy(port);
            if (!proxyOk) {
              debugPrint('[Heartbeat] system proxy conflict — another client took over port $port');
              AppNotifier.warning(S.current.msgSystemProxyConflict);
              ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
              ref.read(trafficProvider.notifier).state = const Traffic();
              ref.read(trafficHistoryProvider.notifier).state = TrafficHistory();
              ref.read(trafficHistoryVersionProvider.notifier).state = 0;
              manager.stop().catchError((_) {});
              failures = 0;
              return;
            }
          }
        }
      }
    } else {
      failures++;
      debugPrint('[Heartbeat] failure #$failures — '
          'ffi.isRunning=$ffiRunning, api=$apiOk');
      if (failures >= 3) {
        debugPrint('[Heartbeat] core dead, cleaning up');
        ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
        ref.read(trafficProvider.notifier).state = const Traffic();
        ref.read(trafficHistoryProvider.notifier).state = TrafficHistory();
        ref.read(trafficHistoryVersionProvider.notifier).state = 0;
        // Clear desktop system proxy to prevent dead-proxy network blackout
        if (Platform.isMacOS || Platform.isWindows) {
          CoreActions.clearSystemProxyStatic().catchError((_) {});
        }
        manager.stop().catchError((_) {});
        failures = 0;
      }
    }
  });
  ref.onDispose(() => timer.cancel());
});

// ------------------------------------------------------------------
// Traffic state (written by both heartbeat and stream activators)
// ------------------------------------------------------------------

final trafficProvider = StateProvider<Traffic>((ref) => const Traffic());

final trafficHistoryProvider =
    StateProvider<TrafficHistory>((ref) => TrafficHistory());

/// Monotonically increasing version counter for [trafficHistoryProvider].
/// Bumped on every sample add — ChartCard watches this instead of a full
/// TrafficHistory copy, saving ~3600 double copies per second.
final trafficHistoryVersionProvider = StateProvider<int>((ref) => 0);

// ------------------------------------------------------------------
// Memory usage state
// ------------------------------------------------------------------

final memoryUsageProvider = StateProvider<int>((ref) => 0);

