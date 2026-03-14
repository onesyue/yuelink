import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../constants.dart';

/// REST client for XBoard panel API.
///
/// Handles authentication, user info, and subscription retrieval.
/// Uses the same HTTP patterns as [MihomoApi] for consistency.
class XBoardApi {
  XBoardApi({required this.baseUrl});

  final String baseUrl;

  static const _kTimeout = Duration(seconds: 15);

  // ------------------------------------------------------------------
  // Auth
  // ------------------------------------------------------------------

  /// Login with email and password.
  /// Returns auth data containing the token.
  Future<LoginResponse> login(String email, String password) async {
    final resp = await _post('/api/v1/passport/auth/login', body: {
      'email': email,
      'password': password,
    });
    return LoginResponse.fromJson(resp);
  }

  // ------------------------------------------------------------------
  // User
  // ------------------------------------------------------------------

  /// Get current user info (plan, traffic, expiry, etc.).
  Future<UserProfile> getUserInfo(String token) async {
    final resp = await _get('/api/v1/user/info', token: token);
    return UserProfile.fromJson(resp);
  }

  /// Get the user's subscription URL for fetching proxy configs.
  /// XBoard returns this as part of user/getSubscribe.
  Future<String> getSubscribeUrl(String token) async {
    final resp = await _get('/api/v1/user/getSubscribe', token: token);
    final url = resp['subscribe_url'] as String?;
    if (url == null || url.isEmpty) {
      throw XBoardApiException(0, 'No subscribe URL in response');
    }
    return url;
  }

  // ------------------------------------------------------------------
  // Subscription
  // ------------------------------------------------------------------

  /// Download the actual subscription config (Clash YAML) from a subscribe URL.
  /// This is a direct HTTP GET to the subscription URL, not an XBoard API call.
  ///
  /// Returns both the YAML content and parsed subscription-userinfo headers.
  Future<SubscribeResult> fetchSubscribeConfig(String subscribeUrl) async {
    final response = await http.get(
      Uri.parse(subscribeUrl),
      headers: {
        'User-Agent': AppConstants.userAgent,
      },
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw XBoardApiException(
        response.statusCode,
        'Failed to fetch subscription config',
      );
    }

    return SubscribeResult(
      content: response.body,
      headers: response.headers,
    );
  }

  // ------------------------------------------------------------------
  // Announcements
  // ------------------------------------------------------------------

  /// Get announcements list.
  Future<List<Announcement>> getAnnouncements(String token) async {
    final resp = await _get('/api/v1/user/notice/fetch', token: token);
    final list = resp['data'] as List? ?? [];
    return list
        .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ------------------------------------------------------------------
  // HTTP helpers
  // ------------------------------------------------------------------

  Map<String, String> _headers({String? token}) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': token,
      };

  Future<Map<String, dynamic>> _get(String path, {String? token}) async {
    final resp = await http
        .get(Uri.parse('$baseUrl$path'), headers: _headers(token: token))
        .timeout(_kTimeout);

    if (resp.statusCode != 200) {
      throw XBoardApiException(resp.statusCode, resp.body);
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = json['data'];
    if (data is Map<String, dynamic>) return data;
    // Some endpoints wrap data differently
    return json;
  }

  Future<Map<String, dynamic>> _post(String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _headers(token: token),
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(_kTimeout);

    if (resp.statusCode != 200) {
      throw XBoardApiException(resp.statusCode, resp.body);
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = json['data'];
    if (data is Map<String, dynamic>) return data;
    return json;
  }
}

// ------------------------------------------------------------------
// Models
// ------------------------------------------------------------------

class LoginResponse {
  final String token;
  final String? authData;

  LoginResponse({required this.token, this.authData});

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    // XBoard returns token directly or nested under auth_data
    final token = json['token'] as String? ??
        json['auth_data'] as String? ??
        '';
    if (token.isEmpty) {
      throw XBoardApiException(0, 'No token in login response');
    }
    return LoginResponse(
      token: token,
      authData: json['auth_data'] as String?,
    );
  }
}

class UserProfile {
  final int? planId;
  final String? planName;
  final int? transferEnable; // total traffic in bytes
  final int? uploadUsed; // uploaded bytes (d field in XBoard)
  final int? downloadUsed; // downloaded bytes (u field in XBoard)
  final int? expiredAt; // unix timestamp
  final String? email;
  final String? uuid;

  UserProfile({
    this.planId,
    this.planName,
    this.transferEnable,
    this.uploadUsed,
    this.downloadUsed,
    this.expiredAt,
    this.email,
    this.uuid,
  });

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

  /// Whether the plan has expired.
  bool get isExpired {
    if (expiredAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch > expiredAt! * 1000;
  }

  /// Days until expiry.
  int? get daysRemaining {
    if (expiredAt == null) return null;
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiredAt! * 1000);
    return expiry.difference(DateTime.now()).inDays;
  }

  /// Expiry date.
  DateTime? get expiryDate {
    if (expiredAt == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(expiredAt! * 1000);
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      planId: json['plan_id'] as int?,
      planName: _extractPlanName(json),
      transferEnable: json['transfer_enable'] as int?,
      uploadUsed: json['u'] as int?,
      downloadUsed: json['d'] as int?,
      expiredAt: json['expired_at'] as int?,
      email: json['email'] as String?,
      uuid: json['uuid'] as String?,
    );
  }

  static String? _extractPlanName(Map<String, dynamic> json) {
    // Plan name may be nested under plan object or at top level
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
      };
}

class SubscribeResult {
  final String content;
  final Map<String, String> headers;

  SubscribeResult({required this.content, required this.headers});
}

class Announcement {
  final int? id;
  final String title;
  final String content;
  final int? createdAt;

  Announcement({
    this.id,
    required this.title,
    required this.content,
    this.createdAt,
  });

  DateTime? get createdDate {
    if (createdAt == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(createdAt! * 1000);
  }

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as int?,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] as int?,
    );
  }
}

// ------------------------------------------------------------------
// Exception
// ------------------------------------------------------------------

class XBoardApiException implements Exception {
  final int statusCode;
  final String body;

  XBoardApiException(this.statusCode, this.body);

  /// Try to extract a user-friendly error message from XBoard JSON response.
  String get message {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['message'] as String? ?? body;
    } catch (_) {
      return body;
    }
  }

  @override
  String toString() => 'XBoardApiException($statusCode): $message';
}
