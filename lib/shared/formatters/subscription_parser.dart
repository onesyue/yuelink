import 'dart:convert' show base64Decode;

/// Parses subscription response headers and content.
///
/// Clash/mihomo subscriptions return useful metadata in HTTP headers:
/// - `subscription-userinfo`: traffic quota and expiry
/// - `content-disposition`: suggested filename
/// - `profile-update-interval`: update frequency in hours
class SubscriptionInfo {
  final int? upload; // bytes used upload
  final int? download; // bytes used download
  final int? total; // total quota bytes
  final DateTime? expire; // expiry date
  final int? updateInterval; // hours
  final String? profileTitle; // subscription name from headers

  const SubscriptionInfo({
    this.upload,
    this.download,
    this.total,
    this.expire,
    this.updateInterval,
    this.profileTitle,
  });

  /// Remaining traffic in bytes, or null if unknown.
  int? get remaining {
    if (total == null) return null;
    return total! - (upload ?? 0) - (download ?? 0);
  }

  /// Usage percentage (0.0 - 1.0), or null if unknown.
  double? get usagePercent {
    if (total == null || total == 0) return null;
    final used = (upload ?? 0) + (download ?? 0);
    return used / total!;
  }

  /// Whether the subscription has expired.
  bool get isExpired {
    if (expire == null) return false;
    return DateTime.now().isAfter(expire!);
  }

  /// Days until expiry, or null if unknown.
  int? get daysRemaining {
    if (expire == null) return null;
    return expire!.difference(DateTime.now()).inDays;
  }

  /// Parse from HTTP response headers.
  ///
  /// Expects the `subscription-userinfo` header format:
  /// `upload=1234; download=5678; total=10000000000; expire=1700000000`
  ///
  /// Also extracts subscription name from:
  /// - `profile-title` header (base64 or plain text, used by some panels)
  /// - `content-disposition` header filename
  factory SubscriptionInfo.fromHeaders(Map<String, String> headers) {
    final userInfo = headers['subscription-userinfo'] ?? '';
    final interval = headers['profile-update-interval'];

    int? upload, download, total;
    DateTime? expire;

    for (final part in userInfo.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length != 2) continue;
      final key = kv[0].trim().toLowerCase();
      final value = int.tryParse(kv[1].trim());
      if (value == null) continue;

      switch (key) {
        case 'upload':
          upload = value;
        case 'download':
          download = value;
        case 'total':
          total = value;
        case 'expire':
          expire = DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
    }

    // Extract subscription name from headers
    final profileTitle = _extractProfileTitle(headers);

    return SubscriptionInfo(
      upload: upload,
      download: download,
      total: total,
      expire: expire,
      updateInterval: interval != null ? int.tryParse(interval) : null,
      profileTitle: profileTitle,
    );
  }

  /// Extract subscription name from HTTP headers.
  ///
  /// Priority: profile-title > content-disposition filename.
  static String? _extractProfileTitle(Map<String, String> headers) {
    // 1. profile-title header (some panels send base64-encoded title)
    final title = headers['profile-title'];
    if (title != null && title.isNotEmpty) {
      // Try base64 decode first
      try {
        final decoded = String.fromCharCodes(
            _base64DecodeStr(title));
        if (decoded.isNotEmpty) return decoded;
      } catch (_) {}
      // Plain text fallback
      return Uri.decodeComponent(title);
    }

    // 2. content-disposition filename
    final cd = headers['content-disposition'];
    if (cd != null && cd.isNotEmpty) {
      // filename*=UTF-8''EncodedName
      final utf8Match = RegExp(r"filename\*=UTF-8''(.+?)(?:;|$)", caseSensitive: false).firstMatch(cd);
      if (utf8Match != null) {
        final decoded = Uri.decodeComponent(utf8Match.group(1)!.trim());
        final name = decoded.replaceAll(RegExp(r'\.(yaml|yml|txt)$'), '');
        if (name.isNotEmpty) return name;
      }
      // filename="Name" or filename=Name
      final fnMatch = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(cd);
      if (fnMatch != null) {
        final name = fnMatch.group(1)!.trim().replaceAll(RegExp(r'\.(yaml|yml|txt)$'), '');
        if (name.isNotEmpty) return name;
      }
    }

    return null;
  }

  static List<int> _base64DecodeStr(String input) {
    // Pad if needed
    var s = input.trim();
    while (s.length % 4 != 0) {
      s += '=';
    }
    return base64Decode(s);
  }

  Map<String, dynamic> toJson() => {
        if (upload != null) 'upload': upload,
        if (download != null) 'download': download,
        if (total != null) 'total': total,
        if (expire != null) 'expire': expire!.millisecondsSinceEpoch ~/ 1000,
        if (updateInterval != null) 'updateInterval': updateInterval,
        if (profileTitle != null) 'profileTitle': profileTitle,
      };

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionInfo(
      upload: json['upload'] as int?,
      download: json['download'] as int?,
      total: json['total'] as int?,
      expire: json['expire'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['expire'] as int) * 1000)
          : null,
      updateInterval: json['updateInterval'] as int?,
      profileTitle: json['profileTitle'] as String?,
    );
  }
}

/// Format bytes to human-readable string (e.g. "1.5 GB").
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes < 1024 * 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
}
