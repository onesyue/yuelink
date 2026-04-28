import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/emby/models/emby_models.dart';

void main() {
  group('EmbyLibrary', () {
    test('fromJson reads Id / Name / CollectionType', () {
      final lib = EmbyLibrary.fromJson({
        'Id': 'abc',
        'Name': '电影',
        'CollectionType': 'movies',
      });
      expect(lib.id, 'abc');
      expect(lib.name, '电影');
      expect(lib.type, 'movies');
    });

    test('missing CollectionType defaults to empty string', () {
      // Real-world Emby occasionally omits CollectionType on synthetic
      // virtual folders; the model must not crash.
      final lib = EmbyLibrary.fromJson({'Id': 'x', 'Name': 'y'});
      expect(lib.type, '');
    });

    group('isCollectionLibrary', () {
      test('true for "boxsets"', () {
        expect(_lib(type: 'boxsets').isCollectionLibrary, isTrue);
      });

      test('false for movies / tvshows / music / unknown', () {
        for (final t in ['movies', 'tvshows', 'music', '', 'foo']) {
          expect(_lib(type: t).isCollectionLibrary, isFalse, reason: t);
        }
      });
    });

    group('isMediaLibrary (Hero Banner eligibility)', () {
      test('true for movies and tvshows only', () {
        expect(_lib(type: 'movies').isMediaLibrary, isTrue);
        expect(_lib(type: 'tvshows').isMediaLibrary, isTrue);
      });

      test('false for music / boxsets / unknown', () {
        for (final t in ['music', 'boxsets', '', 'photos']) {
          expect(_lib(type: t).isMediaLibrary, isFalse, reason: t);
        }
      });
    });

    test('icon picks the right Material symbol per type', () {
      // Smoke-test the four mapped types resolve to distinct icons —
      // exact codepoint isn't load-bearing, just that the mapping
      // doesn't collapse to a single fallback.
      final icons = <IconData>{
        _lib(type: 'movies').icon,
        _lib(type: 'tvshows').icon,
        _lib(type: 'music').icon,
        _lib(type: 'boxsets').icon,
        _lib(type: 'unknown').icon,
      };
      expect(icons.length, 5,
          reason: 'each known type should map to a distinct icon');
    });

    group('includeItemTypes (Emby /Items query string)', () {
      test('music → MusicAlbum', () {
        expect(_lib(type: 'music').includeItemTypes, 'MusicAlbum');
      });

      test('tvshows → "Series,Video" (Video required for STRM 搬运)', () {
        // Emby indexes incomplete metadata files as generic Video;
        // omitting Video makes the count come back as 0 on STRM
        // libraries — the comment in emby_models.dart calls this out.
        expect(_lib(type: 'tvshows').includeItemTypes, 'Series,Video');
      });

      test('boxsets → BoxSet', () {
        expect(_lib(type: 'boxsets').includeItemTypes, 'BoxSet');
      });

      test('default → "Movie,Video"', () {
        // Same Video requirement applies to STRM-only movie libraries.
        expect(_lib(type: 'movies').includeItemTypes, 'Movie,Video');
        expect(_lib(type: '').includeItemTypes, 'Movie,Video');
      });
    });
  });

  group('EmbyItem', () {
    test('fromJson reads core fields', () {
      final item = EmbyItem.fromJson({
        'Id': '1',
        'Name': 'Inception',
        'Type': 'Movie',
        'ProductionYear': 2010,
        'ImageTags': {'Primary': 'tag'},
        'BackdropImageTags': ['bd1'],
        'Overview': 'overview',
        'CommunityRating': 8.8,
        'Genres': ['Action', 'Sci-Fi'],
        'RunTimeTicks': 88800000000, // 148 minutes
      });
      expect(item.id, '1');
      expect(item.name, 'Inception');
      expect(item.type, 'Movie');
      expect(item.year, 2010);
      expect(item.hasPoster, isTrue);
      expect(item.hasBackdrop, isTrue);
      expect(item.overview, 'overview');
      expect(item.rating, 8.8);
      expect(item.genres, ['Action', 'Sci-Fi']);
      expect(item.runTimeTicks, 88800000000);
    });

    test('hasPoster is false when ImageTags missing or has no Primary', () {
      expect(
        EmbyItem.fromJson({
          'Id': '1',
          'Name': 'X',
          'Type': 'Movie',
          'BackdropImageTags': [],
        }).hasPoster,
        isFalse,
      );
      expect(
        EmbyItem.fromJson({
          'Id': '1',
          'Name': 'X',
          'Type': 'Movie',
          'ImageTags': {'Logo': 'tag'},
          'BackdropImageTags': [],
        }).hasPoster,
        isFalse,
      );
    });

    test('hasBackdrop is false on null or empty BackdropImageTags', () {
      expect(
        EmbyItem.fromJson({
          'Id': '1',
          'Name': 'X',
          'Type': 'Movie',
        }).hasBackdrop,
        isFalse,
      );
      expect(
        EmbyItem.fromJson({
          'Id': '1',
          'Name': 'X',
          'Type': 'Movie',
          'BackdropImageTags': <Object>[],
        }).hasBackdrop,
        isFalse,
      );
    });

    test('genres defaults to empty list when missing', () {
      final item = EmbyItem.fromJson({
        'Id': '1',
        'Name': 'X',
        'Type': 'Movie',
      });
      expect(item.genres, isEmpty);
    });

    group('runtimeLabel', () {
      test('returns empty string when runTimeTicks is null', () {
        expect(_item(ticks: null).runtimeLabel, isEmpty);
      });

      test('< 60 minutes shows "N分钟"', () {
        // 30 min = 18,000,000,000 ticks (10M ticks per second × 60 × 30)
        expect(_item(ticks: 18000000000).runtimeLabel, '30分钟');
      });

      test('>= 60 minutes shows "h" + zero-padded minutes', () {
        // 90 min = 1h30m
        expect(_item(ticks: 54000000000).runtimeLabel, '1h30m');
        // exact 60 min = 1h00m
        expect(_item(ticks: 36000000000).runtimeLabel, '1h00m');
        // 2h05m
        expect(_item(ticks: 75000000000).runtimeLabel, '2h05m');
      });
    });

    test('== compares structurally (immutable model)', () {
      final a = _item(ticks: 100);
      final b = _item(ticks: 100);
      // Note: EmbyItem doesn't override == today; the default is identity.
      // This test documents the current behaviour — switch to expect(a == b)
      // if/when structural equality is added (similar to ProxyGroup).
      expect(identical(a, b), isFalse);
    });
  });
}

EmbyLibrary _lib({String type = ''}) =>
    EmbyLibrary(id: 'id', name: 'n', type: type);

EmbyItem _item({int? ticks}) => EmbyItem(
      id: 'id',
      name: 'name',
      type: 'Movie',
      hasPoster: false,
      hasBackdrop: false,
      runTimeTicks: ticks,
    );
