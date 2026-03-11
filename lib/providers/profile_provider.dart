import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../services/core_manager.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';

// ------------------------------------------------------------------
// Current active profile (persisted)
// ------------------------------------------------------------------

final activeProfileIdProvider =
    StateNotifierProvider<ActiveProfileNotifier, String?>(
  (ref) => ActiveProfileNotifier(),
);

class ActiveProfileNotifier extends StateNotifier<String?> {
  ActiveProfileNotifier([super.initial]);

  void select(String? id) {
    state = id;
    SettingsService.setActiveProfileId(id);
  }
}

// ------------------------------------------------------------------
// Profiles list
// ------------------------------------------------------------------

final profilesProvider =
    StateNotifierProvider<ProfilesNotifier, AsyncValue<List<Profile>>>(
  (ref) => ProfilesNotifier(ref),
);

class ProfilesNotifier extends StateNotifier<AsyncValue<List<Profile>>> {
  ProfilesNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  final Ref _ref;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final profiles = await ProfileService.loadProfiles();
      state = AsyncValue.data(profiles);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Profile> add({required String name, required String url}) async {
    final proxyPort = CoreManager.instance.isRunning
        ? CoreManager.instance.mixedPort
        : null;
    final profile = await ProfileService.addProfile(
        name: name, url: url, proxyPort: proxyPort);
    state.whenData((list) {
      state = AsyncValue.data([...list, profile]);
    });
    return profile;
  }

  /// Insert an already-created local profile into the state list.
  void addLocal(Profile profile) {
    state.whenData((list) {
      state = AsyncValue.data([...list, profile]);
    });
  }

  /// Update a profile in-place to avoid loading flash.
  Future<void> update(Profile profile) async {
    final proxyPort = CoreManager.instance.isRunning
        ? CoreManager.instance.mixedPort
        : null;
    await ProfileService.updateProfile(profile, proxyPort: proxyPort);
    state.whenData((list) {
      final idx = list.indexWhere((p) => p.id == profile.id);
      if (idx == -1) return;
      final updated = [...list];
      updated[idx] = profile;
      state = AsyncValue.data(updated);
    });
  }

  Future<void> delete(String id) async {
    await ProfileService.deleteProfile(id);
    // Clear active profile selection if we deleted the active one
    if (_ref.read(activeProfileIdProvider) == id) {
      _ref.read(activeProfileIdProvider.notifier).select(null);
    }
    state.whenData((list) {
      state = AsyncValue.data(list.where((p) => p.id != id).toList());
    });
  }
}
