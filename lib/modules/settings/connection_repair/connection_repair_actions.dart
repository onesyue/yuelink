import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/vpn_service.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/providers/core_provider.dart';
import '../../../core/storage/settings_service.dart';
import '../../profiles/providers/profiles_providers.dart';
import '../../yue_auth/providers/yue_auth_providers.dart';

/// Riverpod-coupled orchestrations for the connection-repair page.
///
/// Pure data helpers (log-bundle assembly, redaction, probe-result
/// classification) live in `ConnectionDiagnosticsService`. UI concerns
/// (busy state, notifications, dialogs) stay in the page.
class ConnectionRepairActions {
  final Ref _ref;
  ConnectionRepairActions(this._ref);

  /// Look up the active subscription's selected profile and load its
  /// YAML. Caller is responsible for surfacing
  /// [ActiveConfigMissing.reason] as a user-visible error — this method
  /// never shows UI.
  Future<ActiveConfigResult> loadActiveConfig() async {
    final activeId =
        _ref.read(activeProfileIdProvider) ??
        await SettingsService.getActiveProfileId();
    if (activeId == null) {
      return const ActiveConfigMissing(MissingConfigReason.noActiveProfile);
    }
    final config = await ProfileService.loadConfig(activeId);
    if (config == null || config.trim().isEmpty) {
      return const ActiveConfigMissing(MissingConfigReason.configEmpty);
    }
    return ActiveConfigLoaded(config);
  }

  /// Restart the core with the active subscription's config. Returns
  /// `false` if no active config can be loaded — the caller should
  /// invoke [loadActiveConfig] first when it needs to differentiate
  /// missing-config from a generic restart failure.
  Future<bool> restartCoreWithActiveConfig() async {
    final res = await loadActiveConfig();
    if (res is! ActiveConfigLoaded) return false;
    return _ref.read(coreActionsProvider).restart(res.yaml);
  }

  /// Full repair flow: reset platform-managed VPN profile (iOS), clear
  /// stale system proxy and restore TUN DNS (desktop), re-sync the user's
  /// subscription, then load the active config and `start` the core.
  ///
  /// **Order matters.** `loadActiveConfig` MUST come after
  /// `syncSubscription` — the whole point of "one-click repair" is that a
  /// freshly synced subscription can rescue a previously empty config. A
  /// pre-flight load would block the rescue path and turn this into a
  /// no-op for users whose only problem is a stale empty config.
  Future<RepairReconnectResult> oneClickRepairAndReconnect() async {
    if (Platform.isIOS) {
      await VpnService.resetVpnProfile();
      await VpnService.clearAppGroupConfig();
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // Clear stale system proxy before reconnecting. In TUN mode this
      // avoids controller self-loop; in system-proxy mode start() will
      // reapply the proxy if "set proxy on connect" is enabled.
      await _ref.read(coreActionsProvider).clearSystemProxy();
      if (Platform.isMacOS) await CoreActions.restoreTunDns();
    }

    final token = _ref.read(authProvider).token;
    if (token != null) {
      await _ref.read(authProvider.notifier).syncSubscription();
    }

    final res = await loadActiveConfig();
    if (res is ActiveConfigMissing) {
      return RepairReconnectMissingConfig(res.reason);
    }
    final yaml = (res as ActiveConfigLoaded).yaml;
    final ok = await _ref.read(coreActionsProvider).start(yaml);
    return ok ? const RepairReconnectSuccess() : const RepairReconnectFailed();
  }

  /// Delete cached log/config files in [appDir]. Idempotent — files
  /// that don't exist are skipped silently. The directory itself is
  /// not removed.
  Future<void> clearLocalCache(Directory appDir) async {
    const targets = [
      'config.yaml',
      'startup_report.json',
      'core.log',
      'crash.log',
      'event.log',
    ];
    for (final name in targets) {
      final f = File('${appDir.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
  }
}

/// Provider for [ConnectionRepairActions]. Page reads via
/// `ref.read(connectionRepairActionsProvider)`.
final connectionRepairActionsProvider = Provider<ConnectionRepairActions>(
  (ref) => ConnectionRepairActions(ref),
);

// ── loadActiveConfig result types ────────────────────────────────────────

sealed class ActiveConfigResult {
  const ActiveConfigResult();
}

class ActiveConfigLoaded extends ActiveConfigResult {
  final String yaml;
  const ActiveConfigLoaded(this.yaml);
}

class ActiveConfigMissing extends ActiveConfigResult {
  final MissingConfigReason reason;
  const ActiveConfigMissing(this.reason);
}

enum MissingConfigReason {
  /// No subscription is currently selected — user has either never
  /// added one or hasn't picked an active one yet.
  noActiveProfile,

  /// A profile is selected but the YAML on disk is empty or whitespace-
  /// only. Usually means the subscription URL returned an empty body
  /// or sync hasn't run yet.
  configEmpty,
}

// ── oneClickRepairAndReconnect result types ──────────────────────────────

/// Outcome of [ConnectionRepairActions.oneClickRepairAndReconnect].
///
/// `MissingConfig` is reported only when the load fails *after*
/// `syncSubscription` has run — it means the user genuinely has no
/// usable subscription, not "we didn't try to fetch one".
sealed class RepairReconnectResult {
  const RepairReconnectResult();
}

class RepairReconnectSuccess extends RepairReconnectResult {
  const RepairReconnectSuccess();
}

class RepairReconnectFailed extends RepairReconnectResult {
  const RepairReconnectFailed();
}

class RepairReconnectMissingConfig extends RepairReconnectResult {
  final MissingConfigReason reason;
  const RepairReconnectMissingConfig(this.reason);
}
