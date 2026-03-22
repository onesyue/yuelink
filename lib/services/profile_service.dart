import '../domain/models/profile.dart';
import '../infrastructure/repositories/profile_repository.dart';

/// Static proxy shim for backward compatibility.
///
/// All logic has moved to [ProfileRepository]. This class delegates every
/// call to a static repository instance so that existing callers
/// (main.dart, AuthNotifier, NodesPage, etc.) continue to work without
/// changing their `ProfileService.xxx()` call sites.
///
/// New code should use `ref.read(profileRepositoryProvider)` instead.
class ProfileService {
  ProfileService._();

  static final _repo = ProfileRepository();

  static Future<List<Profile>> loadProfiles() => _repo.loadProfiles();

  static Future<void> saveProfiles(List<Profile> profiles) =>
      _repo.saveProfiles(profiles);

  static Future<Profile> addProfile({
    required String name,
    required String url,
    int? proxyPort,
  }) =>
      _repo.addProfile(name: name, url: url, proxyPort: proxyPort);

  static Future<Profile> updateProfile(Profile profile, {int? proxyPort}) =>
      _repo.updateProfile(profile, proxyPort: proxyPort);

  static Future<Profile> addLocalProfile({
    required String name,
    required String configContent,
  }) =>
      _repo.addLocalProfile(name: name, configContent: configContent);

  static Future<void> deleteProfile(String id) => _repo.deleteProfile(id);

  static Future<String?> loadConfig(String id) => _repo.loadConfig(id);

  static Future<String?> fetchSubscriptionName(String url) =>
      _repo.fetchSubscriptionName(url);
}
