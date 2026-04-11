import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ffi/core_controller.dart';
import '../../core/kernel/core_manager.dart';
import '../../core/kernel/recovery_manager.dart';
import '../../i18n/app_strings.dart';
import '../providers/core_provider.dart';
import '../../modules/nodes/providers/nodes_providers.dart';
import '../../shared/app_notifier.dart';
import 'system_proxy_manager.dart';

/// Periodic core heartbeat with battery-aware throttling and ProxyGuard.
///
/// Was inlined in `coreHeartbeatProvider` (lib/providers/core_provider.dart)
/// before the manager split — extracted as a class so the timer + state
/// machine can be reasoned about (and unit-tested) in isolation.
///
/// Behaviour preserved exactly from the inlined version:
///   • 10 s interval foreground, 60 s background
///   • 3 consecutive failures → reset state via [resetCoreToStopped]
///   • Skips itself while [recoveryInProgressProvider] is true
///   • Every ~5 min in foreground (30 ticks × 10 s), runs ProxyGuard:
///     re-verifies the system proxy and restores it if another client
///     took over. After 1 failed restore, the core is force-stopped to
///     surface the conflict to the user.
class CoreHeartbeatManager {
  CoreHeartbeatManager(this.ref);

  final Ref ref;

  Timer? _timer;
  int _failures = 0;
  int _proxyCheckTick = 0;

  /// Start the heartbeat. Idempotent — repeated calls reset the timer
  /// (used when [appInBackgroundProvider] flips and the interval changes).
  void start({required bool inBackground}) {
    _timer?.cancel();
    final interval = Duration(seconds: inBackground ? 60 : 10);
    _timer = Timer.periodic(interval, (_) => _tick(inBackground: inBackground));
  }

  /// Stop the heartbeat. Idempotent.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _failures = 0;
    _proxyCheckTick = 0;
  }

  Future<void> _tick({required bool inBackground}) async {
    // Skip while recovery is in progress — the recovery logic handles
    // state transitions. Without this guard, the heartbeat can accumulate
    // failures during recovery and reset state prematurely.
    if (ref.read(recoveryInProgressProvider)) {
      debugPrint('[Heartbeat] skipped — recovery in progress');
      return;
    }

    final manager = CoreManager.instance;

    // On iOS, Go core runs in the PacketTunnel extension process — FFI
    // isRunning only reflects the main process and is always false. Use
    // API availability as the sole health indicator on iOS.
    final ffiRunning = Platform.isIOS || CoreController.instance.isRunning;
    final apiOk = await manager.api.isAvailable();

    if (apiOk && ffiRunning) {
      _failures = 0;
      await _maybeProxyGuard(inBackground: inBackground);
    } else {
      _failures++;
      debugPrint('[Heartbeat] failure #$_failures — '
          'ffi.isRunning=$ffiRunning, api=$apiOk');
      if (_failures >= 3) {
        debugPrint('[Heartbeat] core dead, cleaning up');
        resetCoreToStopped(ref);
        ref.read(delayResultsProvider.notifier).state = {};
        ref.read(delayTestingProvider.notifier).state = {};
        _failures = 0;
      }
    }
  }

  /// Re-verify the system proxy at most every 5 minutes (foreground only).
  /// Battery-conservative: subprocess fan-out only when the user can see it.
  Future<void> _maybeProxyGuard({required bool inBackground}) async {
    if (inBackground) return;
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;

    _proxyCheckTick++;
    if (_proxyCheckTick < 30) return;
    _proxyCheckTick = 0;

    final connMode = ref.read(connectionModeProvider);
    if (connMode != 'systemProxy') return;
    if (!ref.read(systemProxyOnConnectProvider)) return;

    final port = CoreManager.instance.mixedPort;
    final proxyOk = await SystemProxyManager.verify(port);
    if (proxyOk) return;

    debugPrint('[ProxyGuard] system proxy tampered — attempting restore');
    final restored = await SystemProxyManager.set(port);
    if (restored) {
      debugPrint('[ProxyGuard] system proxy restored successfully');
      return;
    }
    debugPrint('[ProxyGuard] restore failed — another client took over');
    AppNotifier.warning(S.current.msgSystemProxyConflict);
    resetCoreToStopped(ref, clearDesktopProxy: false);
    ref.read(delayResultsProvider.notifier).state = {};
    ref.read(delayTestingProvider.notifier).state = {};
    _failures = 0;
  }
}
