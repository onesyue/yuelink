import 'dart:convert';
import 'dart:io';

import '../../domain/checkin/checkin_result_entity.dart';
import '../datasources/xboard_api.dart';

/// Repository for check-in operations via YueLink Checkin API.
///
/// The check-in API runs as a standalone service on yue.yuebao.website,
/// separate from the XBoard panel. Uses the same XBoard Sanctum token
/// for authentication.
///
/// This repository maintains its own HTTP client because the checkin
/// server is independent from XBoard — reusing XBoardApi would be incorrect.
class CheckinRepository {
  static const _baseUrl = 'https://yue.yuebao.website';

  /// Perform a check-in.
  /// POST /api/client/checkin
  Future<CheckinResult> checkin(String token) async {
    final data = await _post('/api/client/checkin', token: token);
    return CheckinResult.fromJson(data);
  }

  /// Get current check-in status for today.
  /// GET /api/client/checkin/status
  Future<CheckinResult?> getCheckinStatus(String token) async {
    try {
      final data = await _get('/api/client/checkin/status', token: token);
      return CheckinResult.fromJson(data);
    } on XBoardApiException catch (e) {
      // 404 = endpoint not ready yet, treat as not checked in
      if (e.statusCode == 404) return null;
      rethrow;
    } catch (_) {
      return null;
    }
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path,
      {required String token}) async {
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

  Future<Map<String, dynamic>> _post(String path,
      {required String token, Map<String, dynamic>? body}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final request = await client.postUrl(uri);
      request.headers.set('Authorization', token);
      request.headers.set('Accept', 'application/json');
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode(body ?? {})));
      final response = await request.close();
      final respBody = await response.transform(utf8.decoder).join();
      final json = jsonDecode(respBody) as Map<String, dynamic>;
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
    // Catch any non-2xx status (e.g. 502 from auth failures) that slipped
    // past the checks above — prevents treating server errors as success.
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
