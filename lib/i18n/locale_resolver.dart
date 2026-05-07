import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

/// Stored language preference values.
///
/// [languageAuto] follows the operating system locale and re-resolves on
/// every `didChangeLocales` callback. The other two pin the UI to a
/// concrete language regardless of OS settings.
class LanguagePreference {
  static const String auto = 'auto';
  static const String zh = 'zh';
  static const String en = 'en';

  /// Recognised values for the persisted setting. Anything else (legacy
  /// rows, future codes we haven't migrated) is treated as [auto] so the
  /// app at least matches the user's OS until they re-pick.
  static const Set<String> validValues = {auto, zh, en};

  static String normalise(String? raw) {
    if (raw == null) return auto;
    return validValues.contains(raw) ? raw : auto;
  }
}

/// Map a system locale string (`zh`, `zh_CN`, `zh-Hant`, `en`, `en_US`,
/// `ja_JP`, …) to the closest supported app language. Anything that's
/// not Chinese falls through to English — the supportedLocales list is
/// `[zh, en]`, so this mirrors the Flutter framework's own resolver.
String resolveLanguageFromSystemLocale(String localeName) {
  final code = localeName.toLowerCase();
  return code.startsWith('zh') ? LanguagePreference.zh : LanguagePreference.en;
}

/// Best-effort read of the OS locale at the moment of the call. Used at
/// bootstrap (before any widgets exist) and from `didChangeLocales`
/// (where the caller could pass the new list, but we re-read the
/// dispatcher to be source-agnostic).
String currentSystemLanguage() {
  // PlatformDispatcher.locale is more reliable than Platform.localeName
  // in tests and during early bootstrap on some Linux distros where
  // LC_ALL / LANG roundtrip through dart:io misses subtags. Fall back
  // to Platform.localeName for the rare embedder that hasn't surfaced
  // a dispatcher locale yet.
  final dispatcherLocale =
      PlatformDispatcher.instance.locale.toLanguageTag();
  if (dispatcherLocale.isNotEmpty) {
    return resolveLanguageFromSystemLocale(dispatcherLocale);
  }
  return resolveLanguageFromSystemLocale(Platform.localeName);
}

/// Resolve a stored preference to the concrete language the app should
/// render right now. `auto` consults [currentSystemLanguage]; pinned
/// values pass through.
String effectiveLanguageForPreference(String preference) {
  switch (preference) {
    case LanguagePreference.zh:
      return LanguagePreference.zh;
    case LanguagePreference.en:
      return LanguagePreference.en;
    case LanguagePreference.auto:
    default:
      return currentSystemLanguage();
  }
}
