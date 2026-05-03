import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kernel/core_manager.dart';
import '../../core/providers/core_provider.dart';
import '../../core/storage/settings_service.dart';
import '../../i18n/app_strings.dart';
import '../../shared/app_notifier.dart';
import '../nodes/providers/nodes_providers.dart';

/// Shared routing-mode / connection-mode switch actions.
///
/// Extracted in the v1.0.21 hotfix so the dashboard HeroCard pill and
/// the tray menu (P2-6) go through exactly one implementation — prior
/// to this split the HeroCard had the only copy and the tray had no
/// quick-switch at all. Avoids the "pill and tray drift out of sync"
/// hazard that comes with duplicating the optimistic-state / persist /
/// PATCH-mihomo / revert-on-error sequence in two places.
class ModeActions {
  ModeActions._();

  /// Set routing mode to [next] (one of 'rule' / 'global' / 'direct').
  /// Idempotent — if the current mode already equals [next], no-op.
  ///
  /// Contract mirrors HeroCard._cycleRoutingMode verbatim:
  ///   1. optimistic: bump the provider so UI reflects immediately;
  ///   2. persist to SettingsService so it survives relaunch;
  ///   3. if core is running, PATCH via mihomo API;
  ///   4. on direct: close all connections so existing proxied flows
  ///      don't keep riding the old rules;
  ///   5. refresh proxy groups so the UI's current-node reflection
  ///      picks up any side effect;
  ///   6. revert everything on PATCH failure.
  ///
  /// Shows a small AppNotifier toast on success (`modeSwitched: X`)
  /// and on failure. Never throws.
  static Future<void> setRoutingMode(WidgetRef ref, String next) async {
    if (next != 'rule' && next != 'global' && next != 'direct') {
      debugPrint('[ModeActions] ignoring invalid routing mode: $next');
      return;
    }
    final current = ref.read(routingModeProvider);
    if (current == next) return;
    final s = S.current;

    ref.read(routingModeProvider.notifier).set(next);
    await SettingsService.setRoutingMode(next);

    final status = ref.read(coreStatusProvider);
    if (status != CoreStatus.running && status != CoreStatus.degraded) {
      // Not running: persistence is the whole win. No API call to make.
      return;
    }

    final label = _routingModeLabel(next, s);
    try {
      final ok = await CoreManager.instance.api.setRoutingMode(next);
      if (!ok) {
        AppNotifier.error(s.switchModeFailed);
        ref.read(routingModeProvider.notifier).set(current);
        return;
      }
      if (next == 'direct') {
        try {
          await CoreManager.instance.api.closeAllConnections();
        } catch (e) {
          debugPrint('[ModeActions] closeAllConnections on direct failed: $e');
        }
      }
      ref.read(proxyGroupsProvider.notifier).refresh();
      // Post-PATCH verify: read back the actual mode from mihomo to catch
      // the case where the API accepted our request but the core ended up
      // in a different mode (subscription with a conflicting profile
      // patch, for instance). Preserves the warning path the HeroCard had
      // before the ModeActions extraction — spotted in the P2-6 review.
      try {
        final actual = await CoreManager.instance.api.getRoutingMode();
        if (actual != next) {
          AppNotifier.warning('${s.routeModeRule}: $actual ≠ $next');
        } else {
          AppNotifier.success('${s.modeSwitched}: $label');
        }
      } catch (e) {
        debugPrint('[ModeActions] verify getRoutingMode failed: $e');
        AppNotifier.success('${s.modeSwitched}: $label');
      }
    } catch (e) {
      debugPrint('[ModeActions] setRoutingMode error: $e');
      AppNotifier.error('${s.switchModeFailed}: $e');
      ref.read(routingModeProvider.notifier).set(current);
    }
  }

  /// Set connection mode to [next] (one of 'systemProxy' / 'tun').
  /// Idempotent.
  ///
  /// Mirrors HeroCard._toggleConnectionMode: provider → persist →
  /// hotSwitchConnectionMode → revert on error. Skipping the persist
  /// step was the v1.0.20-pre Windows "click TUN pill → nothing happens"
  /// bug; keeping the exact sequence prevents regression.
  static Future<void> setConnectionMode(WidgetRef ref, String next) async {
    if (next != 'systemProxy' && next != 'tun') {
      debugPrint('[ModeActions] ignoring invalid connection mode: $next');
      return;
    }
    final current = ref.read(connectionModeProvider);
    if (current == next) return;

    ref.read(connectionModeProvider.notifier).set(next);
    await SettingsService.setConnectionMode(next);
    try {
      final ok = await ref
          .read(coreActionsProvider)
          .hotSwitchConnectionMode(next, fallbackMode: current);
      if (!ok) {
        ref.read(connectionModeProvider.notifier).set(current);
        await SettingsService.setConnectionMode(current);
      }
    } catch (e) {
      debugPrint('[ModeActions] hotSwitchConnectionMode error: $e');
      // Revert optimistic state so the UI doesn't lie about the runtime.
      ref.read(connectionModeProvider.notifier).set(current);
      await SettingsService.setConnectionMode(current);
    }
  }

  static String _routingModeLabel(String mode, S s) {
    switch (mode) {
      case 'rule':
        return s.routeModeRule;
      case 'global':
        return s.routeModeGlobal;
      case 'direct':
        return s.routeModeDirect;
      default:
        return mode;
    }
  }
}
