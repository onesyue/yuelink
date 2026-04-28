/// Emby media service access info.
///
/// Pure Dart — no Flutter or network dependencies.
class EmbyInfo {
  final String? embyUrl;
  final String? autoLoginUrl;

  EmbyInfo({this.embyUrl, this.autoLoginUrl});

  /// The best URL to open: auto_login_url if present, else emby_url.
  String? get launchUrl => autoLoginUrl?.isNotEmpty == true
      ? autoLoginUrl
      : embyUrl?.isNotEmpty == true
          ? embyUrl
          : null;

  bool get hasAccess => launchUrl != null;

  // ── Parsed components from auto_login_url ────────────────────────────────

  /// e.g. "https://emby.yue.to"
  String? get serverBaseUrl {
    final url = autoLoginUrl ?? embyUrl;
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final port = (uri.hasPort &&
            !((uri.scheme == 'https' && uri.port == 443) ||
                (uri.scheme == 'http' && uri.port == 80)))
        ? ':${uri.port}'
        : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  String? get parsedUserId => _q('userId');
  String? get parsedAccessToken => _q('accessToken');
  String? get parsedServerId => _q('serverId');

  String? _q(String key) {
    if (autoLoginUrl == null) return null;
    return Uri.tryParse(autoLoginUrl!)?.queryParameters[key];
  }

  /// True when we have enough info to use the native media browser.
  bool get hasNativeAccess =>
      serverBaseUrl != null &&
      parsedUserId != null &&
      parsedAccessToken != null;

  factory EmbyInfo.fromJson(Map<String, dynamic> json) {
    return EmbyInfo(
      embyUrl: json['emby_url'] as String?,
      autoLoginUrl: json['auto_login_url'] as String?,
    );
  }

  /// Serialise back to the same shape XBoard's `/emby` endpoint returns,
  /// so the cache round-trips through `fromJson` without losing fidelity.
  /// `auto_login_url` carries access-token + user-id query params, which
  /// is why callers persist this through SecureStorage rather than
  /// SettingsService — same threat-model as the Bearer token.
  Map<String, dynamic> toJson() => {
        if (embyUrl != null) 'emby_url': embyUrl,
        if (autoLoginUrl != null) 'auto_login_url': autoLoginUrl,
      };
}
