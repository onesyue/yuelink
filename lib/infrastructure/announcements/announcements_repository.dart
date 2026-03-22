import '../../domain/announcements/announcement_entity.dart';
import '../datasources/xboard_api.dart';

/// Fetches announcements from XBoard API.
///
/// Receives [XBoardApi] via constructor — never constructs its own client.
/// Token is passed per-call so the repository stays auth-agnostic.
class AnnouncementsRepository {
  final XBoardApi _api;

  AnnouncementsRepository({required XBoardApi api}) : _api = api;

  /// Returns all announcements, or rethrows [XBoardApiException].
  Future<List<Announcement>> getAnnouncements(String token) {
    return _api.getAnnouncements(token);
  }
}
