import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/surge_modules/module_entity.dart';

/// Manages persistent storage for [ModuleRecord]s.
///
/// Storage layout (under ApplicationSupport):
///   `modules/index.json`        — JSON array of ModuleRecord objects
///   `modules_raw/<id>.sgmodule` — raw .sgmodule text for each module
///
/// Follows the same Completer-based mutex pattern as ProfileRepository.
class ModuleRepository {
  const ModuleRepository();

  static const _indexDir = 'modules';
  static const _indexFile = 'index.json';
  static const _rawDir = 'modules_raw';

  // ── Mutex ──────────────────────────────────────────────────────────────

  static Completer<void>? _indexLock;

  static Future<T> _withIndexLock<T>(Future<T> Function() action) async {
    while (_indexLock != null) {
      await _indexLock!.future;
    }
    _indexLock = Completer<void>();
    try {
      return await action();
    } finally {
      _indexLock!.complete();
      _indexLock = null;
    }
  }

  // ── File paths ─────────────────────────────────────────────────────────

  static Future<File> _indexFilePath() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/$_indexDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$_indexFile');
  }

  static Future<File> _rawFilePath(String id) async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/$_rawDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$id.sgmodule');
  }

  // ── Atomic write helpers ────────────────────────────────────────────────

  static Future<void> _atomicWriteString(File dest, String content) async {
    final tmp = File('${dest.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(dest.path);
  }

  // ── Public API ─────────────────────────────────────────────────────────

  /// Load all module records from the index file.
  /// JSON decode runs in a background Isolate to keep the main thread free.
  Future<List<ModuleRecord>> loadAll() async {
    final file = await _indexFilePath();
    if (!await file.exists()) return [];
    final jsonStr = await file.readAsString();
    if (jsonStr.trim().isEmpty) return [];
    try {
      return await Isolate.run(() {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        return list
            .map((e) => ModuleRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      debugPrint('[ModuleRepository] loadAll decode error: $e');
      return [];
    }
  }

  /// Get a single module by ID. Returns null if not found.
  Future<ModuleRecord?> getById(String id) async {
    final all = await loadAll();
    try {
      return all.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Create or update a module record in the index.
  /// Also writes the raw content to the raw file.
  Future<void> save(ModuleRecord module) async {
    // Write raw content
    if (module.originalContent.isNotEmpty) {
      final rawFile = await _rawFilePath(module.id);
      await _atomicWriteString(rawFile, module.originalContent);
    }

    await _withIndexLock(() async {
      final all = await loadAll();
      final idx = all.indexWhere((m) => m.id == module.id);
      if (idx >= 0) {
        all[idx] = module;
      } else {
        all.add(module);
      }
      await _saveAll(all);
    });
  }

  /// Delete a module by ID. Also removes the raw file.
  Future<void> delete(String id) async {
    // Delete raw file
    try {
      final rawFile = await _rawFilePath(id);
      if (await rawFile.exists()) await rawFile.delete();
    } catch (e) {
      debugPrint('[ModuleRepository] delete raw file error: $e');
    }

    await _withIndexLock(() async {
      final all = await loadAll();
      all.removeWhere((m) => m.id == id);
      await _saveAll(all);
    });
  }

  /// Toggle the enabled state of a module.
  Future<void> setEnabled(String id, bool enabled) async {
    await _withIndexLock(() async {
      final all = await loadAll();
      final idx = all.indexWhere((m) => m.id == id);
      if (idx >= 0) {
        all[idx] = all[idx].copyWith(enabled: enabled, updatedAt: DateTime.now());
        await _saveAll(all);
      }
    });
  }

  /// Returns all MITM hostnames from all enabled modules (deduplicated).
  Future<List<String>> getEnabledMitmHostnames() async {
    final all = await loadAll();
    final seen = <String>{};
    for (final module in all) {
      if (!module.enabled) continue;
      seen.addAll(module.mitmHostnames);
    }
    return seen.toList();
  }

  /// Returns flattened raw rule strings from all enabled modules.
  /// Rules are in Clash/mihomo format (TYPE,TARGET,ACTION).
  Future<List<String>> getEnabledRules() async {
    final all = await loadAll();
    final result = <String>[];
    for (final module in all) {
      if (!module.enabled) continue;
      for (final rule in module.rules) {
        result.add(rule.raw);
      }
    }
    return result;
  }

  /// Returns the raw .sgmodule content for a module.
  Future<String?> getRawContent(String id) async {
    try {
      final rawFile = await _rawFilePath(id);
      if (!await rawFile.exists()) return null;
      return rawFile.readAsString();
    } catch (e) {
      debugPrint('[ModuleRepository] getRawContent error: $e');
      return null;
    }
  }

  /// Check if the new content differs from the stored checksum.
  Future<bool> checksumChanged(String id, String newContent) async {
    final module = await getById(id);
    if (module == null) return true;
    final newChecksum = _sha256(newContent);
    return newChecksum != module.checksum;
  }

  // ── Private helpers ────────────────────────────────────────────────────

  static Future<void> _saveAll(List<ModuleRecord> modules) async {
    final file = await _indexFilePath();
    final jsonList = modules.map((m) => m.toJson()).toList();
    final encoded = await Isolate.run(() => jsonEncode(jsonList));
    await _atomicWriteString(file, encoded);
  }

  /// Compute SHA-256 hex digest of a string.
  static String _sha256(String content) =>
      sha256.convert(utf8.encode(content)).toString();
}

/// Compute a SHA-256 checksum of raw .sgmodule content.
/// Public so ModuleDownloader can use it for change detection.
///
/// Previously this was a 32-bit DJB2-style rolling hash, which has trivial
/// collisions (e.g. "Aa" and "BB" hash to the same value). Module repositories
/// use this for "did the upstream content change" checks, and the old hash
/// would skip real updates that happened to collide. Now uses real SHA-256
/// from package:crypto.
String moduleChecksum(String content) =>
    sha256.convert(utf8.encode(content)).toString();

/// Generate a module ID similar to the profile ID pattern.
String generateModuleId() {
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
  final rand = (DateTime.now().microsecondsSinceEpoch ^ ts.hashCode)
      .abs()
      .toRadixString(16)
      .padLeft(6, '0')
      .substring(0, 6);
  return '$ts$rand';
}
