import '../../domain/checkin/checkin_result_entity.dart';
import '../../domain/checkin/sign_calendar_entity.dart';
import '../datasources/xboard/index.dart';
import '../transport/yuelink_http_client.dart';

/// Repository for check-in operations via YueLink Checkin API.
///
/// The check-in API runs as a standalone service on yue.yuebao.website,
/// separate from the XBoard panel. Uses the same XBoard Sanctum token
/// for authentication.
///
/// Transport (HttpClient + Bearer + status-code asserts) is shared with
/// [AccountRepository] and [HomeRepository] via [YueLinkHttpClient].
class CheckinRepository {
  CheckinRepository({int? proxyPort})
      : _http = YueLinkHttpClient(
          baseUrl: 'https://yue.yuebao.website',
          proxyPort: proxyPort,
        );

  final YueLinkHttpClient _http;

  /// Perform a check-in.
  /// POST /api/client/checkin
  Future<CheckinResult> checkin(String token) async {
    final data = await _http.post('/api/client/checkin', token: token);
    return CheckinResult.fromJson(data);
  }

  /// Get current check-in status for today.
  /// GET /api/client/checkin/status
  Future<CheckinResult?> getCheckinStatus(String token) async {
    try {
      final data = await _http.get('/api/client/checkin/status', token: token);
      return CheckinResult.fromJson(data);
    } on XBoardApiException catch (e) {
      // 404 = endpoint not ready yet, treat as not checked in
      if (e.statusCode == 404) return null;
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// 月度签到日历 — GET /api/client/checkin/history?month=YYYY-MM
  ///
  /// month 省略时取当月。返回 null 代表读取失败（网络 / 服务端 / 反序列化），
  /// 调用方应展示降级文案而不是空日历。
  ///
  /// checkin-api 用 `status:'error'` 表示业务错误（_assertSuccess 只拦
  /// `status:'fail'`），所以这里手动判断。
  Future<SignCalendarMonth?> fetchHistory(String token, {String? month}) async {
    try {
      final qs = (month != null && month.isNotEmpty) ? '?month=$month' : '';
      final data = await _http.get('/api/client/checkin/history$qs', token: token);
      if (data['status'] == 'error') return null;
      return SignCalendarMonth.fromJson(data);
    } on XBoardApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// 补签卡：扣 25 积分给昨天补 1 行历史 + streak +1
  /// POST /api/client/checkin/resign
  Future<ResignResult> resign(String token) async {
    try {
      final data = await _http.post('/api/client/checkin/resign', token: token);
      if (data['status'] == 'error') {
        final code = data['message'] as String? ?? 'unknown';
        return ResignResult.error(code, data.cast<String, dynamic>());
      }
      return ResignResult.success(data);
    } on XBoardApiException catch (e) {
      return ResignResult.error('http_${e.statusCode}');
    } catch (_) {
      return ResignResult.error('unknown');
    }
  }
}
