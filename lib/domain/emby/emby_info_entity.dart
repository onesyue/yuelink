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

  factory EmbyInfo.fromJson(Map<String, dynamic> json) {
    return EmbyInfo(
      embyUrl: json['emby_url'] as String?,
      autoLoginUrl: json['auto_login_url'] as String?,
    );
  }
}
