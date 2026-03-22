import '../../domain/emby/emby_info_entity.dart';
import '../datasources/xboard_api.dart';

/// Fetches Emby service info from XBoard API.
///
/// Receives [XBoardApi] via constructor — never constructs its own client.
class EmbyRepository {
  final XBoardApi _api;

  EmbyRepository({required XBoardApi api}) : _api = api;

  /// Returns Emby info, or rethrows [XBoardApiException].
  Future<EmbyInfo?> getEmby(String token) {
    return _api.getEmby(token);
  }
}
