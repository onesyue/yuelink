import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/kernel/core_manager.dart';
import '../domain/models/profile.dart';
import '../infrastructure/repositories/profile_repository.dart';
import '../modules/profiles/providers/profiles_providers.dart';
import '../shared/event_log.dart';

/// Silently updates stale subscriptions in the background.
///
/// Checks all profiles every 30 minutes. A profile is "stale" when
/// `DateTime.now() - lastUpdated > updateInterval`. Stale profiles
/// are re-downloaded and saved without user intervention.
///
/// This runs as a foreground timer (not a platform background task)
/// because the VPN process is already alive — no need for workmanager.
/// When the app goes to background, the timer pauses automatically
/// (Dart event loop is deprioritized by the OS).
final subscriptionSyncProvider = Provider<void>((ref) {
  // Only run when profiles are loaded and the timer makes sense.
  final profiles = ref.watch(profilesProvider);
  final list = profiles.valueOrNull;
  if (list == null || list.isEmpty) return;

  // Check every 30 minutes
  final timer = Timer.periodic(const Duration(minutes: 30), (_) {
    _syncStaleProfiles(ref);
  });

  // Also check once immediately on provider creation
  Future.microtask(() => _syncStaleProfiles(ref));

  ref.onDispose(() => timer.cancel());
});

Future<void> _syncStaleProfiles(Ref ref) async {
  final profiles = ref.read(profilesProvider).valueOrNull;
  if (profiles == null) return;

  final repo = ref.read(profileRepositoryProvider);
  final now = DateTime.now();
  final proxyPort = CoreManager.instance.isRunning
      ? CoreManager.instance.mixedPort
      : null;

  for (final profile in profiles) {
    // Skip local profiles (no URL to update from)
    if (profile.url.isEmpty) continue;

    // Skip if not stale
    if (profile.lastUpdated != null &&
        now.difference(profile.lastUpdated!) < profile.updateInterval) {
      continue;
    }

    // Skip if updateInterval is zero (never auto-update)
    if (profile.updateInterval == Duration.zero) continue;

    try {
      debugPrint('[SubscriptionSync] updating stale profile: ${profile.name}');
      await repo.updateProfile(profile, proxyPort: proxyPort);
      EventLog.write('[Sync] updated ${profile.name}');

      // Update in-memory state
      final list = ref.read(profilesProvider).valueOrNull;
      if (list != null) {
        final idx = list.indexWhere((p) => p.id == profile.id);
        if (idx != -1) {
          final updated = [...list];
          updated[idx] = profile;
          ref.read(profilesProvider.notifier).state =
              AsyncValue.data(updated);
        }
      }
    } catch (e) {
      debugPrint('[SubscriptionSync] failed to update ${profile.name}: $e');
      EventLog.write('[Sync] failed ${profile.name}: $e');
      // Don't retry immediately — next 30-minute tick will try again.
      // This is effectively exponential backoff (30min intervals).
    }
  }
}
