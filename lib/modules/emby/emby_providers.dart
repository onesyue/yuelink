import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/auth_token_service.dart';
import '../../domain/emby/emby_info_entity.dart';
import '../../infrastructure/emby/emby_repository.dart';
import '../yue_auth/providers/yue_auth_providers.dart';

// ── DI: Infrastructure instance ─────────────────────────────────────────────

final embyRepositoryProvider = Provider<EmbyRepository>((ref) {
  final api = ref.watch(businessXboardApiProvider);
  return EmbyRepository(api: api);
});

// ── Data provider ───────────────────────────────────────────────────────────

/// Fetches the current user's Emby service info.
/// Returns null when not logged in or no Emby access.
///
/// Cache-first behaviour (v1.0.23): if a non-stale `EmbyInfo` is sitting
/// in SecureStorage (24h TTL), return it immediately and kick off a
/// background refresh. This shaves ~300-800 ms off every Emby tab cold
/// paint — the dashboard previously stalled waiting for XBoard's `/emby`
/// HTTP roundtrip on every launch even though the value rarely changes.
///
/// On the refresh path: parse failures / non-401 errors fall back to the
/// cached value (better stale than crashing the tab); 401/403 routes
/// through `handleUnauthenticated()` which itself clears the cache.
final embyProvider = FutureProvider<EmbyInfo?>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return null;

  final auth = AuthTokenService.instance;
  final repo = ref.watch(embyRepositoryProvider);

  Future<EmbyInfo?> fetchAndCache() async {
    try {
      final fresh = await repo.getEmby(token);
      if (fresh != null) {
        await auth.cacheEmbyInfo(fresh);
      }
      return fresh;
    } on XBoardApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await ref.read(authProvider.notifier).handleUnauthenticated();
        return null;
      }
      rethrow;
    }
  }

  // Cache hit → return immediately, refresh in the background. The
  // refresh result lands via `ref.invalidateSelf` so the UI re-paints
  // with fresh data even when the cached value is still valid.
  final cached = await auth.getCachedEmbyInfo();
  final stale = await auth.isEmbyInfoStale();
  if (cached != null && !stale) {
    // Fire-and-forget background refresh. Errors are swallowed — the
    // cached value is good enough for display; the next foreground
    // call (or logout/login) gets another shot.
    () async {
      try {
        final fresh = await fetchAndCache();
        if (fresh != null && fresh.toJson().toString() != cached.toJson().toString()) {
          ref.invalidateSelf();
        }
      } catch (e) {
        debugPrint('[embyProvider] background refresh failed: $e');
      }
    }();
    return cached;
  }

  // Cache miss / stale: hard-fetch.
  return fetchAndCache();
});
