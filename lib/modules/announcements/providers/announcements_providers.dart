import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/auth_token_service.dart';
import '../../../infrastructure/datasources/xboard_api.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import 'announcement_read_service.dart';

const _kDefaultApiHost = 'https://d7ccm19ki90mg.cloudfront.net';

/// Fetches announcements from XBoard. Returns empty list when not logged in.
final announcementsProvider = FutureProvider<List<Announcement>>((ref) async {
  final token = ref.watch(authProvider).token;
  if (token == null) return [];

  final host =
      await AuthTokenService.instance.getApiHost() ?? _kDefaultApiHost;
  final api = XBoardApi(baseUrl: host);
  try {
    return await api.getAnnouncements(token);
  } on XBoardApiException catch (e) {
    if (e.statusCode == 401 || e.statusCode == 403) {
      ref.read(authProvider.notifier).handleUnauthenticated();
      return [];
    }
    rethrow;
  }
});

/// Locally-read announcement IDs (Set<int>), notifier for invalidation.
final readAnnouncementIdsProvider =
    StateNotifierProvider<_ReadIdsNotifier, Set<int>>(
  (_) => _ReadIdsNotifier(),
);

class _ReadIdsNotifier extends StateNotifier<Set<int>> {
  _ReadIdsNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    final ids = await AnnouncementReadService.instance.getReadIds();
    if (mounted) state = ids;
  }

  Future<void> markRead(int id) async {
    await AnnouncementReadService.instance.markRead(id);
    if (mounted) state = {...state, id};
  }

  Future<void> markAllRead(Iterable<int> ids) async {
    await AnnouncementReadService.instance.markAllRead(ids);
    if (mounted) state = {...state, ...ids};
  }
}
