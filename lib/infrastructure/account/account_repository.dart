import 'dart:convert';
import 'dart:io';

import '../../domain/account/account_overview.dart';
import '../../domain/account/notice.dart';
import '../datasources/xboard/index.dart';

/// Repository for account overview and quick-action link data.
///
/// Uses the same standalone YueLink Checkin API server (yue.yuebao.website)
/// as [CheckinRepository], with the same HttpClient style.
class AccountRepository {
  static const _baseUrl = 'https://yue.yuebao.website';

  // ── Public API ───────────────────────────────────────────────────────────

  /// Fetch account overview for the current user.
  /// GET /api/client/account/overview  (Bearer token required)
  /// Returns null on any error so the UI can show an error state without crashing.
  Future<AccountOverview?> getAccountOverview(String token) async {
    try {
      final data = await _get('/api/client/account/overview', token: token);
      return AccountOverview.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Fetch user notices (Bearer token required).
  /// GET /api/client/account/notices
  /// Returns empty list on any error.
  Future<List<AccountNotice>> getNotices(String token) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      try {
        final uri = Uri.parse('$_baseUrl/api/client/account/notices');
        final request = await client.getUrl(uri);
        request.headers.set('Authorization', token);
        request.headers.set('Accept', 'application/json');
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (response.statusCode < 200 || response.statusCode >= 300) return [];
        final data = json['data'];
        if (data is List) {
          return data
              .whereType<Map<String, dynamic>>()
              .map((e) => AccountNotice.fromJson(e))
              .toList();
        }
        return [];
      } finally {
        client.close();
      }
    } catch (_) {
      return [];
    }
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path, {required String token}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final request = await client.getUrl(uri);
      request.headers.set('Authorization', token);
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      _assertSuccess(json, response.statusCode);
      return json['data'] as Map<String, dynamic>? ?? json;
    } finally {
      client.close();
    }
  }

  void _assertSuccess(Map<String, dynamic> json, int statusCode) {
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
      throw XBoardApiException(200, json['message']?.toString() ?? 'Unknown error');
    }
  }
}
