/// Compile-time environment configuration.
///
/// Controls features that differ between standalone distribution
/// (sideload, TrollStore, direct download) and app store distribution
/// (App Store, Google Play — where self-update is prohibited).
///
/// Usage:
///   - Default (standalone): `flutter run` or `flutter build apk`
///   - Store mode: `flutter build ios --dart-define=STANDALONE=false`
///
/// Apple rejects apps that contain self-update mechanisms. This flag
/// gates the update checker, "check for updates" UI, and any download-
/// and-install logic so the same codebase can target both channels.
class EnvConfig {
  EnvConfig._();

  /// True for independent distribution (GitHub Releases, TrollStore, sideload).
  /// False for App Store / Google Play submissions.
  ///
  /// Override at compile time:
  ///   `flutter build ios --dart-define=STANDALONE=false`
  static const isStandalone = bool.fromEnvironment(
    'STANDALONE',
    defaultValue: true,
  );

  /// Human-readable distribution channel name (for analytics / logs).
  static String get channel => isStandalone ? 'standalone' : 'store';
}
