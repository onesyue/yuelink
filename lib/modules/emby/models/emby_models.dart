import 'package:flutter/material.dart';

/// Models extracted from `emby_media_page.dart`. They were private
/// (`_Library` / `_Item`) when the page was a single 1372-line file;
/// pulling them out removes the temptation to make every Emby UI a
/// monolith and makes them reusable from `emby_detail_page.dart`,
/// `library_grid_page.dart`, and tests.

/// Emby library / collection metadata.
///
/// Mapped from `/emby/Users/{userId}/Views`. The `type` string follows
/// Emby's `CollectionType` taxonomy (`movies`, `tvshows`, `music`,
/// `boxsets`, …); empty string means "unknown" and falls into the
/// generic-folder bucket for icon + query purposes.
class EmbyLibrary {
  final String id;
  final String name;
  final String type;

  EmbyLibrary({required this.id, required this.name, required this.type});

  factory EmbyLibrary.fromJson(Map<String, dynamic> j) => EmbyLibrary(
        id: j['Id'] as String,
        name: j['Name'] as String,
        type: (j['CollectionType'] as String?) ?? '',
      );

  /// True for the collections / boxsets library.
  /// Emby 4.9 reports `CollectionType: "boxsets"`.
  bool get isCollectionLibrary => type == 'boxsets';

  /// True for real media libraries (movies / tvshows) — used to decide
  /// Hero Banner eligibility.
  bool get isMediaLibrary => type == 'movies' || type == 'tvshows';

  IconData get icon {
    switch (type) {
      case 'movies':
        return Icons.movie_outlined;
      case 'tvshows':
        return Icons.tv_outlined;
      case 'music':
        return Icons.music_note_outlined;
      case 'boxsets':
        return Icons.collections_bookmark_outlined;
      default:
        return Icons.folder_outlined;
    }
  }

  /// Comma-separated `IncludeItemTypes` value for the
  /// `/emby/Users/{userId}/Items` query against this library.
  ///
  /// `Video` is required for STRM-based 搬运 servers — Emby indexes
  /// incomplete metadata files as generic `Video` rather than `Movie`
  /// or `Episode`, so omitting it makes the count come back as 0.
  String get includeItemTypes {
    switch (type) {
      case 'music':
        return 'MusicAlbum';
      case 'tvshows':
        return 'Series,Video';
      case 'boxsets':
        return 'BoxSet';
      default:
        return 'Movie,Video';
    }
  }
}

/// Emby item (movie, episode, album, boxset, …).
///
/// `hasPoster` and `hasBackdrop` precompute the (cheap) presence checks
/// from the JSON so widgets don't re-walk `ImageTags` /
/// `BackdropImageTags` per build. `runTimeTicks` is the raw Emby
/// duration unit (100-nanosecond intervals); [runtimeLabel] is the
/// human-readable form used in card subtitles.
class EmbyItem {
  final String id;
  final String name;
  final String type;
  final int? year;
  final bool hasPoster;
  final bool hasBackdrop;
  final String? overview;
  final double? rating;
  final List<String> genres;
  final int? runTimeTicks;

  EmbyItem({
    required this.id,
    required this.name,
    required this.type,
    this.year,
    required this.hasPoster,
    required this.hasBackdrop,
    this.overview,
    this.rating,
    this.genres = const [],
    this.runTimeTicks,
  });

  factory EmbyItem.fromJson(Map<String, dynamic> j) {
    final imgTags = j['ImageTags'] as Map<String, dynamic>?;
    final backdrops = j['BackdropImageTags'] as List<dynamic>?;
    return EmbyItem(
      id: j['Id'] as String,
      name: j['Name'] as String,
      type: j['Type'] as String,
      year: j['ProductionYear'] as int?,
      hasPoster: imgTags?.containsKey('Primary') == true,
      hasBackdrop: backdrops != null && backdrops.isNotEmpty,
      overview: j['Overview'] as String?,
      rating: (j['CommunityRating'] as num?)?.toDouble(),
      genres: (j['Genres'] as List<dynamic>?)?.cast<String>() ?? const [],
      runTimeTicks: j['RunTimeTicks'] as int?,
    );
  }

  /// Human-readable runtime label, e.g. "1h 25m" or "45分钟". Empty
  /// string when [runTimeTicks] is null.
  String get runtimeLabel {
    if (runTimeTicks == null) return '';
    final min = runTimeTicks! ~/ 600000000;
    if (min >= 60) {
      return '${min ~/ 60}h${(min % 60).toString().padLeft(2, '0')}m';
    }
    return '$min分钟';
  }
}
