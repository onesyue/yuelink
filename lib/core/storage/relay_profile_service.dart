import '../../domain/models/relay_profile.dart';
import 'settings_service.dart';

/// Persistence for the commercial dialer-proxy relay profile.
///
/// Phase 1A surface: a single profile stored under `commercialRelay` in
/// SettingsService. Default is absent → [load] returns null → every call
/// site is a no-op. No UI writes this today; tests and debug harnesses
/// invoke [save] directly.
class RelayProfileService {
  RelayProfileService._();

  static const _key = 'commercialRelay';

  /// Returns the persisted profile, or null when nothing is stored or the
  /// stored payload is not a valid JSON map. Never throws.
  static Future<RelayProfile?> load() async {
    try {
      final settings = await SettingsService.load();
      final raw = settings[_key];
      if (raw is! Map) return null;
      return RelayProfile.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(RelayProfile profile) async {
    await SettingsService.set(_key, profile.toJson());
  }

  static Future<void> clear() async {
    await SettingsService.set(_key, null);
  }
}
