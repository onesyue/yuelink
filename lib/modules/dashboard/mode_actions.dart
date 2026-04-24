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

    ref.read(routingModeProvider.notifier).state = next;
    await SettingsService.setRoutingMode(next);

    if (ref.read(coreStatusProvider) != CoreStatus.running) {
      // Not running: persistence is the whole win. No API call to make.
      return;
    }

    final label = _routingModeLabel(next, s);
    try {
      final ok = await CoreManager.instance.api.setRoutingMode(next);
      if (!ok) {
        AppNotifier.error(s.switchModeFailed);
        ref.read(routingModeProvider.notifier).state = current;
        return;
      }
      if (next == 'direct') {
        try {
          await CoreManager.instance.api.closeAllConnections();
        } catch (e) {
          debugPrint(
              '[ModeActions] closeAllConnections on direct failed: $e');
        }
      }
      ref.read(proxyGroupsProvider.notifier).refresh();
      AppNotifier.success('${s.modeSwitched}: $label');
    } catch (e) {
      debugPrint('[ModeActions] setRoutingMode error: $e');
      AppNotifier.error('${s.switchModeFailed}: $e');
      ref.read(routingModeProvider.notifier).state = current;
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

    ref.read(connectionModeProvider.notifier).state = next;
    await SettingsService.setConnectionMode(next);
    try {
      await ref.read(coreActionsProvider).hotSwitchConnectionMode(next);
    } catch (e) {
      debugPrint('[ModeActions] hotSwitchConnectionMode error: $e');
      // Revert optimistic state so the UI doesn't lie about the runtime.
      ref.read(connectionModeProvider.notifier).state = current;
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
