import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'errors.dart';

/// Internal HTTP transport for XBoard API calls.
///
/// Owns:
///   • the [http.Client] factory (always backed by [dart:io]'s [HttpClient]
///     so TLS SNI is sent — required by CloudFront)
///   • the per-call retry loop with backoff
///   • the CloudFront → direct-origin fallback when CDN returns 502/503
///   • the four `_get` / `_post` / `_getRawData` / `_postRawData` helpers
///   • XBoard's `status:"fail"` business-error detection (`_assertSuccess`)
///
/// Was previously inlined inside `XBoardApi` (lib/infrastructure/datasources/
/// xboard_api.dart, 742 lines). Extracted as part of the split into the
/// `xboard/` module so the endpoint methods in `api.dart` are pure
/// "compose path → call _get → wrap result", with no transport noise.
class XBoardHttpClient {
  static const defaultTimeout = Duration(seconds: 20);
  static const defaultMaxRetries = 3;

  XBoardHttpClient({
    required this.baseUrl,
    List<String>? fallbackUrls,
    this.proxyPort,
    this.timeout = defaultTimeout,
    this.maxRetries = defaultMaxRetries,
  }) : fallbackUrls = fallbackUrls ?? const [];

  final String baseUrl;
  final int? proxyPort;
  final Duration timeout;
  final int maxRetries;

  /// Ordered fallback hosts tried one-by-one (single-attempt, no retry
  /// per URL) after baseUrl exhausts its retries with a "host-unreachable"
  /// class error (502/503/504 / timeout / socket / TLS handshake).
  /// Non-transient errors (401/403/404/business-level) never trigger
  /// fallback — they'd fail the same way on every host.
  final List<String> fallbackUrls;

  /// Override in tests to inject a mock [http.Client].
  @visibleForTesting
  static http.Client Function({int? proxyPort})? testClientFactory;

  /// Build an [http.Client] backed by [dart:io]'s [HttpClient]. Ensures
  /// SNI is always sent (required by CloudFront), explicit timeouts, and
  /// works on all Flutter platforms.
  ///
  /// When [proxyPort] is provided, routes through YueLink's local mihomo
  /// mixed-port (`127.0.0.1:proxyPort`). Otherwise, bypasses the system proxy
  /// via explicit `findProxy = DIRECT`.
  ///
  /// Why direct matters for bootstrap: YueLink's own TUN / system-proxy mode sets the OS proxy to
  /// `127.0.0.1:mixedPort`, which means Dart's HttpClient (that respects
  /// the system proxy by default) would route XBoard API calls THROUGH our
  /// own mihomo. When a subscription's nodes are stale after an app
  /// update, the VPN connects but traffic blackholes — and so does every
  /// subsequent `getSubscribeData` / `userInfo` call, because they're now
  /// dependent on the very VPN they're trying to refresh. Users reported
  /// having to open a second VPN app first "until the username loads" to
  /// break the loop. Direct CloudFront/origin gets us out of this.
  ///
  /// Using separate statements instead of cascade (`..findProxy = ...`)
  /// because Dart's arrow-function + cascade parser has a known bug
  /// documented in CLAUDE.md — mis-typing the assignment on some Dart
  /// versions.
  static http.Client buildClient({
    int? proxyPort,
    Duration connectionTimeout = defaultTimeout,
  }) {
    if (testClientFactory != null) {
      return testClientFactory!(proxyPort: proxyPort);
    }
    final inner = HttpClient();
    if (proxyPort != null && proxyPort > 0) {
      inner.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    } else {
      inner.findProxy = (_) => 'DIRECT';
    }
    inner.connectionTimeout = connectionTimeout;
    inner.idleTimeout = const Duration(seconds: 30);
    return IOClient(inner);
  }

  // ── Retry policy ────────────────────────────────────────────────────────

  static const _retryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  static bool _isTransient(Object e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is HandshakeException) return true;
    if (e is HttpException) return true;
    if (e is XBoardApiException && e.statusCode >= 500) return true;
    return false;
  }

  /// Execute [fn] on the direct path with automatic retry on transient errors.
  /// Non-retryable errors (auth, business logic) propagate immediately.
  ///
  /// Host fallback: after baseUrl exhausts its retries with a transport-
  /// level error (502/503/504 / timeout / socket / TLS handshake), each
  /// URL in [fallbackUrls] is tried once in order. Single-attempt per
  /// fallback — already 3 × retry on primary; adding more retries per
  /// fallback would push the worst-case latency past user patience.
  Future<T> _withDirectRetry<T>(Future<T> Function(String url) fn) async {
    Object? lastError;
    final attempts = maxRetries < 1 ? 1 : maxRetries;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await fn(baseUrl);
      } catch (e) {
        lastError = e;
        final isLast = attempt == attempts - 1;
        if (isLast) break;
        if (!_isTransient(e)) rethrow;
        debugPrint('[XBoardApi] Retry ${attempt + 1}/$attempts after: $e');
        await Future.delayed(_retryDelays[attempt]);
      }
    }

    if (_isHostUnreachable(lastError) && fallbackUrls.isNotEmpty) {
      for (final url in fallbackUrls) {
        debugPrint('[XBoardApi] Primary unreachable, trying fallback: $url');
        try {
          return await fn(url);
        } catch (e) {
          lastError = e;
          if (!_isHostUnreachable(e)) {
            // Got a non-transport error (4xx/business) — same answer on
            // any host, don't bother with more fallbacks.
            break;
          }
        }
      }
    }

    debugPrint('[XBoardApi] All hosts exhausted: $lastError');
    throw lastError!;
  }

  /// Runtime business APIs prefer the local proxy when the core is already
  /// connected, but always keep the old direct bootstrap path as a fallback.
  ///
  /// This avoids the "panel domain blocked by GFW" failure mode after login
  /// without reintroducing the older self-dependency loop where auth /
  /// subscription refresh became impossible if the current node was broken.
  Future<T> _withRouting<T>(
    Future<T> Function(String url, {int? proxyPort}) fn,
  ) async {
    final port = proxyPort;
    if (port != null && port > 0) {
      try {
        return await fn(baseUrl, proxyPort: port);
      } catch (e) {
        if (!_isHostUnreachable(e)) rethrow;
        debugPrint(
            '[XBoardApi] Proxied route failed, falling back to direct: $e');
      }
    }
    return _withDirectRetry((url) => fn(url));
  }

  /// "This host isn't reachable on this network" — the canonical trigger
  /// for falling back to another origin. Anything else (4xx, business
  /// `status:fail`) would produce identical results on every host.
  static bool _isHostUnreachable(Object? e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is HandshakeException) return true;
    if (e is XBoardApiException) {
      final c = e.statusCode;
      return c == 502 || c == 503 || c == 504;
    }
    return false;
  }

  // ── Headers + business-level error check ────────────────────────────────

  Map<String, String> _headers({String? token}) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': ?token,
      };

  /// XBoard returns HTTP 200 with `{"status":"fail","message":"..."}` for
  /// business-level failures. Throws [XBoardApiException] when seen so the
  /// caller never has to dispatch on the body shape.
  static void assertSuccess(Map<String, dynamic> json) {
    final status = json['status'];
    if (status == 'fail' || status == false || status == 0) {
      final msg = json['message'] as String? ??
          json['error'] as String? ??
          'Request failed';
      throw XBoardApiException(0, msg);
    }
  }

  // ── Request helpers ─────────────────────────────────────────────────────

  /// GET that expects `data` to be a `Map<String, dynamic>`.
  Future<Map<String, dynamic>> get(String path, {String? token}) =>
      _withRouting((url, {proxyPort}) async {
        final client =
            buildClient(proxyPort: proxyPort, connectionTimeout: timeout);
        try {
          final resp = await client
              .get(Uri.parse('$url$path'), headers: _headers(token: token))
              .timeout(timeout);
          if (resp.statusCode != 200) {
            throw XBoardApiException(resp.statusCode, resp.body);
          }
          final json = jsonDecode(resp.body) as Map<String, dynamic>;
          assertSuccess(json);
          final data = json['data'];
          if (data is Map<String, dynamic>) return data;
          return json;
        } finally {
          client.close();
        }
      });

  /// POST that expects `data` to be a `Map<String, dynamic>`.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) =>
      _withRouting((url, {proxyPort}) async {
        final client =
            buildClient(proxyPort: proxyPort, connectionTimeout: timeout);
        try {
          final resp = await client
              .post(
                Uri.parse('$url$path'),
                headers: _headers(token: token),
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(timeout);
          if (resp.statusCode != 200) {
            throw XBoardApiException(resp.statusCode, resp.body);
          }
          final json = jsonDecode(resp.body) as Map<String, dynamic>;
          assertSuccess(json);
          final data = json['data'];
          if (data is Map<String, dynamic>) return data;
          return json;
        } finally {
          client.close();
        }
      });

  /// Like [get] but returns the raw `data` value without forcing Map type.
  /// Use for endpoints whose `data` is a List or scalar (String, bool, etc.).
  Future<dynamic> getRawData(
    String path, {
    String? token,
    Map<String, String>? queryParams,
  }) =>
      _withRouting((url, {proxyPort}) async {
        final client =
            buildClient(proxyPort: proxyPort, connectionTimeout: timeout);
        try {
          var uri = Uri.parse('$url$path');
          if (queryParams != null && queryParams.isNotEmpty) {
            uri = uri.replace(queryParameters: queryParams);
          }
          final resp = await client
              .get(uri, headers: _headers(token: token))
              .timeout(timeout);
          if (resp.statusCode != 200) {
            throw XBoardApiException(resp.statusCode, resp.body);
          }
          final json = jsonDecode(resp.body) as Map<String, dynamic>;
          assertSuccess(json);
          return json['data'];
        } finally {
          client.close();
        }
      });

  /// Like [post] but returns the raw `data` value without forcing Map type.
  Future<dynamic> postRawData(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) =>
      _withRouting((url, {proxyPort}) async {
        final client =
            buildClient(proxyPort: proxyPort, connectionTimeout: timeout);
        try {
          final resp = await client
              .post(
                Uri.parse('$url$path'),
                headers: _headers(token: token),
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(timeout);
          if (resp.statusCode != 200) {
            throw XBoardApiException(resp.statusCode, resp.body);
          }
          final json = jsonDecode(resp.body) as Map<String, dynamic>;
          assertSuccess(json);
          return json['data'];
        } finally {
          client.close();
        }
      });
}
