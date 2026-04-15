import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kernel/core_manager.dart';
import '../../core/storage/settings_service.dart';
import '../../domain/models/traffic.dart';
import '../../domain/models/traffic_history.dart';
import '../../i18n/app_strings.dart';
import '../providers/core_provider.dart';
import '../../modules/nodes/providers/nodes_providers.dart';
import '../../shared/app_notifier.dart';
import '../../shared/event_log.dart';
import '../../shared/telemetry.dart';
import 'system_proxy_manager.dart';

/// Owns the connect / disconnect / hot-switch lifecycle.
///
/// Was inlined in `CoreActions` (lib/providers/core_provider.dart) before
/// the manager split. Behaviour preserved exactly: every state transition,
/// every notifier emit, every routing-mode read-back is unchanged.
///
/// `CoreActions` itself is now a thin facade over this manager — see
/// lib/providers/core_provider.dart.
class CoreLifecycleManager {
  CoreLifecycleManager(this.ref);

  final Ref ref;

  Future<bool> start(String configYaml) async {
    debugPrint(
        '[CoreLifecycle] start() called, config length: ${configYaml.length}');
    Telemetry.event(TelemetryEvents.connectStart);
    ref.read(userStoppedProvider.notifier).state = false;
    ref.read(coreStatusProvider.notifier).state = CoreStatus.starting;
    ref.read(coreStartupErrorProvider.notifier).state = null;

    final manager = CoreManager.instance;

    try {
      final bypassAddrs = await SettingsService.getTunBypassAddresses();
      final bypassProcs = await SettingsService.getTunBypassProcesses();

      final ok = await manager.start(
        configYaml,
        connectionMode: ref.read(connectionModeProvider),
        desktopTunStack: ref.read(desktopTunStackProvider),
        tunBypassAddresses: bypassAddrs,
        tunBypassProcesses: bypassProcs,
      );
      if (!ok) {
        ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
        final report = manager.lastReport;
        final detail = report?.failureSummary ?? S.current.errCoreStartFailed;
        ref.read(coreStartupErrorProvider.notifier).state = detail;
        EventLog.write(
            '[Core] connect_fail detail=${detail.split('\n').first}');
        Telemetry.event(
          TelemetryEvents.connectFailed,
          priority: true,
          props: {'step': report?.failedStep ?? 'unknown'},
        );
        AppNotifier.error(detail);
        return false;
      }

      ref.read(coreStatusProvider.notifier).state = CoreStatus.running;
      EventLog.write('[Core] connect_ok');
      Telemetry.event(TelemetryEvents.connectOk);
      AppNotifier.success(S.current.msgConnected);

      // Apply routing mode (non-blocking — errors logged, not thrown)
      await _applyRoutingMode(manager);

      // System proxy or TUN DNS (desktop only)
      final connMode = ref.read(connectionModeProvider);
      if (!manager.isMockMode &&
          (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        if (connMode == 'tun' && Platform.isMacOS) {
          await SystemProxyManager.setTunDns();
        } else if (connMode == 'systemProxy' &&
            ref.read(systemProxyOnConnectProvider)) {
          await applySystemProxy();
        }
      }

      // Trigger initial proxy data fetch
      ref.read(proxyGroupsProvider.notifier).refresh();
      return true;
    } catch (e, st) {
      debugPrint('[CoreLifecycle] start() error: $e\n$st');
      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
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
      debugPrint(
          '[CoreLifecycle] routingMode: saved=$savedMode, actual=$actual');
      if (actual != savedMode) {
        ref.read(routingModeProvider.notifier).state = actual;
      }
    } catch (e) {
      debugPrint('[CoreLifecycle] setRoutingMode error: $e');
    }
  }

  Future<void> stop() async {
    ref.read(userStoppedProvider.notifier).state = true;
    ref.read(coreStatusProvider.notifier).state = CoreStatus.stopping;

    try {
      // Always clear system proxy on stop — even if the user disabled
      // "set system proxy on connect", a previous session may have set it.
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await SystemProxyManager.clear();
      }
      if (Platform.isMacOS) {
        await SystemProxyManager.restoreTunDns();
      }

      final manager = CoreManager.instance;
      await manager.stop();

      AppNotifier.info(S.current.msgDisconnected);
    } catch (e) {
      debugPrint('[CoreLifecycle] stop error: $e');
      AppNotifier.error(S.current.errStopFailed);
    } finally {
      // Always reset state — even if stop() throws, the core is no longer
      // in a usable running state and the UI must reflect that.
      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
      ref.read(trafficProvider.notifier).state = const Traffic();
      ref.read(trafficHistoryProvider.notifier).state = TrafficHistory();
      ref.read(trafficHistoryVersionProvider.notifier).state = 0;
      ref.read(delayResultsProvider.notifier).state = {};
      ref.read(delayTestingProvider.notifier).state = {};
    }
  }

  /// Hot-switch connection mode (TUN ↔ systemProxy) while core is running.
  /// Uses mihomo PATCH /configs to toggle TUN without stop+start.
  Future<void> hotSwitchConnectionMode(String newMode) async {
    final manager = CoreManager.instance;
    if (!manager.isRunning || manager.isMockMode) return;

    try {
      if (newMode == 'tun') {
        final stack = ref.read(desktopTunStackProvider);
        final ok = await manager.api.patchConfig({
          'tun': {
            'enable': true,
            'stack': stack,
            'auto-route': true,
            'auto-detect-interface': true,
            'dns-hijack': ['any:53'],
            'mtu': 9000,
          },
        });
        if (!ok) {
          AppNotifier.error(S.current.errTunSwitchFailed);
          return;
        }
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
          await SystemProxyManager.clear();
        }
        if (Platform.isMacOS) {
          await SystemProxyManager.setTunDns();
        }
        AppNotifier.success(S.current.msgSwitchedToTun);
      } else {
        final ok = await manager.api.patchConfig({
          'tun': {'enable': false},
        });
        if (!ok) {
          AppNotifier.error(S.current.errTunSwitchFailed);
          return;
        }
        if (Platform.isMacOS) {
          await SystemProxyManager.restoreTunDns();
        }
        if ((Platform.isMacOS || Platform.isWindows || Platform.isLinux) &&
            ref.read(systemProxyOnConnectProvider)) {
          await applySystemProxy();
        }
        AppNotifier.success(S.current.msgSwitchedToSystemProxy);
      }
    } catch (e) {
      debugPrint('[CoreLifecycle] hotSwitchConnectionMode error: $e');
      AppNotifier.error(S.current.errTunSwitchFailed);
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
    final ok = await SystemProxyManager.set(port);
    if (!ok) {
      debugPrint('[CoreLifecycle] System proxy setup failed for port $port');
      AppNotifier.warning(S.current.errSystemProxyFailed);
    }
    return ok;
  }
}
