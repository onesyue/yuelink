import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/profile.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../infrastructure/repositories/profile_repository.dart';
import '../../../core/storage/settings_service.dart';
import '../../../shared/telemetry.dart';

// ------------------------------------------------------------------
// Current active profile (persisted)
// ------------------------------------------------------------------

/// Pre-loaded initial profile ID, overridden in main.dart ProviderScope.
final preloadedProfileIdProvider = Provider<String?>((ref) => null);

final activeProfileIdProvider =
    NotifierProvider<ActiveProfileNotifier, String?>(
  ActiveProfileNotifier.new,
);

class ActiveProfileNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(preloadedProfileIdProvider);

  void select(String? id) {
    if (state == id) return;
    state = id;
    SettingsService.setActiveProfileId(id);
    if (id != null) Telemetry.event(TelemetryEvents.profileSwitch);
  }
}

// ------------------------------------------------------------------
// Profiles list
// ------------------------------------------------------------------

final profilesProvider =
    NotifierProvider<ProfilesNotifier, AsyncValue<List<Profile>>>(
  ProfilesNotifier.new,
);

class ProfilesNotifier extends Notifier<AsyncValue<List<Profile>>> {
  @override
  AsyncValue<List<Profile>> build() {
    load();
    return const AsyncValue.loading();
  }

  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final profiles = await _repo.loadProfiles();
      state = AsyncValue.data(profiles);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Profile> add({required String name, required String url}) async {
    final proxyPort = CoreManager.instance.isRunning
        ? CoreManager.instance.mixedPort
        : null;
    final profile =
        await _repo.addProfile(name: name, url: url, proxyPort: proxyPort);
    final current = state.valueOrNull;
    state = AsyncValue.data([...?current, profile]);
    return profile;
  }

  /// Insert an already-created local profile into the state list.
  void addLocal(Profile profile) {
    final current = state.valueOrNull;
    state = AsyncValue.data([...?current, profile]);
  }

  /// Update a profile in-place to avoid loading flash.
  Future<void> update(Profile profile) async {
    final proxyPort = CoreManager.instance.isRunning
        ? CoreManager.instance.mixedPort
        : null;
    await _repo.updateProfile(profile, proxyPort: proxyPort);
    final list = state.valueOrNull;
    if (list != null) {
      final idx = list.indexWhere((p) => p.id == profile.id);
      if (idx != -1) {
        final updated = [...list];
        updated[idx] = profile;
        state = AsyncValue.data(updated);
      }
    }
  }

  Future<void> delete(String id) async {
    await _repo.deleteProfile(id);
    // Clear active profile selection if we deleted the active one
    if (ref.read(activeProfileIdProvider) == id) {
      ref.read(activeProfileIdProvider.notifier).select(null);
    }
    final list = state.valueOrNull;
    if (list != null) {
      state = AsyncValue.data(list.where((p) => p.id != id).toList());
    }
  }
}
