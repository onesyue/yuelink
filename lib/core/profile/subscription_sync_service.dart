import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../kernel/core_manager.dart';
import '../../infrastructure/repositories/profile_repository.dart';
import '../../modules/profiles/providers/profiles_providers.dart';
import '../../modules/settings/providers/settings_providers.dart'
    show subSyncIntervalProvider;
import '../../shared/event_log.dart';

/// Silently updates stale subscriptions in the background.
///
/// Checks all profiles at an interval configured by the user
/// (default 6 hours). A profile is "stale" when
/// `DateTime.now() - lastUpdated > updateInterval`. Stale profiles
/// are re-downloaded and saved without user intervention.
///
/// This runs as a foreground timer (not a platform background task)
/// because the VPN process is already alive — no need for workmanager.
/// When the app goes to background, the timer pauses automatically
/// (Dart event loop is deprioritized by the OS).
final subscriptionSyncProvider = Provider<void>((ref) {
  final intervalHours = ref.watch(subSyncIntervalProvider);

  // 0 = disabled
  if (intervalHours <= 0) return;

  final checkInterval = Duration(hours: intervalHours);

  final timer = Timer.periodic(checkInterval, (_) {
    _syncStaleProfiles(ref);
  });

  // Also check once after a short delay on provider creation.
  // Use a delay instead of microtask so the initial load has time to finish.
  final initialTimer = Timer(const Duration(seconds: 10), () {
    _syncStaleProfiles(ref);
  });

  ref.onDispose(() {
    timer.cancel();
    initialTimer.cancel();
  });
});

/// Guard against concurrent syncs — only one sync cycle runs at a time.
bool _syncing = false;

Future<void> _syncStaleProfiles(Ref ref) async {
  if (_syncing) return;
  _syncing = true;
  try {
    final profiles = ref.read(profilesProvider).valueOrNull;
    if (profiles == null || profiles.isEmpty) return;

    final repo = ref.read(profileRepositoryProvider);
    final now = DateTime.now();
    final proxyPort = CoreManager.instance.isRunning
        ? CoreManager.instance.mixedPort
        : null;

    var updated = 0;

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
        debugPrint(
            '[SubscriptionSync] updating stale profile: ${profile.name}');
        await repo.updateProfile(profile, proxyPort: proxyPort);
        EventLog.write('[Sync] updated ${profile.name}');
        updated++;
      } catch (e) {
        debugPrint(
            '[SubscriptionSync] failed to update ${profile.name}: $e');
        EventLog.write('[Sync] failed ${profile.name}: $e');
        // Don't retry immediately — next 30-minute tick will try again.
      }
    }

    // Refresh in-memory profiles list once after all updates, not per profile.
    if (updated > 0) {
      ref.read(profilesProvider.notifier).load();
    }
  } finally {
    _syncing = false;
  }
}
