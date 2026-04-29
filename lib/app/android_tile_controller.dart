import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/tile_service.dart';
import '../core/providers/core_provider.dart';
import '../modules/dashboard/providers/dashboard_providers.dart'
    show exitIpInfoProvider;
import '../modules/settings/providers/settings_providers.dart'
    show tileShowNodeInfoProvider;

/// Owns the Android Quick Settings tile lifecycle and state push for the
/// running app. Previously inlined in `_YueLinkAppState` (lib/main.dart,
/// ~80 lines across 4 methods).
///
/// Why extracted:
///   * Mirrors the existing `app_tray_controller.dart` split for desktop —
///     same "controller per platform integration" pattern.
///   * The tile needs to react to several providers (`coreStatusProvider`,
///     `exitIpInfoProvider`, `tileShowNodeInfoProvider`) and the call sites
///     were scattered across `_initListeners`, the post-frame init block,
///     and the per-status-change branch. A controller bundles them.
///   * Cold-start drain (`consumePendingToggle`) and routine toggle live
///     in the same place now, so the "headless tile tap → app boot →
///     execute queued toggle" path is one call away from `init()`.
///
/// The controller takes a callback for "load active profile YAML"
/// (`loadProfileConfig`) so it doesn't reach across the codebase to
/// `SettingsService` + `ProfileService` directly — easier to mock in tests
/// and keeps the tile module's import surface small.
class AndroidTileController {
  AndroidTileController({
    required this.ref,
    required this.loadProfileConfig,
    required this.onTilePreferences,
  });

  final WidgetRef ref;

  /// Returns the YAML config of the currently active profile, or null when
  /// no profile is selected / loading fails. Called by [_performToggle]
  /// before issuing the start command.
  final Future<String?> Function() loadProfileConfig;

  /// Fired when the user long-presses the QS tile (Android's
  /// `QS_TILE_PREFERENCES` intent). Wired to switch the main shell to the
  /// Nodes tab so the user lands on something useful instead of the
  /// dashboard.
  final VoidCallback onTilePreferences;
  bool _pendingToggleDrainStarted = false;

  /// Wire up the tile native channel. Idempotent — safe to call once at
  /// app startup. After this returns:
  ///   * a tap on the QS tile fires [_performToggle];
  ///   * a long-press fires [onTilePreferences];
  ///   * any toggle queued by the native ProxyTileService while the
  ///     engine was still booting (the headless cold-start path) is
  ///     drained shortly after the first rendered frame.
  void init() {
    if (!Platform.isAndroid) return;
    TileService.init();
    TileService.onToggleRequested = _performToggle;
    TileService.onOpenPreferences = onTilePreferences;
    // Keep Android's input thread clean during cold start. Tile state sync
    // and queued-toggle drain both cross a platform channel; run them after
    // the first frame so the Activity can accept input before any OEM tile
    // service binder work begins.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 300), pushState);
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 500),
          _drainPendingToggle,
        ),
      );
    });
  }

  Future<void> _drainPendingToggle() async {
    if (_pendingToggleDrainStarted) return;
    _pendingToggleDrainStarted = true;
    try {
      if (!await TileService.consumePendingToggle()) return;
      debugPrint('[Tile] draining queued toggle from cold-start');
      await _performToggle();
    } catch (e) {
      debugPrint('[Tile] pending toggle drain failed: $e');
    }
  }

  /// Compute and push the full tile state to native — active flag,
  /// transition (starting/stopping), and optional "🇭🇰 香港" subtitle.
  /// Called on any of: core status change, exit-IP resolution, or the
  /// showNodeInTile toggle. Cheap; no-op on non-Android.
  void pushState() {
    if (!Platform.isAndroid) return;
    final status = ref.read(coreStatusProvider);
    final active = status == CoreStatus.running;
    final transition = switch (status) {
      CoreStatus.starting => 'starting',
      CoreStatus.stopping => 'stopping',
      _ => null,
    };
    String? subtitle;
    if (active && transition == null && ref.read(tileShowNodeInfoProvider)) {
      final info = ref.read(exitIpInfoProvider).value;
      if (info != null && info.flagEmoji.isNotEmpty) {
        final loc = info.locationLine;
        subtitle = loc.isNotEmpty ? '${info.flagEmoji} $loc' : info.flagEmoji;
      }
    }
    unawaited(
      TileService.updateState(
        active: active,
        transition: transition,
        subtitle: subtitle,
      ),
    );
  }

  /// Run the user's tile-tap intent: stop if running, start if stopped.
  /// Skips while the core is in a transition state — the user already
  /// has an in-flight start/stop and a second tap shouldn't pile on.
  Future<void> _performToggle() async {
    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.starting || status == CoreStatus.stopping) {
      debugPrint('[Tile] toggle ignored — core is $status');
      return;
    }
    debugPrint('[Tile] toggle — current status: $status');
    final actions = ref.read(coreActionsProvider);
    if (status == CoreStatus.running) {
      await actions.stop();
      return;
    }
    final configYaml = await loadProfileConfig();
    if (configYaml == null) {
      debugPrint('[Tile] toggle: no profile selected, cannot start');
      return;
    }
    await actions.start(configYaml);
  }
}
