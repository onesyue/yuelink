import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emby/emby_client.dart';
import '../../emby/emby_providers.dart';
import '../home_content_provider.dart';

// ---------------------------------------------------------------------------
// Source enum
// ---------------------------------------------------------------------------

/// Data source for [embyPreviewProvider].
///
/// - [recent]   — Most recently added items (DateCreated descending).
///               This is the default shown on the dashboard.
/// - [featured] — Editor's picks: favourited items ranked by community
///               rating. Falls back to [recent] when no favourites exist.
///
/// Adding future sources (e.g. `trending`, `tagged`) only requires:
///   1. A new enum value here.
///   2. A `_fetch*` implementation in [embyPreviewProvider].
enum EmbyPreviewSource {
  recent,
  featured,
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Lightweight Emby item used only in the dashboard preview row.
class EmbyPreviewItem {
  final String id;
  final String name;
  final String type;
  final bool hasPoster;

  const EmbyPreviewItem({
    required this.id,
    required this.name,
    required this.type,
    required this.hasPoster,
  });

  factory EmbyPreviewItem.fromJson(Map<String, dynamic> j) {
    final imgTags = j['ImageTags'] as Map<String, dynamic>?;
    return EmbyPreviewItem(
      id: j['Id'] as String,
      name: j['Name'] as String? ?? '',
      type: j['Type'] as String? ?? '',
      hasPoster: imgTags?.containsKey('Primary') == true,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Fetches Emby items for the dashboard preview row.
///
/// Parameterised by [EmbyPreviewSource]:
/// - `EmbyPreviewSource.recent`   → most recently added (default)
/// - `EmbyPreviewSource.featured` → admin-favourited items; falls back to
///   recent when the server has no favourites
///
/// Returns `[]` (never throws) when:
/// - User has no Emby access or web-only access
/// - Any network / auth error (graceful degradation)
///
/// Degradation strategy per source:
///
/// **recent** (2 steps):
///   1. `IncludeItemTypes=Movie,Series,Video` + `SortBy=DateCreated,Descending`
///   2. Fallback: same without `IncludeItemTypes`
///      (STRM servers may index content as generic `Video` or `Folder`)
///
/// **featured** (4 steps):
///   1. `Filters=IsFavorite` + typed + `SortBy=CommunityRating,Descending`
///   2. `Filters=IsFavorite` + untyped (STRM servers)
///   3–4. If still empty → fall through to the [recent] two-step chain
final embyPreviewProvider =
    FutureProvider.family<List<EmbyPreviewItem>, EmbyPreviewSource>(
        (ref, source) async {
  final emby = await ref.watch(embyProvider.future);

  // No credentials → nothing to show; widget handles this via embyProvider
  if (emby == null || !emby.hasNativeAccess) return const [];

  final client = EmbyClient(
    serverUrl: emby.serverBaseUrl!,
    accessToken: emby.parsedAccessToken!,
    userId: emby.parsedUserId!,
  );
  // Close in finally instead of `ref.onDispose(client.close)`. onDispose
  // fires the moment the provider is invalidated (refresh, ancestor
  // rebuild), which would slam the door shut on the in-flight fetch
  // below — observed as `ClientException: HTTP request failed. Client
  // is already closed.` (macOS 2026-04-28). The client's lifetime is
  // exactly this one fetch; finally is the right scope.

  final uid = emby.parsedUserId!;
  final cfg = ref.watch(embyPreviewConfigProvider);
  final limit = '${cfg.maxItems}';

  try {
    if (source == EmbyPreviewSource.featured) {
      final items = await _fetchFeatured(client, uid, limit: limit);
      if (items.isNotEmpty) return items;
      // Featured empty → fall through to recent
    }
    final items = await _fetchRecent(client, uid, limit: limit);
    if (items.isNotEmpty) return items;

    // Final fallback: fetch ALL items (no type/sort filter) — catches
    // servers with non-standard library types.
    final data = await client.get('/emby/Users/$uid/Items', {
      'Limit': limit,
      'Recursive': 'true',
      'Fields': 'ImageTags',
      'ExcludeItemTypes': 'Folder,CollectionFolder,UserView,Season',
    });
    return _parseItems(data);
  } catch (e) {
    debugPrint('[EmbyPreview] fetch failed: $e');
    return const [];
  } finally {
    client.close();
  }
});

// ---------------------------------------------------------------------------
// Source-specific fetch helpers
// ---------------------------------------------------------------------------

/// Fetch most-recently-added items (typed → untyped fallback).
Future<List<EmbyPreviewItem>> _fetchRecent(
    EmbyClient client, String uid, {String limit = '10'}) async {
  // Step 1: typed
  final data = await client.get('/emby/Users/$uid/Items', {
    'Limit': limit,
    'SortBy': 'DateCreated,SortName',
    'SortOrder': 'Descending',
    'Recursive': 'true',
    'IncludeItemTypes': 'Movie,Series,Video',
    'Fields': 'ImageTags',
  });
  final items = _parseItems(data);
  if (items.isNotEmpty) return items;

  // Step 2: untyped fallback (STRM / unscanned libraries)
  final data2 = await client.get('/emby/Users/$uid/Items', {
    'Limit': limit,
    'SortBy': 'DateCreated,SortName',
    'SortOrder': 'Descending',
    'Recursive': 'true',
    'Fields': 'ImageTags',
  });
  return _parseItems(data2);
}

/// Fetch admin-favourited items, ranked by community rating.
/// Returns `[]` if the server has no favourites (caller falls back to recent).
Future<List<EmbyPreviewItem>> _fetchFeatured(
    EmbyClient client, String uid, {String limit = '10'}) async {
  // Step 1: typed favourites
  final data = await client.get('/emby/Users/$uid/Items', {
    'Limit': limit,
    'Filters': 'IsFavorite',
    'SortBy': 'CommunityRating,SortName',
    'SortOrder': 'Descending',
    'Recursive': 'true',
    'IncludeItemTypes': 'Movie,Series,Video',
    'Fields': 'ImageTags',
  });
  final items = _parseItems(data);
  if (items.isNotEmpty) return items;

  // Step 2: untyped favourites (STRM servers)
  final data2 = await client.get('/emby/Users/$uid/Items', {
    'Limit': limit,
    'Filters': 'IsFavorite',
    'SortBy': 'CommunityRating,SortName',
    'SortOrder': 'Descending',
    'Recursive': 'true',
    'Fields': 'ImageTags',
  });
  return _parseItems(data2);
}

// ---------------------------------------------------------------------------
// Shared parser
// ---------------------------------------------------------------------------

List<EmbyPreviewItem> _parseItems(Map<String, dynamic> data) {
  final list = data['Items'] as List<dynamic>? ?? [];
  return list
      .map((e) => EmbyPreviewItem.fromJson(e as Map<String, dynamic>))
      .toList();
}
