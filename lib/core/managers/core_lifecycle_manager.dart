import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants.dart';
import '../../core/kernel/core_manager.dart';
import '../../core/storage/settings_service.dart';
import '../../domain/models/traffic.dart';
import '../../domain/models/traffic_history.dart';
import '../../i18n/app_strings.dart';
import '../providers/core_provider.dart';
import '../../shared/app_notifier.dart';
import '../../shared/event_log.dart';
import '../../shared/nps_service.dart';
import '../../shared/telemetry.dart';
import '../service/service_manager.dart';
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
      '[CoreLifecycle] start() called, config length: ${configYaml.length}',
    );
    Telemetry.event(TelemetryEvents.connectStart);
    ref.read(userStoppedProvider.notifier).state = false;
    ref.read(coreStatusProvider.notifier).state = CoreStatus.starting;
    ref.read(coreStartupErrorProvider.notifier).state = null;

    final manager = CoreManager.instance;

    // Pre-flight: desktop TUN mode REQUIRES the service helper (it's the
    // only process with enough privilege to hand the core a utun fd).
    //
    // Two-factor check (matches FlClash / CVR):
    //   1. installed — SCM / launchd / systemd registered + token present
    //   2. reachable — IPC listener actually answers within 3 s
    // Catching both here distinguishes "user never installed the helper"
    // (go install it) from "helper is registered but its listener hasn't
    // bound yet" (wait + retry — the post-install race that used to force
    // users to 'refresh once then click connect').
    final connMode = ref.read(connectionModeProvider);
    if (connMode == 'tun' &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      final installed = await ServiceManager.isInstalled();
      if (!installed) {
        ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
        const detail =
            'TUN 模式需要安装"服务模式"辅助程序。\n'
            '请前往设置 → 连接修复 → 安装服务模式，然后再连接。';
        ref.read(coreStartupErrorProvider.notifier).state = detail;
        AppNotifier.error(detail);
        EventLog.write('[Core] connect_fail reason=service_not_installed');
        Telemetry.event(
          TelemetryEvents.connectFailed,
          priority: true,
          props: {'step': 'preflight_service_check'},
        );
        return false;
      }
      // Reachability is enforced downstream by the `waitService` step
      // inside _startDesktopServiceMode (10 s budget — sized for Windows
      // cold start + Defender scan). No need to double-gate here.
    }

    try {
      final bypassAddrs = await SettingsService.getTunBypassAddresses();
      final bypassProcs = await SettingsService.getTunBypassProcesses();

      final ok = await manager.start(
        configYaml,
        connectionMode: connMode,
        desktopTunStack: ref.read(desktopTunStackProvider),
        tunBypassAddresses: bypassAddrs,
        tunBypassProcesses: bypassProcs,
        quicRejectPolicy: ref.read(quicPolicyProvider),
      );
      if (!ok) {
        ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
        final report = manager.lastReport;
        final detail = report?.failureSummary ?? S.current.errCoreStartFailed;
        ref.read(coreStartupErrorProvider.notifier).state = detail;
        EventLog.write(
          '[Core] connect_fail detail=${detail.split('\n').first}',
        );
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
      // First-ever successful connect becomes the NPS anchor (24h later).
      unawaited(NpsService.markFirstConnect());
      AppNotifier.success(S.current.msgConnected);

      // Apply routing mode (non-blocking — errors logged, not thrown)
      await _applyRoutingMode(manager);

      // Apply log-level — must run AFTER start, because subscription configs
      // typically include `log-level: info` which overrides our setting
      // otherwise, producing 13k+ warning lines per session (mihomo logs
      // every L4 connection at warn level). Fire-and-forget; if it fails
      // the only consequence is noisier logs, not a broken connection.
      unawaited(_applyLogLevel(manager));

      // System proxy or TUN DNS (desktop only). `connMode` was captured
      // at the top of start() — re-reading here would risk a race if the
      // user flipped the setting mid-connect.
      if (!manager.isMockMode &&
          (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        if (connMode == 'tun' && Platform.isMacOS) {
          await SystemProxyManager.setTunDns();
        } else if (connMode == 'systemProxy' &&
            ref.read(systemProxyOnConnectProvider)) {
          await applySystemProxy();
        }
      }

      // Initial proxy-data fetch is handled by ProxyGroupsNotifier's own
      // listener on coreStatusProvider — it fires on the stopped/other
      // → running transition that coreStatusProvider now holds after
      // CoreManager.start() returns. This keeps lifecycle_manager free
      // of any modules/ import.
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

  /// Push the user-saved log level to the running core so a subscription's
  /// `log-level: info` can't override our quieter default. Never throws.
  Future<void> _applyLogLevel(CoreManager manager) async {
    try {
      final level = ref.read(logLevelProvider);
      await manager.api.setLogLevel(level);
    } catch (e) {
      debugPrint('[CoreLifecycle] setLogLevel error: $e');
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
        '[CoreLifecycle] routingMode: saved=$savedMode, actual=$actual',
      );
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
      // delay-state wipe is handled by _delayResetSub in main.dart (listens
      // for coreStatusProvider → stopped transition).
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
            'mtu': AppConstants.defaultTunMtu,
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

  /// Full core restart — stop + start with the same config. Used as the
  /// last-resort recovery path when mihomo's internal state goes stale
  /// (delay tests all time out, DNS resolver stuck, connection pool wedged).
  /// Cheaper than rebuilding the VPN profile; doesn't touch subscriptions.
  Future<bool> restart(String configYaml) async {
    if (CoreManager.instance.isRunning) {
      await stop();
    }
    final ok = await start(configYaml);
    if (ok) Telemetry.event(TelemetryEvents.coreRestarted);
    return ok;
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
