import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../core/providers/core_provider.dart';
import '../../../infrastructure/repositories/profile_repository.dart';
import '../../profiles/providers/profiles_providers.dart';
import '../../yue_auth/providers/yue_auth_providers.dart';
import 'nodes_providers.dart';

/// Orchestration for the "sync subscription + reconnect" action exposed by
/// the nodes page sync icon.
///
/// Extracted from `nodes_page.dart` so the 50-line pipeline is driven by a
/// notifier instead of a StatefulWidget method — testable in isolation and
/// reusable if another entry point needs to kick the same sequence.
///
/// Intentionally UI-agnostic: no `BuildContext`, no `S.of(context)`, no
/// `AppNotifier`. Callers translate the returned [SyncAndReconnectResult]
/// into their own feedback (snackbar, toast, telemetry).
///
/// Provider access is via `ref.read(...)` throughout — this notifier does
/// NOT watch `coreStatusProvider` / `coreActionsProvider` /
/// `activeProfileIdProvider`, so moving the pipeline out of the widget
/// tree doesn't create a persistent provider consumer that could re-enter
/// during a mid-sync core restart.

enum SyncAndReconnectOutcome { success, startFailed, error }

class SyncAndReconnectResult {
  final SyncAndReconnectOutcome outcome;

  /// Set only when [outcome] == [SyncAndReconnectOutcome.error].
  final Object? error;

  const SyncAndReconnectResult._(this.outcome, [this.error]);

  static const success =
      SyncAndReconnectResult._(SyncAndReconnectOutcome.success);
  static const startFailed =
      SyncAndReconnectResult._(SyncAndReconnectOutcome.startFailed);

  factory SyncAndReconnectResult.failure(Object e) =>
      SyncAndReconnectResult._(SyncAndReconnectOutcome.error, e);

  bool get isSuccess => outcome == SyncAndReconnectOutcome.success;
}

class SyncAndReconnectNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// True while a sync-and-reconnect is in flight. Callers should watch
  /// this to disable their trigger button.
  bool get isRunning => state;

  /// Execute the pipeline. Returns `null` if a run was already in flight
  /// (caller should treat as "ignored"); otherwise returns a typed result.
  Future<SyncAndReconnectResult?> run() async {
    if (state) return null;
    state = true;

    try {
      // 1. Sync subscription: re-download config from remote.
      final authState = ref.read(authProvider);
      if (authState.isLoggedIn) {
        // Logged-in user: sync via XBoard.
        await ref.read(authProvider.notifier).syncSubscription();
      } else {
        // Guest / third-party airport: update active profile directly.
        final activeId = ref.read(activeProfileIdProvider);
        if (activeId != null) {
          final profiles =
              await ref.read(profileRepositoryProvider).loadProfiles();
          final profile =
              profiles.where((p) => p.id == activeId).firstOrNull;
          if (profile != null && profile.url.isNotEmpty) {
            final proxyPort = CoreManager.instance.isRunning
                ? CoreManager.instance.mixedPort
                : null;
            await ref
                .read(profileRepositoryProvider)
                .updateProfile(profile, proxyPort: proxyPort);
            ref.read(profilesProvider.notifier).load();
          }
        }
      }

      // 2. If core is running, stop → reload config → restart.
      final status = ref.read(coreStatusProvider);
      if (status == CoreStatus.running) {
        final activeId = ref.read(activeProfileIdProvider);
        if (activeId != null) {
          final configYaml =
              await ref.read(profileRepositoryProvider).loadConfig(activeId);
          if (configYaml != null) {
            await ref.read(coreActionsProvider).stop();
            final ok =
                await ref.read(coreActionsProvider).start(configYaml);
            if (!ok) {
              return SyncAndReconnectResult.startFailed;
            }
          }
        }
      }

      // 3. Refresh proxy groups.
      ref.read(proxyGroupsProvider.notifier).refresh();

      return SyncAndReconnectResult.success;
    } catch (e) {
      debugPrint('[SyncAndReconnect] $e');
      return SyncAndReconnectResult.failure(e);
    } finally {
      state = false;
    }
  }
}

final syncAndReconnectProvider =
    NotifierProvider<SyncAndReconnectNotifier, bool>(
  SyncAndReconnectNotifier.new,
);
