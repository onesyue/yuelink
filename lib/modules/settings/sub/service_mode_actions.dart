import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/providers/core_provider.dart';
import '../../../core/service/service_manager.dart';
import '../../../core/service/service_mode_provider.dart';
import '../../../core/service/service_models.dart';
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

  /// Installs the privileged helper, refreshes status, then brings the
  /// core up (respecting userStoppedProvider). Throws on install failure.
  /// Returns the post-apply warning (null = OK).
  Future<String?> install() async {
    await ServiceManager.install();
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
    refresh();
    return applyImmediately();
  }

  /// After a successful install/update, put the core into the right
  /// state without forcing the user back to the dashboard:
  ///   - running  → restart (so service mode takes effect)
  ///   - stopped  → start (the install itself is an implicit "I want TUN")
  /// Respects an explicit user-stop in this session.
  ///
  /// 1.5 s grace lets the freshly-elevated helper bind `127.0.0.1:9090`,
  /// then retries once after 2 s. Any failure writes EventLog and returns
  /// a non-null warning for the caller to display.
  Future<String?> applyImmediately() async {
    try {
      final activeId = _ref.read(activeProfileIdProvider);
      if (activeId == null) return null;
      final initialStatus = _ref.read(coreStatusProvider);
      final userStopped = _ref.read(userStoppedProvider);
      if (initialStatus == CoreStatus.stopped && userStopped) return null;

      final config = await ProfileService.loadConfig(activeId);
      if (config == null) return null;

      await Future.delayed(const Duration(milliseconds: 1500));

      final actions = _ref.read(coreActionsProvider);
      Future<bool> attempt() {
        final status = _ref.read(coreStatusProvider);
        return status == CoreStatus.running
            ? actions.restart(config)
            : actions.start(config);
      }

      bool ok = await attempt();
      if (!ok) {
        EventLog.write(
            '[Service] post-install start failed once, retrying after 2 s');
        await Future.delayed(const Duration(seconds: 2));
        ok = await attempt();
      }
      if (!ok) {
        EventLog.write('[Service] post-install start failed after retry');
        return '服务已安装，但内核启动失败。请在主页点击"开始连接"重试。';
      }
      return null;
    } catch (e) {
      EventLog.write('[Service] post-install start threw: $e');
      return '服务已安装，但内核启动失败：${e.toString().split('\n').first}';
    }
  }

  /// Pure description — no `ref` access, safe to call from any widget.
  static String describe(
    S s,
    AsyncValue<DesktopServiceInfo> serviceInfo,
  ) {
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
