import '../../../constants.dart';
import '../../../domain/announcements/announcement_entity.dart';
import '../../../domain/emby/emby_info_entity.dart';
import '../../../domain/store/coupon_result.dart';
import '../../../domain/store/order_list_result.dart';
import '../../../domain/store/payment_method.dart';
import '../../../domain/store/store_order.dart';
import '../../store/checkout_result.dart';
import '../../../domain/store/store_plan.dart';
import 'client.dart';
import 'errors.dart';
import 'models.dart';

/// REST client for XBoard panel API.
///
/// Was a 742-line monolith (`xboard_api.dart`) containing the HTTP client
/// build, retry policy, business-error detection, models, exception type,
/// and ~15 endpoint methods all jammed together. Split into the
/// `lib/infrastructure/datasources/xboard/` module:
///
///   • client.dart  — HTTP transport (retry / fallback / get / post / raw)
///   • errors.dart  — XBoardApiException
///   • models.dart  — LoginResponse, UserProfile, SubscribeData, SubscribeResult
///   • api.dart     — this file: endpoint methods only
///
/// The endpoint methods are now ~3 lines each ("compose path → call client →
/// wrap result") and the file fits comfortably under 350 lines.
class XBoardApi {
  XBoardApi({
    required this.baseUrl,
    this.fallbackUrls = const <String>[],
    this.proxyPort,
    this.timeout = XBoardHttpClient.defaultTimeout,
    this.maxRetries = XBoardHttpClient.defaultMaxRetries,
  }) : _http = XBoardHttpClient(
          baseUrl: baseUrl,
          fallbackUrls: fallbackUrls,
          proxyPort: proxyPort,
          timeout: timeout,
          maxRetries: maxRetries,
        );

  final String baseUrl;
  final int? proxyPort;
  final Duration timeout;
  final int maxRetries;

  /// Ordered fallback hosts — see [XBoardHttpClient.fallbackUrls].
  final List<String> fallbackUrls;

  final XBoardHttpClient _http;

  // Tests inject a mock http.Client via [XBoardHttpClient.testClientFactory]
  // directly — see test/services/xboard_api_test.dart.

  // ── Auth ────────────────────────────────────────────────────────────────

  /// Login with email and password. Returns auth data containing the token.
  Future<LoginResponse> login(String email, String password) async {
    final resp = await _http.post('/api/v1/passport/auth/login', body: {
      'email': email,
      'password': password,
    });
    return LoginResponse.fromJson(resp);
  }

  // ── User profile + subscription URL ─────────────────────────────────────

  /// Get full subscribe data in a single request.
  ///
  /// Calls `/api/v1/user/getSubscribe` which returns:
  ///   - plan.name (nested plan object with full plan info)
  ///   - u / d (upload / download bytes used)
  ///   - transfer_enable (total quota)
  ///   - expired_at, email, uuid
  ///   - subscribe_url
  ///
  /// Use this instead of getUserInfo — `/api/v1/user/info` does NOT return
  /// u/d traffic fields or the nested plan object.
  Future<SubscribeData> getSubscribeData(String token) async {
    // Use getRawData so assertSuccess is called — catches status:"fail".
    final raw =
        await _http.getRawData('/api/v1/user/getSubscribe', token: token);
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

  // ── Password ────────────────────────────────────────────────────────────

  /// POST /api/v1/user/changePassword
  Future<void> changePassword({
    required String token,
    required String oldPassword,
    required String newPassword,
  }) async {
    await _http.postRawData(
      '/api/v1/user/changePassword',
      token: token,
      body: {
        'old_password': oldPassword,
        'new_password': newPassword,
      },
    );
  }

  // ── Subscription config download (direct GET, not XBoard JSON API) ──────

  /// Download the actual subscription config (Clash YAML) from a subscribe
  /// URL. This is a direct HTTP GET to the subscription URL, not an XBoard
  /// API call. Returns both the YAML content and parsed
  /// `subscription-userinfo` headers.
  Future<SubscribeResult> fetchSubscribeConfig(String subscribeUrl) async {
    final client = XBoardHttpClient.buildClient(
      proxyPort: proxyPort,
      connectionTimeout: timeout,
    );
    try {
      final response = await client.get(
        Uri.parse(subscribeUrl),
        headers: {'User-Agent': AppConstants.userAgent},
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
    } finally {
      client.close();
    }
  }

  // ── Emby ────────────────────────────────────────────────────────────────

  /// Get Emby service info for the current user. Returns null if no access.
  Future<EmbyInfo?> getEmby(String token) async {
    try {
      final resp = await _http.get('/api/v1/user/emby', token: token);
      return EmbyInfo.fromJson(resp);
    } on XBoardApiException catch (e) {
      // 404 / empty data means no Emby for this user
      if (e.statusCode == 404 || e.statusCode == 0) return null;
      rethrow;
    }
  }

  // ── Announcements ───────────────────────────────────────────────────────

  Future<List<Announcement>> getAnnouncements(String token) async {
    final resp = await _http.get('/api/v1/user/notice/fetch', token: token);
    final list = resp['data'] as List? ?? [];
    return list
        .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Store — Plans ───────────────────────────────────────────────────────

  /// Fetch all available subscription plans.
  /// GET /api/v1/user/plan/fetch
  Future<List<StorePlan>> getPlans(String token) async {
    final raw = await _http.getRawData('/api/v1/user/plan/fetch', token: token);
    final list = raw as List? ?? [];
    return list
        .map((e) => StorePlan.fromJson(e as Map<String, dynamic>))
        .where((p) => p.show && p.sell)
        .toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
  }

  // ── Store — Orders ──────────────────────────────────────────────────────

  /// Create a new order. POST /api/v1/user/order/save → trade_no string.
  Future<String> createOrder({
    required String token,
    required int planId,
    required String period,
    String? couponCode,
  }) async {
    final raw = await _http.postRawData(
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
    final raw = await _http.getRawData(
      '/api/v1/user/order/detail',
      token: token,
      queryParams: {'trade_no': tradeNo},
    );
    return StoreOrder.fromJson(raw as Map<String, dynamic>);
  }

  /// Checkout / pay for an order. POST /api/v1/user/order/checkout
  /// Returns a [CheckoutResult] with payment URL or QR code.
  Future<CheckoutResult> checkoutOrder({
    required String token,
    required String tradeNo,
    int? method,
  }) async {
    final raw = await _http.postRawData(
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
      final raw = await _http.getRawData(
        '/api/v1/user/order/getPaymentMethod',
        token: token,
      );
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
    final raw = await _http.postRawData(
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
  ///   A) a plain List directly in `data`
  ///   B) a Laravel paginator: `{data: [...], total, current_page, last_page}`
  Future<OrderListResult> fetchOrders({
    required String token,
    int page = 1,
  }) async {
    final raw = await _http.getRawData(
      '/api/v1/user/order/fetch',
      token: token,
      queryParams: {'page': '$page'},
    );

    if (raw is List) {
      final orders = raw
          .map((e) => StoreOrder.fromJson(e as Map<String, dynamic>))
          .toList();
      return OrderListResult(orders: orders, hasMore: false);
    }

    if (raw is Map<String, dynamic>) {
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

    return const OrderListResult(orders: [], hasMore: false);
  }

  /// Cancel a pending order. POST /api/v1/user/order/cancel
  /// Throws [XBoardApiException] on server-side rejection (already paid).
  Future<void> cancelOrder({
    required String token,
    required String tradeNo,
  }) async {
    await _http.postRawData(
      '/api/v1/user/order/cancel',
      token: token,
      body: {'trade_no': tradeNo},
    );
  }
}
