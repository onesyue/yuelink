import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../datasources/xboard/index.dart';

/// Shared transport helper for the standalone YueLink Checkin API server
/// (`yue.yuebao.website`) used by [AccountRepository], [CheckinRepository],
/// and [HomeRepository].
///
/// XBoard (CloudFront) traffic uses [XBoardHttpClient] — that owns retry,
/// fallback, and `assertSuccess` for the panel's `status:"fail"` shape, and
/// MUST NOT be replaced with this helper.
///
/// This helper covers only the simpler "raw `HttpClient`, manual
/// `getUrl`/`postUrl`, Bearer auth, JSON in/out" pattern that was repeated
/// across three repositories with identical shape.
///
/// CLAUDE.md: never chain `findProxy` on a cascade — set as a separate
/// statement. This helper does NOT use a proxy; callers that need one
/// (mihomo mixed-port) build their own `HttpClient` to keep that clear.
class YueLinkHttpClient {
  YueLinkHttpClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
    this.proxyPort,
  });

  final String baseUrl;
  final Duration timeout;
  final int? proxyPort;

  /// Build a raw [HttpClient] with timeout applied as a separate statement
  /// (per CLAUDE.md cascade-bug guidance).
  HttpClient _buildClient({int? proxyPort}) {
    final client = HttpClient();
    if (proxyPort != null && proxyPort > 0) {
      client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    } else {
      client.findProxy = (_) => 'DIRECT';
    }
    client.connectionTimeout = timeout;
    return client;
  }

  static bool _isRetryable(Object e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is HandshakeException) return true;
    if (e is HttpException) return true;
    if (e is XBoardApiException) {
      final c = e.statusCode;
      return c == 502 || c == 503 || c == 504;
    }
    return false;
  }

  Future<T> _withRouting<T>(Future<T> Function(HttpClient client) fn) async {
    final port = proxyPort;
    if (port != null && port > 0) {
      final proxied = _buildClient(proxyPort: port);
      try {
        return await fn(proxied);
      } catch (e) {
        if (!_isRetryable(e)) rethrow;
        debugPrint(
            '[YueLinkHttp] Proxied request failed, falling back to direct: $e');
      } finally {
        proxied.close();
      }
    }

    final direct = _buildClient();
    try {
      return await fn(direct);
    } finally {
      direct.close();
    }
  }

  /// GET returning decoded `data` Map (or whole body if `data` is absent).
  /// Throws [XBoardApiException] on non-2xx or `status:"fail"`.
  ///
  /// NOTE on timeouts: `HttpClient.connectionTimeout` only covers TCP
  /// handshake. Once the connection is open, `request.close()` and the
  /// body read can hang indefinitely if the server accepts the request
  /// but stops writing (seen in the wild on yue.yuebao.website during
  /// slow back-end moments — the `accountOverviewProvider` in settings
  /// would sit in `AsyncLoading` forever, freezing the "我的" card's
  /// "加载中" placeholder). Per-await `.timeout(timeout)` guards make
  /// every stuck call fail loudly after [timeout], letting the catch
  /// in [AccountRepository] / [CheckinRepository] degrade gracefully.
  Future<Map<String, dynamic>> get(String path, {String? token}) async {
    return _withRouting((client) async {
      final request = await client.getUrl(Uri.parse('$baseUrl$path'));
      if (token != null) request.headers.set('Authorization', token);
      request.headers.set('Accept', 'application/json');
      final response = await request.close().timeout(timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      final json = jsonDecode(body) as Map<String, dynamic>;
      _assertSuccess(json, response.statusCode);
      return json['data'] as Map<String, dynamic>? ?? json;
    });
  }

  /// POST returning decoded `data` Map.
  Future<Map<String, dynamic>> post(
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    return _withRouting((client) async {
      final request = await client.postUrl(Uri.parse('$baseUrl$path'));
      if (token != null) request.headers.set('Authorization', token);
      request.headers.set('Accept', 'application/json');
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode(body ?? {})));
      final response = await request.close().timeout(timeout);
      final respBody =
          await response.transform(utf8.decoder).join().timeout(timeout);
      final json = jsonDecode(respBody) as Map<String, dynamic>;
      _assertSuccess(json, response.statusCode);
      return json['data'] as Map<String, dynamic>? ?? json;
    });
  }

  /// Same as [get] but returns the parsed `data` value as a List, or empty
  /// on any error / non-2xx. Used by notice-style endpoints where errors
  /// should silently degrade.
  Future<List<Map<String, dynamic>>> getList(
    String path, {
    String? token,
  }) async {
    return _withRouting((client) async {
      final request = await client.getUrl(Uri.parse('$baseUrl$path'));
      if (token != null) request.headers.set('Authorization', token);
      request.headers.set('Accept', 'application/json');
      final response = await request.close().timeout(timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode == 502 ||
          response.statusCode == 503 ||
          response.statusCode == 504) {
        throw XBoardApiException(response.statusCode, body);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) return [];
      final json = jsonDecode(body) as Map<String, dynamic>;
      final data = json['data'];
      if (data is List) {
        return data.whereType<Map<String, dynamic>>().toList();
      }
      return [];
    });
  }

  /// Same as [get] but returns null on any error / non-2xx instead of
  /// throwing. Used by anonymous public endpoints (HomeRepository).
  Future<Map<String, dynamic>?> tryGet(String path, {String? token}) async {
    try {
      return await _withRouting((client) async {
        final request = await client.getUrl(Uri.parse('$baseUrl$path'));
        if (token != null) request.headers.set('Authorization', token);
        request.headers.set('Accept', 'application/json');
        final response = await request.close().timeout(timeout);
        if (response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504) {
          throw XBoardApiException(response.statusCode, 'Server error');
        }
        if (response.statusCode != 200) return null;
        final body =
            await response.transform(utf8.decoder).join().timeout(timeout);
        final json = jsonDecode(body) as Map<String, dynamic>;
        return json['data'] as Map<String, dynamic>? ?? json;
      });
    } catch (_) {
      return null;
    }
  }

  /// Mirrors the per-repo `_assertSuccess` that was duplicated in
  /// AccountRepository and CheckinRepository. Throws [XBoardApiException].
  ///
  /// CLAUDE.md (Checkin section): "must reject all non-2xx (don't treat
  /// 502 as success)" + "must only match genuine 'already checked'".
  static void _assertSuccess(Map<String, dynamic> json, int statusCode) {
    if (statusCode == 404) {
      throw XBoardApiException(404, 'Not found');
    }
    if (statusCode == 401 || statusCode == 403) {
      throw XBoardApiException(
        statusCode,
        json['detail']?.toString() ?? 'Unauthorized',
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw XBoardApiException(
        statusCode,
        json['detail']?.toString() ??
            json['message']?.toString() ??
            'Server error ($statusCode)',
      );
    }
    if (json['status'] == 'fail') {
      throw XBoardApiException(
        200,
        json['message']?.toString() ?? 'Unknown error',
      );
    }
  }
}
