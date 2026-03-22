import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/emby/emby_info_entity.dart';
import '../../infrastructure/datasources/xboard_api.dart';
import '../../infrastructure/emby/emby_repository.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';

// ── DI: Infrastructure instance ─────────────────────────────────────────────

final embyRepositoryProvider = Provider<EmbyRepository>((ref) {
  final api = ref.watch(xboardApiProvider);
  return EmbyRepository(api: api);
});

// ── Data provider ───────────────────────────────────────────────────────────

/// Fetches the current user's Emby service info.
/// Returns null when not logged in or no Emby access.
final embyProvider = FutureProvider<EmbyInfo?>((ref) async {
  final token = ref.watch(authProvider).token;
  if (token == null) return null;

  final repo = ref.watch(embyRepositoryProvider);
  try {
    return await repo.getEmby(token);
  } on XBoardApiException catch (e) {
    if (e.statusCode == 401 || e.statusCode == 403) {
      ref.read(authProvider.notifier).handleUnauthenticated();
      return null;
    }
    rethrow;
  }
});
