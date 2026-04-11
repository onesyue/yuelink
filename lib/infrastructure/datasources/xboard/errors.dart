import 'dart:convert';

/// Typed exception for all XBoard API failures (HTTP error, business-level
/// `status:"fail"`, or invalid response shape).
///
/// Was previously inlined at the bottom of `xboard_api.dart` (742 lines).
/// Extracted into its own file as part of the split into the
/// `lib/infrastructure/datasources/xboard/` module.
class XBoardApiException implements Exception {
  XBoardApiException(this.statusCode, this._body);

  final int statusCode;
  final String _body;

  /// User-friendly error message. If the body is JSON with a `message`
  /// field, extract it; otherwise return the raw body. Cached to avoid
  /// repeated parsing.
  late final String message = _extractMessage();

  String _extractMessage() {
    // HTML error pages (e.g. CloudFront 502) — extract a short summary.
    if (_body.contains('<HTML') || _body.contains('<html')) {
      if (statusCode == 502) return '服务暂时不可用，请稍后重试';
      if (statusCode == 503) return '服务维护中，请稍后重试';
      if (statusCode == 504) return '服务响应超时，请稍后重试';
      return '服务器错误 ($statusCode)';
    }
    // If _assertSuccess already extracted the message, body is plain text —
    // return as-is. Only attempt JSON decode when body looks like an object.
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
