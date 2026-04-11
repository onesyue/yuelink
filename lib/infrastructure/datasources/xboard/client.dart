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
  XBoardHttpClient({required this.baseUrl, this.fallbackUrl});

  final String baseUrl;

  /// Direct origin URL used when CloudFront (baseUrl) returns 502/503.
  /// Set via AuthTokenService / provider — typically `http://origin:port`.
  final String? fallbackUrl;

  static const _kTimeout = Duration(seconds: 20);

  /// Override in tests to inject a mock [http.Client].
  @visibleForTesting
  static http.Client Function()? testClientFactory;

  /// Build an [http.Client] backed by [dart:io]'s [HttpClient]. Ensures
  /// SNI is always sent (required by CloudFront), explicit timeouts, and
  /// works on all Flutter platforms.
  static http.Client buildClient() {
    if (testClientFactory != null) return testClientFactory!();
    final inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 30);
    return IOClient(inner);
  }

  // ── Retry policy ────────────────────────────────────────────────────────

  static const _maxRetries = 3;
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

  /// Execute [fn] with automatic retry on transient errors.
  /// Non-retryable errors (auth, business logic) propagate immediately.
  ///
  /// When [fallbackUrl] is set, a CloudFront 502/503 after all retries
  /// triggers one final attempt against the direct origin.
  Future<T> _withRetry<T>(Future<T> Function(String url) fn) async {
    Object? lastError;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await fn(baseUrl);
      } catch (e) {
        lastError = e;
        final isLast = attempt == _maxRetries - 1;
        if (isLast) break;
        if (!_isTransient(e)) rethrow;
        debugPrint('[XBoardApi] Retry ${attempt + 1}/$_maxRetries after: $e');
        await Future.delayed(_retryDelays[attempt]);
      }
    }

    if (fallbackUrl != null &&
        lastError is XBoardApiException &&
        (lastError.statusCode == 502 || lastError.statusCode == 503)) {
      debugPrint('[XBoardApi] CDN down, trying direct origin: $fallbackUrl');
      try {
        return await fn(fallbackUrl!);
      } catch (e) {
        debugPrint('[XBoardApi] Direct origin also failed: $e');
        rethrow;
      }
    }

    debugPrint('[XBoardApi] All $_maxRetries retries exhausted: $lastError');
    throw lastError!;
  }

  // ── Headers + business-level error check ────────────────────────────────

  Map<String, String> _headers({String? token}) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': token,
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
      _withRetry((url) async {
        final client = buildClient();
        try {
          final resp = await client
              .get(Uri.parse('$url$path'), headers: _headers(token: token))
              .timeout(_kTimeout);
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
      _withRetry((url) async {
        final client = buildClient();
        try {
          final resp = await client
              .post(
                Uri.parse('$url$path'),
                headers: _headers(token: token),
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(_kTimeout);
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
      _withRetry((url) async {
        final client = buildClient();
        try {
          var uri = Uri.parse('$url$path');
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
      _withRetry((url) async {
        final client = buildClient();
        try {
          final resp = await client
              .post(
                Uri.parse('$url$path'),
                headers: _headers(token: token),
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(_kTimeout);
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
