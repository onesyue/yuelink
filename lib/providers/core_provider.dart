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
import '../core/platform/vpn_service.dart';

// Re-export traffic stream providers and chart UI state
// (defined in modules/dashboard to avoid circular imports)
export '../modules/dashboard/providers/traffic_providers.dart';

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
final autoConnectProvider = StateProvider<bool>((ref) => true);

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
      // 1. Check VPN Permission (Android only — always needed for VpnService)
      if (Platform.isAndroid && !manager.isMockMode) {
        final hasPerm = await VpnService.requestPermission();
        if (!hasPerm) {
          ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
          ref.read(coreStartupErrorProvider.notifier).state =
              'vpnPermission: ${S.current.errVpnPermission}';
          AppNotifier.error(S.current.errVpnPermission);
          return false;
        }
      }

      // 2. Start Core — all steps are tracked inside CoreManager
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

      // 4. System proxy (desktop)
      if ((Platform.isMacOS || Platform.isWindows) &&
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
      // Clear system proxy on macOS/Windows
      if ((Platform.isMacOS || Platform.isWindows) &&
          ref.read(systemProxyOnConnectProvider)) {
        await clearSystemProxy();
      }

      final manager = CoreManager.instance;
      await manager.stop();

      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
      ref.read(trafficProvider.notifier).state = const Traffic();
      ref.read(trafficHistoryProvider.notifier).state = TrafficHistory();
      AppNotifier.info(S.current.msgDisconnected);
    } catch (e) {
      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
      AppNotifier.error(S.current.errStopFailed);
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
    await _clearSystemProxy();
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
        final verified = await _verifySystemProxy(mixedPort);
        if (!verified) {
          debugPrint('[SystemProxy] WARNING: proxy set commands succeeded '
              'but verification failed');
        }
        return verified;
      }
      return false;
    } else if (Platform.isWindows) {
      final r1 = await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f'
      ]);
      final r2 = await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyServer', '/t', 'REG_SZ',
        '/d', '127.0.0.1:$mixedPort', '/f'
      ]);
      if (r1.exitCode != 0 || r2.exitCode != 0) {
        debugPrint('[SystemProxy] Windows registry update failed: '
            'r1=${r1.exitCode} r2=${r2.exitCode}');
        return false;
      }
      return true;
    }
    return false;
  }

  /// Verify that macOS system proxy is actually pointing to our port.
  /// Checks ALL network services (not just the first match) so the log
  /// shows which interfaces have the proxy enabled.
  static Future<bool> _verifySystemProxy(int mixedPort) async {
    if (!Platform.isMacOS) return true;
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
  }

  static Future<void> _clearSystemProxy() async {
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
      final r = await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f'
      ]);
      if (r.exitCode != 0) {
        debugPrint('[SystemProxy] Windows registry clear failed: ${r.stderr}');
      }
    }
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

  var failures = 0;
  final timer = Timer.periodic(const Duration(seconds: 10), (_) async {
    // On iOS, Go core runs in the PacketTunnel extension process — FFI
    // isRunning only reflects the main process and is always false.
    // Use API availability as the sole health indicator on iOS.
    final ffiRunning = Platform.isIOS || CoreController.instance.isRunning;
    final apiOk = await manager.api.isAvailable();

    if (apiOk && ffiRunning) {
      failures = 0;
    } else {
      failures++;
      debugPrint('[Heartbeat] failure #$failures — '
          'ffi.isRunning=$ffiRunning, api=$apiOk');
      if (failures >= 3) {
        debugPrint('[Heartbeat] core dead, cleaning up');
        ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
        ref.read(trafficProvider.notifier).state = const Traffic();
        ref.read(trafficHistoryProvider.notifier).state = TrafficHistory();
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

// ------------------------------------------------------------------
// Memory usage state
// ------------------------------------------------------------------

final memoryUsageProvider = StateProvider<int>((ref) => 0);

