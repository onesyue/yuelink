import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Subscription auto-sync interval, in hours.
///
/// 0 = disabled. Default is 6 hours. Consumed by
/// `core/profile/subscription_sync_service.dart` to schedule the
/// background staleness check.
///
/// Lives in `core/providers/` alongside other operational settings
/// (`routingModeProvider`, `connectionModeProvider`, `logLevelProvider`,
/// etc. defined in `core_provider.dart`). It is intentionally NOT in
/// `modules/settings/providers/` because that would force `core/` to
/// import from `modules/` — the previous arrangement of this provider.
///
/// Settings-side consumers (`GeneralSettingsPage`, the `main.dart`
/// bootstrap override) reach it through a re-export in
/// `modules/settings/providers/settings_providers.dart`, so their import
/// paths are unchanged.
final subSyncIntervalProvider = NotifierProvider<SubSyncIntervalNotifier, int>(
  SubSyncIntervalNotifier.new,
);

class SubSyncIntervalNotifier extends Notifier<int> {
  SubSyncIntervalNotifier([this._initial = 6]);
  final int _initial;

  @override
  int build() => _initial;

  void set(int value) => state = value;
}

/// One-way notification bump that `subscription_sync_service` increments
/// after it finishes a batch update of stale profiles. The
/// `ProfilesNotifier` in `modules/profiles/providers/profiles_providers.dart`
/// listens for changes and re-runs `load()`, so the UI's `lastUpdated`
/// badges refresh without `core/` having to import the profiles module.
///
/// Direction: `modules → core` (the notifier subscribes to a core-side
/// counter). Core never references `profilesProvider` directly anymore.
/// Bumping this counter is a pure side-effect signal — do NOT read the
/// counter value; only listen for transitions.
final profileSyncGenerationProvider =
    NotifierProvider<ProfileSyncGenerationNotifier, int>(
      ProfileSyncGenerationNotifier.new,
    );

class ProfileSyncGenerationNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Increments the generation counter through an explicit notifier method.
  void bump() => state++;
}
