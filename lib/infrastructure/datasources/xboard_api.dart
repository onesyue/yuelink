import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../constants.dart';
import '../../modules/store/models/coupon_result.dart';
import '../../modules/store/models/payment_method.dart';
import '../../modules/store/models/store_order.dart';
import '../../modules/store/models/store_plan.dart';

/// REST client for XBoard panel API.
///
/// Handles authentication, user info, and subscription retrieval.
/// Uses IOClient (dart:io HttpClient) for proper TLS SNI on all platforms.
class XBoardApi {
  XBoardApi({required this.baseUrl});

  final String baseUrl;

  static const _kTimeout = Duration(seconds: 20);

  /// Build an [http.Client] backed by [dart:io]'s [HttpClient].
  ///
  /// This ensures:
  ///   - SNI (Server Name Indication) is always sent — required by CloudFront.
  ///   - Connection / idle timeouts are explicit.
  ///   - Works correctly on all Flutter platforms (Android, iOS, macOS, Windows).
  static http.Client _buildClient() {
    final inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 30);
    return IOClient(inner);
  }

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

  /// Get full subscribe data in a single request.
  ///
  /// Calls /api/v1/user/getSubscribe which returns:
  ///   - plan.name (nested plan object with full plan info)
  ///   - u / d (upload / download bytes used)
  ///   - transfer_enable (total quota)
  ///   - expired_at, email, uuid
  ///   - subscribe_url
  ///
  /// Use this instead of getUserInfo — /api/v1/user/info does NOT return
  /// u/d traffic fields or the nested plan object with plan name.
  Future<SubscribeData> getSubscribeData(String token) async {
    // Use _getRawData so _assertSuccess is called — catches status:"fail" responses.
    final raw = await _getRawData('/api/v1/user/getSubscribe', token: token);
    final resp = raw as Map<String, dynamic>;
    final url = resp['subscribe_url'] as String?;
    if (url == null || url.isEmpty) {
      throw XBoardApiException(0, 'No subscribe URL in response');
    }
    return SubscribeData(
      profile: UserProfile.fromJson(resp),
      subscribeUrl: url,
    );
  }

  // ------------------------------------------------------------------
  // Password
  // ------------------------------------------------------------------

  /// Change the user's password.
  /// POST /api/v1/user/changePassword
  Future<void> changePassword({
    required String token,
    required String oldPassword,
    required String newPassword,
  }) async {
    await _postRawData(
      '/api/v1/user/changePassword',
      token: token,
      body: {
        'old_password': oldPassword,
        'new_password': newPassword,
      },
    );
  }

  // ------------------------------------------------------------------
  // Subscription
  // ------------------------------------------------------------------

  /// Download the actual subscription config (Clash YAML) from a subscribe URL.
  /// This is a direct HTTP GET to the subscription URL, not an XBoard API call.
  ///
  /// Returns both the YAML content and parsed subscription-userinfo headers.
  Future<SubscribeResult> fetchSubscribeConfig(String subscribeUrl) async {
    final client = _buildClient();
    try {
      final response = await client
          .get(
            Uri.parse(subscribeUrl),
            headers: {'User-Agent': AppConstants.userAgent},
          )
          .timeout(const Duration(seconds: 30));

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
    } finally {
      client.close();
    }
  }

  // ------------------------------------------------------------------
  // Emby
  // ------------------------------------------------------------------

  /// Get Emby service info for the current user.
  /// Returns null if the user has no Emby access.
  Future<EmbyInfo?> getEmby(String token) async {
    try {
      final resp = await _get('/api/client/emby', token: token);
      return EmbyInfo.fromJson(resp);
    } on XBoardApiException catch (e) {
      // 404 / empty data means no Emby for this user
      if (e.statusCode == 404 || e.statusCode == 0) return null;
      rethrow;
    }
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
  // Store — Plans
  // ------------------------------------------------------------------

  /// Fetch all available subscription plans.
  /// GET /api/v1/user/plan/fetch
  Future<List<StorePlan>> getPlans(String token) async {
    final raw = await _getRawData('/api/v1/user/plan/fetch', token: token);
    final list = raw as List? ?? [];
    return list
        .map((e) => StorePlan.fromJson(e as Map<String, dynamic>))
        .where((p) => p.show && p.sell)
        .toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
  }

  // ------------------------------------------------------------------
  // Store — Orders
  // ------------------------------------------------------------------

  /// Create a new order.
  /// POST /api/v1/user/order/save
  /// Returns the trade_no string.
  Future<String> createOrder({
    required String token,
    required int planId,
    required String period,
    String? couponCode,
  }) async {
    final raw = await _postRawData(
      '/api/v1/user/order/save',
      token: token,
      body: {
        'plan_id': planId,
        'period': period,
        if (couponCode != null && couponCode.isNotEmpty)
          'coupon_code': couponCode,
      },
    );
    if (raw is String) return raw;
    throw XBoardApiException(0, 'Unexpected order/save response: $raw');
  }

  /// Get order detail by trade_no.
  /// GET /api/v1/user/order/detail?trade_no=xxx
  Future<StoreOrder> getOrderDetail({
    required String token,
    required String tradeNo,
  }) async {
    final raw = await _getRawData(
      '/api/v1/user/order/detail',
      token: token,
      queryParams: {'trade_no': tradeNo},
    );
    return StoreOrder.fromJson(raw as Map<String, dynamic>);
  }

  /// Checkout / pay for an order.
  /// POST /api/v1/user/order/checkout
  /// Returns a [CheckoutResult] with payment URL or QR code.
  Future<CheckoutResult> checkoutOrder({
    required String token,
    required String tradeNo,
    int? method,
  }) async {
    final raw = await _postRawData(
      '/api/v1/user/order/checkout',
      token: token,
      body: {
        'trade_no': tradeNo,
        if (method != null) 'method': method,
      },
    );
    if (raw is Map<String, dynamic>) {
      return CheckoutResult.fromJson(raw);
    }
    // Some XBoard versions return the URL string directly
    if (raw is String) {
      return CheckoutResult(type: 1, data: raw);
    }
    throw XBoardApiException(0, 'Unexpected checkout response: $raw');
  }

  /// Get available payment methods.
  /// GET /api/v1/user/order/getPaymentMethod
  Future<List<PaymentMethod>> getPaymentMethods(String token) async {
    try {
      final raw = await _getRawData(
          '/api/v1/user/order/getPaymentMethod', token: token);
      final list = raw as List? ?? [];
      return list
          .map((e) => PaymentMethod.fromJson(e as Map<String, dynamic>))
          .toList();
    } on XBoardApiException catch (e) {
      // Endpoint may not exist on older XBoard — return empty list and let
      // checkout proceed without specifying a method (server picks default).
      if (e.statusCode == 404 || e.statusCode == 405) return [];
      rethrow;
    }
  }

  /// Validate a coupon code for a specific plan.
  /// POST /api/v1/user/coupon/check
  /// Throws [XBoardApiException] with user-friendly message on invalid coupon.
  Future<CouponResult> checkCoupon({
    required String token,
    required String code,
    required int planId,
  }) async {
    final raw = await _postRawData(
      '/api/v1/user/coupon/check',
      token: token,
      body: {'code': code, 'plan_id': planId},
    );
    if (raw is Map<String, dynamic>) return CouponResult.fromJson(raw);
    throw XBoardApiException(0, 'Unexpected coupon/check response: $raw');
  }

  /// Fetch order list with pagination.
  /// GET /api/v1/user/order/fetch?page=N
  ///
  /// XBoard may return either:
  ///   A) a plain List directly in data
  ///   B) a Laravel paginated object: { data: [...], total, current_page, last_page }
  Future<OrderListResult> fetchOrders({
    required String token,
    int page = 1,
  }) async {
    final raw = await _getRawData(
      '/api/v1/user/order/fetch',
      token: token,
      queryParams: {'page': '$page'},
    );

    if (raw is List) {
      // Older XBoard: plain array, no pagination info
      final orders = raw
          .map((e) => StoreOrder.fromJson(e as Map<String, dynamic>))
          .toList();
      return OrderListResult(orders: orders, hasMore: false);
    }

    if (raw is Map<String, dynamic>) {
      // Newer XBoard: Laravel paginator
      final dataList = raw['data'] as List? ?? [];
      final orders = dataList
          .map((e) => StoreOrder.fromJson(e as Map<String, dynamic>))
          .toList();
      final currentPage = raw['current_page'] as int? ?? page;
      final lastPage = raw['last_page'] as int? ?? 1;
      return OrderListResult(
        orders: orders,
        hasMore: currentPage < lastPage,
      );
    }

    return OrderListResult(orders: [], hasMore: false);
  }

  /// Cancel a pending order.
  /// POST /api/v1/user/order/cancel
  /// Throws [XBoardApiException] on server-side rejection (e.g. order already paid).
  Future<void> cancelOrder({
    required String token,
    required String tradeNo,
  }) async {
    await _postRawData(
      '/api/v1/user/order/cancel',
      token: token,
      body: {'trade_no': tradeNo},
    );
  }

  // ------------------------------------------------------------------
  // HTTP helpers
  // ------------------------------------------------------------------

  /// Maximum retry attempts for transient network errors.
  static const _maxRetries = 3;

  /// Backoff delays between retries: 500ms, 1s, 2s.
  static const _retryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  /// Whether an error is transient and safe to retry.
  static bool _isTransient(Object e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is HandshakeException) return true;
    if (e is HttpException) return true;
    // Server errors (5xx) — retry
    if (e is XBoardApiException && e.statusCode >= 500) return true;
    return false;
  }

  /// Execute [fn] with automatic retry on transient errors.
  /// Non-retryable errors (auth, business logic) propagate immediately.
  Future<T> _withRetry<T>(Future<T> Function() fn) async {
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await fn();
      } catch (e) {
        final isLast = attempt == _maxRetries - 1;
        if (isLast || !_isTransient(e)) rethrow;
        debugPrint('[XBoardApi] Retry ${attempt + 1}/$_maxRetries after: $e');
        await Future.delayed(_retryDelays[attempt]);
      }
    }
    throw StateError('unreachable'); // loop always returns or rethrows
  }

  Map<String, String> _headers({String? token}) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': token,
      };

  Future<Map<String, dynamic>> _get(String path, {String? token}) =>
      _withRetry(() async {
    final client = _buildClient();
    try {
      final resp = await client
          .get(Uri.parse('$baseUrl$path'), headers: _headers(token: token))
          .timeout(_kTimeout);

      if (resp.statusCode != 200) {
        throw XBoardApiException(resp.statusCode, resp.body);
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      _assertSuccess(json);
      final data = json['data'];
      if (data is Map<String, dynamic>) return data;
      // Some endpoints wrap data differently
      return json;
    } finally {
      client.close();
    }
  });

  Future<Map<String, dynamic>> _post(String path, {
    Map<String, dynamic>? body,
    String? token,
  }) => _withRetry(() async {
    final client = _buildClient();
    try {
      final resp = await client
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
      _assertSuccess(json);
      final data = json['data'];
      if (data is Map<String, dynamic>) return data;
      return json;
    } finally {
      client.close();
    }
  });

  /// Like [_get] but returns the raw `data` value without forcing Map type.
  /// Used for endpoints whose `data` is a List or scalar (String, bool, etc.).
  Future<dynamic> _getRawData(
    String path, {
    String? token,
    Map<String, String>? queryParams,
  }) => _withRetry(() async {
    final client = _buildClient();
    try {
      var uri = Uri.parse('$baseUrl$path');
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final resp = await client
          .get(uri, headers: _headers(token: token))
          .timeout(_kTimeout);

      if (resp.statusCode != 200) {
        throw XBoardApiException(resp.statusCode, resp.body);
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      _assertSuccess(json);
      return json['data'];
    } finally {
      client.close();
    }
  });

  /// Like [_post] but returns the raw `data` value without forcing Map type.
  Future<dynamic> _postRawData(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) => _withRetry(() async {
    final client = _buildClient();
    try {
      final resp = await client
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
      _assertSuccess(json);
      return json['data'];
    } finally {
      client.close();
    }
  });

  /// Checks XBoard's `status` field (present when HTTP 200 but business-level
  /// failure). Throws [XBoardApiException] with the server's `message`.
  static void _assertSuccess(Map<String, dynamic> json) {
    final status = json['status'];
    if (status == 'fail' || status == false || status == 0) {
      final msg = json['message'] as String? ??
          json['error'] as String? ??
          'Request failed';
      throw XBoardApiException(0, msg);
    }
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

class UserProfile {
  final int? planId;
  final String? planName;
  /// Total traffic quota in bytes — XBoard users.transfer_enable (converted from plan GB to bytes).
  /// u / d (uploadUsed / downloadUsed) are also in bytes.
  final int? transferEnable;
  final int? uploadUsed;    // upload bytes used   — XBoard field: u
  final int? downloadUsed;  // download bytes used — XBoard field: d
  final int? expiredAt; // unix timestamp
  final String? email;
  final String? uuid;
  /// Number of devices currently online — XBoard field: online_count
  final int? onlineCount;
  /// Maximum allowed devices — from nested plan.device_limit
  final int? deviceLimit;

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

  /// XBoard may return numeric fields as int, double, or bool (tinyint).
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return null;
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
        if (onlineCount != null) 'online_count': onlineCount,
        if (deviceLimit != null) 'device_limit': deviceLimit,
      };
}

class SubscribeResult {
  final String content;
  final Map<String, String> headers;

  SubscribeResult({required this.content, required this.headers});
}

/// Combined result from /api/v1/user/getSubscribe.
/// Contains the full user profile (plan, traffic, expiry) + the subscribe URL.
class SubscribeData {
  final UserProfile profile;
  final String subscribeUrl;

  SubscribeData({required this.profile, required this.subscribeUrl});
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
      id: _toInt(json['id']),
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: _toInt(json['created_at']),
    );
  }

  /// XBoard may return numeric fields as int, double, or bool (tinyint).
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return null;
  }
}

// ------------------------------------------------------------------
// Emby model
// ------------------------------------------------------------------

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

// ------------------------------------------------------------------
// Order list result
// ------------------------------------------------------------------

class OrderListResult {
  final List<StoreOrder> orders;
  final bool hasMore;
  const OrderListResult({required this.orders, required this.hasMore});
}

// ------------------------------------------------------------------
// Exception
// ------------------------------------------------------------------

class XBoardApiException implements Exception {
  final int statusCode;
  final String _body;

  XBoardApiException(this.statusCode, this._body);

  /// User-friendly error message.
  /// If the body is a JSON string with a `message` field, extract it.
  /// Otherwise return the raw body. Caches the result to avoid repeated parsing.
  late final String message = _extractMessage();

  String _extractMessage() {
    // If _assertSuccess already extracted the message, body is plain text — return as-is.
    // Only attempt JSON decode when body looks like a JSON object.
    if (!_body.startsWith('{')) return _body;
    try {
      final json = jsonDecode(_body) as Map<String, dynamic>;
      return json['message'] as String? ?? _body;
    } catch (_) {
      return _body;
    }
  }

  @override
  String toString() => 'XBoardApiException($statusCode): $message';
}
