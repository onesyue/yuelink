import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/announcements/announcement_entity.dart';
import '../../../infrastructure/announcements/announcements_local_datasource.dart';
import '../../../infrastructure/announcements/announcements_repository.dart';
import '../../../infrastructure/datasources/xboard_api.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';

// ── DI: Infrastructure instances ────────────────────────────────────────────

/// Single [AnnouncementsRepository] wired to the shared [XBoardApi].
final announcementsRepositoryProvider = Provider<AnnouncementsRepository>((ref) {
  final api = ref.watch(xboardApiProvider);
  return AnnouncementsRepository(api: api);
});

/// Single [AnnouncementsLocalDatasource] — keeps alive for the app lifetime.
final announcementsLocalDatasourceProvider =
    Provider<AnnouncementsLocalDatasource>((ref) {
  return AnnouncementsLocalDatasource();
});

// ── Data providers ──────────────────────────────────────────────────────────

/// Fetches announcements from XBoard. Returns empty list when not logged in.
final announcementsProvider =
    FutureProvider<List<Announcement>>((ref) async {
  final token = ref.watch(authProvider).token;
  if (token == null) return [];

  final repo = ref.watch(announcementsRepositoryProvider);
  try {
    return await repo.getAnnouncements(token);
  } on XBoardApiException catch (e) {
    if (e.statusCode == 401 || e.statusCode == 403) {
      ref.read(authProvider.notifier).handleUnauthenticated();
      return [];
    }
    rethrow;
  }
});

/// Locally-read announcement IDs (`Set<int>`), notifier for invalidation.
final readAnnouncementIdsProvider =
    NotifierProvider<ReadIdsNotifier, Set<int>>(
  ReadIdsNotifier.new,
);

class ReadIdsNotifier extends Notifier<Set<int>> {
  bool _disposed = false;

  @override
  Set<int> build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _load();
    return {};
  }

  AnnouncementsLocalDatasource get _datasource =>
      ref.read(announcementsLocalDatasourceProvider);

  Future<void> _load() async {
    final ids = await _datasource.getReadIds();
    if (!_disposed) state = ids;
  }

  Future<void> markRead(int id) async {
    await _datasource.markRead(id);
    if (!_disposed) state = {...state, id};
  }

  Future<void> markAllRead(Iterable<int> ids) async {
    await _datasource.markAllRead(ids);
    if (!_disposed) state = {...state, ...ids};
  }
}
