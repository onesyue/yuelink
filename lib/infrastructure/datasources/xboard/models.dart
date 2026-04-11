import 'errors.dart';

/// XBoard login response. Carries the auth token used for subsequent calls.
class LoginResponse {
  LoginResponse({required this.token, this.authData});

  final String token;
  final String? authData;

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    // XBoard login returns two token fields:
    //   - auth_data: Sanctum token, already prefixed with "Bearer " — use this
    //                for Authorization header on all /api/v1/user/* endpoints.
    //   - token:     raw database token used only for subscription download URLs
    //                (Client middleware), NOT for API auth.
    // Both reference clients (ClashMetaForAndroid, clash-verge-rev) use auth_data.
    final authData = json['auth_data'] as String? ?? '';
    final rawToken = json['token'] as String? ?? '';
    final token = authData.isNotEmpty ? authData : rawToken;
    if (token.isEmpty) {
      throw XBoardApiException(0, 'No token in login response');
    }
    return LoginResponse(
      token: token,
      authData: authData.isNotEmpty ? authData : null,
    );
  }
}

/// Combined user profile from `/api/v1/user/getSubscribe`.
///
/// All traffic fields (`transferEnable`, `uploadUsed` = `u`, `downloadUsed` = `d`)
/// are in BYTES — pass directly to `formatBytes()`, do NOT multiply.
class UserProfile {
  UserProfile({
    this.planId,
    this.planName,
    this.transferEnable,
    this.uploadUsed,
    this.downloadUsed,
    this.expiredAt,
    this.email,
    this.uuid,
    this.onlineCount,
    this.deviceLimit,
  });

  final int? planId;
  final String? planName;

  /// Total traffic quota in bytes — XBoard users.transfer_enable.
  final int? transferEnable;

  /// Upload bytes used — XBoard field: u.
  final int? uploadUsed;

  /// Download bytes used — XBoard field: d.
  final int? downloadUsed;

  /// Unix timestamp (seconds).
  final int? expiredAt;

  final String? email;
  final String? uuid;

  /// Number of devices currently online — XBoard field: online_count.
  final int? onlineCount;

  /// Maximum allowed devices — from nested plan.device_limit.
  final int? deviceLimit;

  /// Remaining traffic in bytes.
  int? get remaining {
    if (transferEnable == null) return null;
    return transferEnable! - (uploadUsed ?? 0) - (downloadUsed ?? 0);
  }

  /// Usage percentage (0.0 - 1.0).
  double? get usagePercent {
    if (transferEnable == null || transferEnable == 0) return null;
    final used = (uploadUsed ?? 0) + (downloadUsed ?? 0);
    return used / transferEnable!;
  }

  bool get isExpired {
    if (expiredAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch > expiredAt! * 1000;
  }

  int? get daysRemaining {
    if (expiredAt == null) return null;
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiredAt! * 1000);
    return expiry.difference(DateTime.now()).inDays;
  }

  DateTime? get expiryDate {
    if (expiredAt == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(expiredAt! * 1000);
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    // device_limit may be at top level or nested under plan object
    int? deviceLimit = _toInt(json['device_limit']);
    if (deviceLimit == null && json['plan'] is Map) {
      deviceLimit = _toInt((json['plan'] as Map)['device_limit']);
    }
    return UserProfile(
      planId: _toInt(json['plan_id']),
      planName: _extractPlanName(json),
      transferEnable: _toInt(json['transfer_enable']),
      uploadUsed: _toInt(json['u']),
      downloadUsed: _toInt(json['d']),
      expiredAt: _toInt(json['expired_at']),
      email: json['email'] as String?,
      uuid: json['uuid'] as String?,
      onlineCount: _toInt(json['online_count']),
      deviceLimit: deviceLimit,
    );
  }

  /// XBoard returns numeric fields as int, double, or bool (tinyint(1) on
  /// the Laravel side). All store/profile models go through this helper to
  /// avoid the `type 'bool' is not a subtype of int?` runtime crash.
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return null;
  }

  static String? _extractPlanName(Map<String, dynamic> json) {
    if (json['plan'] is Map) {
      return (json['plan'] as Map)['name'] as String?;
    }
    return json['plan_name'] as String?;
  }

  Map<String, dynamic> toJson() => {
        if (planId != null) 'plan_id': planId,
        if (planName != null) 'plan_name': planName,
        if (transferEnable != null) 'transfer_enable': transferEnable,
        if (uploadUsed != null) 'u': uploadUsed,
        if (downloadUsed != null) 'd': downloadUsed,
        if (expiredAt != null) 'expired_at': expiredAt,
        if (email != null) 'email': email,
        if (uuid != null) 'uuid': uuid,
        if (onlineCount != null) 'online_count': onlineCount,
        if (deviceLimit != null) 'device_limit': deviceLimit,
      };
}

/// Raw subscription config download result (clash YAML + headers).
class SubscribeResult {
  SubscribeResult({required this.content, required this.headers});

  final String content;
  final Map<String, String> headers;
}

/// Combined response from `/api/v1/user/getSubscribe`.
/// Includes the full user profile (plan, traffic, expiry) AND the subscribe URL.
class SubscribeData {
  SubscribeData({required this.profile, required this.subscribeUrl});

  final UserProfile profile;
  final String subscribeUrl;
}
