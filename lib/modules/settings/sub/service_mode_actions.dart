import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/providers/core_provider.dart';
import '../../../core/service/service_manager.dart';
import '../../../core/service/service_mode_provider.dart';
import '../../../core/service/service_models.dart';
import '../../../core/storage/settings_service.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/event_log.dart';
import '../../profiles/providers/profiles_providers.dart';

/// Desktop privileged-service orchestration.
///
/// Wraps `ServiceManager` install/uninstall/update with the post-install
/// core restart dance and the describe-status helper. Callers (page,
/// future `ServiceModeSection`) own only busy-state + UI notifications —
/// every `ref`-touching side effect lives here.
///
/// Constructed per action cycle with a `WidgetRef`; stateless otherwise.
/// Throws on install/uninstall/update failures — caller surfaces the
/// error. `applyImmediately` self-logs to EventLog and returns an
/// optional warning string that the caller may present alongside success.
class ServiceModeActions {
  ServiceModeActions(this._ref);
  final WidgetRef _ref;

  void refresh() {
    _ref.read(desktopServiceRefreshProvider.notifier).state++;
  }

  /// Installs the privileged helper, marks TUN as the active user intent,
  /// refreshes status, then brings the core up. Throws on install failure.
  /// Returns the post-apply warning (null = OK).
  Future<String?> install() async {
    await ServiceManager.install();
    await _markTunInstallIntent();
    refresh();
    return applyImmediately();
  }

  /// Stops the core if running, uninstalls the helper, refreshes status.
  /// Throws on uninstall failure.
  Future<void> uninstall(CoreStatus status) async {
    if (status == CoreStatus.running) {
      await _ref.read(coreActionsProvider).stop();
    }
    await ServiceManager.uninstall();
    refresh();
  }

  /// Reinstalls over the top + core bounce. Same warning semantics as
  /// `install`. Throws on update failure.
  Future<String?> update() async {
    await ServiceManager.update();
    await _markTunInstallIntent();
    refresh();
    return applyImmediately();
  }

  /// Installing/updating the desktop helper from the TUN row is an explicit
  /// user intent to use TUN now. Do not let an earlier manual disconnect
  /// (`userStopped=true`) from P0-1 block the post-install auto-start.
  Future<void> _markTunInstallIntent() async {
    _ref.read(connectionModeProvider.notifier).state = 'tun';
    await SettingsService.setConnectionMode('tun');
    _ref.read(userStoppedProvider.notifier).state = false;
    await SettingsService.setManualStopped(false, immediate: true);
  }

  /// After a successful install/update, put the core into the right
  /// state without forcing the user back to the dashboard:
  ///   - running  → restart (so service mode takes effect)
  ///   - stopped  → start (the install itself is an implicit "I want TUN")
  /// A service install/update is treated as an explicit connect intent; this
  /// deliberately ignores a stale manual-stop flag from a previous session.
  ///
  /// 1.5 s grace lets the freshly-elevated helper bind `127.0.0.1:9090`,
  /// then retries once after 2 s. Any failure writes EventLog and returns
  /// a non-null warning for the caller to display.
  Future<String?> applyImmediately() async {
    try {
      final activeId = _ref.read(activeProfileIdProvider);
      if (activeId == null) return null;

      final config = await ProfileService.loadConfig(activeId);
      if (config == null) return null;

      // install() already waits for IPC once, but the first TUN start can still
      // race Defender/launchd/systemd warmup. Give the helper a second bounded
      // readiness window before attempting to start mihomo through it.
      final ready = await ServiceManager.isReady(
        deadline: const Duration(seconds: 12),
      );
      if (!ready) {
        EventLog.write('[Service] post-install helper not ready before start');
      }

      final actions = _ref.read(coreActionsProvider);
      Future<bool> attempt() {
        final status = _ref.read(coreStatusProvider);
        return status == CoreStatus.running
            ? actions.restart(config)
            : actions.start(config);
      }

      var ok = false;
      final retryDelays = <Duration>[
        Duration.zero,
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ];
      for (var i = 0; i < retryDelays.length; i++) {
        final delay = retryDelays[i];
        if (delay > Duration.zero) {
          EventLog.write(
            '[Service] post-install start retry=${i + 1} after=${delay.inSeconds}s',
          );
          await Future.delayed(delay);
        }
        ok = await attempt();
        if (ok) break;
      }
      if (!ok) {
        EventLog.write('[Service] post-install start failed after retries');
        return '服务已安装，但内核启动失败。请在主页点击"开始连接"重试。';
      }
      return null;
    } catch (e) {
      EventLog.write('[Service] post-install start threw: $e');
      return '服务已安装，但内核启动失败：${e.toString().split('\n').first}';
    }
  }

  /// Pure description — no `ref` access, safe to call from any widget.
  static String describe(S s, AsyncValue<DesktopServiceInfo> serviceInfo) {
    final info = serviceInfo.value;
    if (serviceInfo.isLoading && info == null) return '...';
    if (info == null || info.installed == false) {
      return s.serviceModeNotInstalled;
    }
    if (!info.reachable) {
      return info.detail?.isNotEmpty == true
          ? '${s.serviceModeUnreachable} · ${info.detail}'
          : s.serviceModeUnreachable;
    }
    if (info.needsReinstall) {
      return s.serviceModeNeedsUpdate(info.serviceVersion ?? '?');
    }
    if (info.mihomoRunning) {
      return s.serviceModeRunning(info.pid ?? 0);
    }
    return s.serviceModeIdle;
  }
}
