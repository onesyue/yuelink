import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/profile.dart';
import '../../services/profile_service.dart';

/// Wraps ProfileService with an instance-based API registered as a Riverpod
/// provider. Providers that previously called ProfileService.staticMethod()
/// now call ref.read(profileRepositoryProvider).method() instead.
class ProfileRepository {
  const ProfileRepository();

  Future<List<Profile>> loadProfiles() => ProfileService.loadProfiles();

  Future<void> saveProfiles(List<Profile> profiles) =>
      ProfileService.saveProfiles(profiles);

  Future<Profile> addProfile({
    required String name,
    required String url,
    int? proxyPort,
  }) =>
      ProfileService.addProfile(name: name, url: url, proxyPort: proxyPort);

  Future<Profile> updateProfile(Profile profile, {int? proxyPort}) =>
      ProfileService.updateProfile(profile, proxyPort: proxyPort);

  Future<void> deleteProfile(String id) => ProfileService.deleteProfile(id);

  Future<String?> loadConfig(String id) => ProfileService.loadConfig(id);

  Future<Profile> importLocalFile({
    required String name,
    required String configContent,
  }) =>
      ProfileService.addLocalProfile(name: name, configContent: configContent);
}

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => const ProfileRepository());
