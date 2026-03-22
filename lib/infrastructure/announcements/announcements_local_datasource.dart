import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists locally-read announcement IDs as a JSON array in
/// `read_announcement_ids.json` (app documents directory).
///
/// No singleton — instantiated via Riverpod for testability.
class AnnouncementsLocalDatasource {
  static const _kFileName = 'read_announcement_ids.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_kFileName');
  }

  Future<Set<int>> getReadIds() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      return list.whereType<int>().toSet();
    } catch (e) {
      debugPrint('[Announcements] getReadIds failed: $e');
      return {};
    }
  }

  Future<void> markRead(int id) async {
    final ids = await getReadIds();
    if (ids.contains(id)) return;
    ids.add(id);
    await _save(ids);
  }

  Future<void> markAllRead(Iterable<int> ids) async {
    final current = await getReadIds();
    current.addAll(ids);
    await _save(current);
  }

  Future<void> _save(Set<int> ids) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(ids.toList()));
    } catch (e) {
      debugPrint('[Announcements] save failed: $e');
    }
  }
}
