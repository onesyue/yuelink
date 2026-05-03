import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants.dart';
import '../../core/kernel/core_manager.dart';
import '../../core/profile/profile_service.dart';
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
import '../tun/desktop_tun_diagnostics.dart';
import '../tun/desktop_tun_state.dart';
import '../tun/desktop_tun_telemetry.dart';
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

  static Future<void> _operationQueue = Future<void>.value();

  /// Queue a low-level core stop that is triggered by failure recovery rather
  /// than by an explicit user disconnect.
  ///
  /// Recovery paths must not call [stop], because that marks
  /// `manualStopped=true` and suppresses later auto-recovery. They also must
  /// not call `CoreManager.instance.stop()` directly, because doing so can race
  /// with a user-driven start / hot-switch operation. This helper gives
  /// recovery code the same serialization guarantee without changing user
  /// intent state.
  static Future<void> stopCoreForRecovery() {
    return _runExclusiveStatic(
      'recoveryStop',
      () => CoreManager.instance.stop(),
    );
  }

  static Future<T> _runExclusiveStatic<T>(
    String operation,
    Future<T> Function() body,
  ) {
    final completer = Completer<T>();
    final queuedAt = DateTime.now();
    _operationQueue = _operationQueue
        .catchError((_) {
          // Keep the lifecycle queue alive after a failed previous operation.
        })
        .then((_) async {
          final waitMs = DateTime.now().difference(queuedAt).inMilliseconds;
          EventLog.write(
            '[CoreLifecycle] op_begin op=$operation waitMs=$waitMs',
          );
          try {
            final result = await body();
            EventLog.write('[CoreLifecycle] op_end op=$operation');
            if (!completer.isCompleted) completer.complete(result);
          } catch (e, st) {
            EventLog.write(
              '[CoreLifecycle] op_error op=$operation '
              'error=${e.toString().split('\n').first}',
            );
            if (!completer.isCompleted) completer.completeError(e, st);
          }
        });
    return completer.future;
  }

  Future<T> _runExclusive<T>(String operation, Future<T> Function() body) {
    final completer = Completer<T>();
    final queuedAt = DateTime.now();
    _operationQueue = _operationQueue
        .catchError((_) {
          // Keep the lifecycle queue alive after a failed previous operation.
        })
        .then((_) async {
          final waitMs = DateTime.now().difference(queuedAt).inMilliseconds;
          final status = ref.read(coreStatusProvider);
          EventLog.write(
            '[CoreLifecycle] op_begin op=$operation status=${status.name} '
            'waitMs=$waitMs',
          );
          try {
            final result = await body();
            EventLog.write(
              '[CoreLifecycle] op_end op=$operation '
              'status=${ref.read(coreStatusProvider).name}',
            );
            if (!completer.isCompleted) completer.complete(result);
          } catch (e, st) {
            EventLog.write(
              '[CoreLifecycle] op_error op=$operation '
              'error=${e.toString().split('\n').first}',
            );
            if (!completer.isCompleted) completer.completeError(e, st);
          }
        });
    return completer.future;
  }

  Future<bool> start(String configYaml) {
    return _runExclusive('start', () => _startUnlocked(configYaml));
  }

  Future<bool> _startUnlocked(String configYaml) async {
    final startWatch = Stopwatch()..start();
    debugPrint(
      '[CoreLifecycle] start() called, config length: ${configYaml.length}',
    );
    Telemetry.event(TelemetryEvents.connectStart);
    ref.read(userStoppedProvider.notifier).set(false);
    // Clear the persisted stop flag IMMEDIATELY. The previous debounced
    // write opened a resume-race: if the user backgrounded mid-start
    // (window lost focus, system sheet, etc.), `_onAppResumed` would
    // read the still-stale `true`, hydrate `userStoppedProvider` back
    // to true, and `displayCoreStatusProvider` would surface `stopped`
    // even after a successful start — UI showed "未连接" with mihomo
    // actually running. Reported on macOS 2026-04-28. The disk write
    // costs a few ms; the race costs user trust.
    await SettingsService.setManualStopped(false);
    ref.read(coreStatusProvider.notifier).set(CoreStatus.starting);
    ref.read(coreStartupErrorProvider.notifier).set(null);

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
    final isDesktopTun =
        connMode == 'tun' &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    if (isDesktopTun) {
      DesktopTunTelemetry.startAttempt(
        platform: Platform.operatingSystem,
        mode: 'tun',
        tunStack: ref.read(desktopTunStackProvider),
      );
    }
    if (connMode == 'tun' &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      final installed = await ServiceManager.isInstalled();
      if (!installed) {
        ref.read(coreStatusProvider.notifier).set(CoreStatus.stopped);
        ref.read(desktopTunHealthProvider.notifier).set(null);
        const detail =
            'TUN 模式需要安装"服务模式"辅助程序。\n'
            '请前往设置 → 连接修复 → 桌面 TUN → 安装服务，然后再连接。';
        ref.read(coreStartupErrorProvider.notifier).set(detail);
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
        ref.read(coreStatusProvider.notifier).set(CoreStatus.stopped);
        final report = manager.lastReport;
        final detail = report?.failureSummary ?? S.current.errCoreStartFailed;
        ref.read(coreStartupErrorProvider.notifier).set(detail);
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
        if (connMode == 'tun') {
          // TUN and system proxy must not fight. Clearing first also prevents
          // the later TUN verification probes from accidentally succeeding
          // through a stale 127.0.0.1 system proxy.
          await SystemProxyManager.clear();
          if (Platform.isMacOS) {
            await SystemProxyManager.setTunDns();
          }
        } else if (connMode == 'systemProxy' &&
            ref.read(systemProxyOnConnectProvider)) {
          await applySystemProxy();
        }
      }

      if (isDesktopTun && !manager.isMockMode) {
        final snapshot = await DesktopTunDiagnostics.instance.inspect(
          api: manager.api,
          mixedPort: manager.mixedPort,
          mode: connMode,
          tunStack: ref.read(desktopTunStackProvider),
        );
        final finalSnapshot = snapshot.copyWith(
          elapsedMs: startWatch.elapsedMilliseconds,
        );
        ref.read(desktopTunHealthProvider.notifier).set(finalSnapshot);
        DesktopTunTelemetry.startResult(finalSnapshot);
        DesktopTunTelemetry.healthSnapshot(finalSnapshot);
        if (!finalSnapshot.runningVerified) {
          ref.read(coreStatusProvider.notifier).set(CoreStatus.degraded);
          ref
              .read(coreStartupErrorProvider.notifier)
              .set(finalSnapshot.userMessage);
          EventLog.write(
            '[Core] desktop_tun_degraded '
            'error=${finalSnapshot.errorClass} state=${finalSnapshot.state.wireName}',
          );
          AppNotifier.warning(finalSnapshot.userMessage);
          return true;
        }
      } else {
        ref.read(desktopTunHealthProvider.notifier).set(null);
      }

      ref.read(coreStatusProvider.notifier).set(CoreStatus.running);
      EventLog.write('[Core] connect_ok');
      Telemetry.event(TelemetryEvents.connectOk);
      // First-ever successful connect becomes the NPS anchor (24h later).
      unawaited(NpsService.markFirstConnect());
      AppNotifier.success(S.current.msgConnected);

      // Initial proxy-data fetch is handled by ProxyGroupsNotifier's
      // `ref.listen<CoreStatus>` (registered in its build()), plus an
      // immediate refresh in build() when status is already running at
      // construction time. Together they cover both orderings — listener
      // registered before the status flip (normal user-press path) and
      // notifier first watched after the flip already happened
      // (cold-start auto-connect / resume into running). Keeps
      // lifecycle_manager free of any modules/ import.
      return true;
    } catch (e, st) {
      debugPrint('[CoreLifecycle] start() error: $e\n$st');
      ref.read(coreStatusProvider.notifier).set(CoreStatus.stopped);
      final report = manager.lastReport;
      final detail = report?.failureSummary ?? e.toString().split('\n').first;
      ref.read(coreStartupErrorProvider.notifier).set(detail);
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
        ref.read(routingModeProvider.notifier).set(actual);
      }
    } catch (e) {
      debugPrint('[CoreLifecycle] setRoutingMode error: $e');
    }
  }

  Future<void> stop() {
    return _runExclusive('stop', _stopUnlocked);
  }

  Future<void> _stopUnlocked() async {
    ref.read(userStoppedProvider.notifier).set(true);
    // Persist the stop intent BEFORE doing any teardown work — engine
    // recreate / process kill can happen at any point during a normal
    // disconnect (Android background-kill is the canonical case), and the
    // resume path needs to see this flag even if we never got to finally{}.
    // setImmediate is required: the coalesced flush would lose this write
    // if the user puts the app away within the flush window.
    await SettingsService.setManualStopped(true);
    ref.read(coreStatusProvider.notifier).set(CoreStatus.stopping);
    final wasDesktopTun =
        ref.read(connectionModeProvider) == 'tun' &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

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
      if (wasDesktopTun) {
        final cleanup = await DesktopTunDiagnostics.instance.cleanupSnapshot(
          mixedPort: manager.mixedPort,
          mode: 'tun',
          tunStack: ref.read(desktopTunStackProvider),
        );
        ref.read(desktopTunHealthProvider.notifier).set(cleanup);
        DesktopTunTelemetry.stopResult(cleanup);
        DesktopTunTelemetry.cleanupResult(cleanup);
      } else {
        ref.read(desktopTunHealthProvider.notifier).set(null);
      }

      AppNotifier.info(S.current.msgDisconnected);
    } catch (e) {
      debugPrint('[CoreLifecycle] stop error: $e');
      AppNotifier.error(S.current.errStopFailed);
    } finally {
      // Always reset state — even if stop() throws, the core is no longer
      // in a usable running state and the UI must reflect that.
      ref.read(coreStatusProvider.notifier).set(CoreStatus.stopped);
      ref.read(trafficProvider.notifier).set(const Traffic());
      ref.read(trafficHistoryProvider.notifier).set(TrafficHistory());
      ref.read(trafficHistoryVersionProvider.notifier).set(0);
      // delay-state wipe is handled by _delayResetSub in main.dart (listens
      // for coreStatusProvider → stopped transition).
    }
  }

  /// Hot-switch connection mode (TUN ↔ systemProxy) while core is running.
  ///
  /// Mobile/non-desktop can safely PATCH mihomo's `tun.enable` in place.
  /// Desktop cannot: TUN must run through the privileged helper while
  /// systemProxy can run in the app process. Crossing that boundary with a
  /// plain PATCH leaves the UI saying "TUN" while the runtime is still the
  /// old in-process core. For desktop, restart with the saved profile so the
  /// normal CoreManager.start() path chooses the right data plane.
  ///
  /// Returns whether the runtime switch actually took effect. Callers use this
  /// to revert optimistic provider/settings changes when TUN setup fails.
  Future<bool> hotSwitchConnectionMode(String newMode, {String? fallbackMode}) {
    return _runExclusive(
      'hotSwitchConnectionMode',
      () =>
          _hotSwitchConnectionModeUnlocked(newMode, fallbackMode: fallbackMode),
    );
  }

  Future<bool> _hotSwitchConnectionModeUnlocked(
    String newMode, {
    String? fallbackMode,
  }) async {
    final manager = CoreManager.instance;
    if (newMode != 'systemProxy' && newMode != 'tun') return false;
    if (!manager.isRunning || manager.isMockMode) return true;

    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        return _restartDesktopConnectionMode(
          newMode,
          fallbackMode: fallbackMode,
        );
      }

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
          return false;
        }
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
          await SystemProxyManager.clear();
        }
        if (Platform.isMacOS) {
          await SystemProxyManager.setTunDns();
        }
        AppNotifier.success(S.current.msgSwitchedToTun);
        return true;
      } else {
        final ok = await manager.api.patchConfig({
          'tun': {'enable': false},
        });
        if (!ok) {
          AppNotifier.error(S.current.errTunSwitchFailed);
          return false;
        }
        if (Platform.isMacOS) {
          await SystemProxyManager.restoreTunDns();
        }
        if ((Platform.isMacOS || Platform.isWindows || Platform.isLinux) &&
            ref.read(systemProxyOnConnectProvider)) {
          await applySystemProxy();
        }
        AppNotifier.success(S.current.msgSwitchedToSystemProxy);
        return true;
      }
    } catch (e) {
      debugPrint('[CoreLifecycle] hotSwitchConnectionMode error: $e');
      AppNotifier.error(S.current.errTunSwitchFailed);
      return false;
    }
  }

  Future<bool> _restartDesktopConnectionMode(
    String newMode, {
    String? fallbackMode,
  }) async {
    if (newMode == 'tun' && !await ServiceManager.isInstalled()) {
      const detail = 'TUN 模式需要先安装"服务模式"辅助程序。';
      AppNotifier.error(detail);
      EventLog.write('[Core] tun_switch_failed reason=service_not_installed');
      return false;
    }

    final activeId = await SettingsService.getActiveProfileId();
    if (activeId == null) {
      AppNotifier.error(S.current.errCoreStartFailed);
      EventLog.write('[Core] tun_switch_failed reason=no_active_profile');
      return false;
    }
    final config = await ProfileService.loadConfig(activeId);
    if (config == null) {
      AppNotifier.error(S.current.errCoreStartFailed);
      EventLog.write('[Core] tun_switch_failed reason=no_config');
      return false;
    }

    EventLog.write('[Core] connection_mode_restart mode=$newMode');
    final ok = await _restartUnlocked(config);
    if (!ok) {
      EventLog.write('[Core] connection_mode_restart_failed mode=$newMode');
      AppNotifier.error(S.current.errTunSwitchFailed);
      await _rollbackDesktopConnectionMode(
        config,
        newMode: newMode,
        fallbackMode: fallbackMode,
      );
    }
    return ok;
  }

  Future<void> _rollbackDesktopConnectionMode(
    String config, {
    required String newMode,
    required String? fallbackMode,
  }) async {
    if (fallbackMode == null ||
        fallbackMode == newMode ||
        (fallbackMode != 'systemProxy' && fallbackMode != 'tun')) {
      return;
    }

    EventLog.write(
      '[Core] connection_mode_rollback from=$newMode to=$fallbackMode',
    );
    ref.read(connectionModeProvider.notifier).set(fallbackMode);
    await SettingsService.setConnectionMode(fallbackMode);
    final restored = await _startUnlocked(config);
    EventLog.write(
      '[Core] connection_mode_rollback_done ok=$restored to=$fallbackMode',
    );
  }

  Future<void> toggle(String configYaml) {
    return _runExclusive('toggle', () => _toggleUnlocked(configYaml));
  }

  Future<void> _toggleUnlocked(String configYaml) async {
    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.running || status == CoreStatus.degraded) {
      await _stopUnlocked();
    } else if (status == CoreStatus.stopped) {
      await _startUnlocked(configYaml);
    }
  }

  /// Full core restart — stop + start with the same config. Used as the
  /// last-resort recovery path when mihomo's internal state goes stale
  /// (delay tests all time out, DNS resolver stuck, connection pool wedged).
  /// Cheaper than rebuilding the VPN profile; doesn't touch subscriptions.
  Future<bool> restart(String configYaml) {
    return _runExclusive('restart', () => _restartUnlocked(configYaml));
  }

  Future<bool> _restartUnlocked(String configYaml) async {
    final status = ref.read(coreStatusProvider);
    if (CoreManager.instance.isRunning ||
        status == CoreStatus.running ||
        status == CoreStatus.degraded ||
        status == CoreStatus.starting) {
      await _stopUnlocked();
    }
    final ok = await _startUnlocked(configYaml);
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
