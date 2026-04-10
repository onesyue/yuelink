import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/module_entity.dart';
import 'module_parser.dart';
import 'module_repository.dart';

/// Downloads and refreshes Surge .sgmodule files.
class ModuleDownloader {
  ModuleDownloader._();

  static const _userAgent = 'YueLink/1.0';
  static const _timeout = Duration(seconds: 15);

  /// Download the raw .sgmodule content from [url].
  ///
  /// Uses IOClient(HttpClient()) to ensure TLS SNI is sent correctly on all
  /// platforms. Throws a descriptive [Exception] on failure.
  static Future<String> download(String url) async {
    debugPrint('[ModuleDownloader] downloading: $url');

    final uri = Uri.parse(url);
    // Reject HTTP — module/script content is injected into MITM config,
    // so plaintext transport allows man-in-the-middle code injection.
    if (uri.scheme != 'https') {
      throw Exception(
          'Insecure URL rejected: only HTTPS module URLs are allowed');
    }

    final client = HttpClient();
    client.connectionTimeout = _timeout;
    // Per CLAUDE.md: set properties as separate statements (cascade bug)
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'text/plain, */*');

      final response = await request.close().timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception(
            'HTTP ${response.statusCode} downloading module from $url');
      }

      final buffer = StringBuffer();
      await for (final chunk in response.transform(const SystemEncoding().decoder)) {
        buffer.write(chunk);
      }
      final content = buffer.toString();
      debugPrint('[ModuleDownloader] downloaded ${content.length} bytes');
      return content;
    } on SocketException catch (e) {
      throw Exception('Network error downloading module: ${e.message}');
    } on TimeoutException {
      throw Exception('Timeout downloading module from $url (>${_timeout.inSeconds}s)');
    } catch (e) {
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Full flow: download → parse → fetch script contents → create/update record.
  ///
  /// If [existing] is provided and the checksum hasn't changed, returns the
  /// existing record unchanged (no-op update).
  ///
  /// Returns the saved [ModuleRecord].
  static Future<ModuleRecord> fetchAndSave(
    String url, {
    ModuleRecord? existing,
  }) async {
    final content = await download(url);
    final checksum = moduleChecksum(content);

    // No-op if content didn't change
    if (existing != null && checksum == existing.checksum) {
      debugPrint('[ModuleDownloader] checksum unchanged for ${existing.name}');
      final updated = existing.copyWith(lastFetchedAt: DateTime.now());
      const repo = ModuleRepository();
      await repo.save(updated);
      return updated;
    }

    // Parse
    final parseResult = ModuleParser.parse(content);

    // Fetch JS source for http-response scripts.
    final scripts = await _fetchScriptContents(parseResult.scripts);

    // Determine name: prefer parsed name, fall back to URL basename
    final effectiveName = parseResult.name.isNotEmpty
        ? parseResult.name
        : _nameFromUrl(url);

    final now = DateTime.now();

    final record = existing != null
        ? existing.copyWith(
            name: effectiveName,
            desc: parseResult.desc,
            originalContent: content,
            checksum: checksum,
            versionTag: parseResult.versionTag ?? existing.versionTag,
            author: parseResult.author ?? existing.author,
            iconUrl: parseResult.iconUrl ?? existing.iconUrl,
            homepage: parseResult.homepage ?? existing.homepage,
            category: parseResult.category ?? existing.category,
            rules: parseResult.rules,
            mitmHostnames: parseResult.mitmHostnames,
            urlRewrites: parseResult.urlRewrites,
            headerRewrites: parseResult.headerRewrites,
            scripts: scripts,
            mapLocals: parseResult.mapLocals,
            unsupportedCounts: parseResult.unsupportedCounts,
            parseWarnings: parseResult.warnings,
            updatedAt: now,
            lastFetchedAt: now,
          )
        : ModuleRecord(
            id: generateModuleId(),
            name: effectiveName,
            desc: parseResult.desc,
            sourceUrl: url,
            originalContent: content,
            checksum: checksum,
            enabled: true,
            versionTag: parseResult.versionTag,
            author: parseResult.author,
            iconUrl: parseResult.iconUrl,
            homepage: parseResult.homepage,
            category: parseResult.category,
            rules: parseResult.rules,
            mitmHostnames: parseResult.mitmHostnames,
            urlRewrites: parseResult.urlRewrites,
            headerRewrites: parseResult.headerRewrites,
            scripts: scripts,
            mapLocals: parseResult.mapLocals,
            unsupportedCounts: parseResult.unsupportedCounts,
            parseWarnings: parseResult.warnings,
            createdAt: now,
            updatedAt: now,
            lastFetchedAt: now,
          );

    const repo = ModuleRepository();
    await repo.save(record);
    debugPrint('[ModuleDownloader] saved module: ${record.name} (id=${record.id})');
    return record;
  }

  /// Fetch the JavaScript source for each http-response script.
  /// Non-http-response types and scripts whose path is not a valid HTTP URL
  /// are returned unchanged. Failures are logged and the script is kept with
  /// scriptContent = null (so the engine silently skips it).
  static Future<List<ModuleScript>> _fetchScriptContents(
      List<ModuleScript> scripts) async {
    if (scripts.isEmpty) return scripts;

    final result = <ModuleScript>[];
    for (final s in scripts) {
      if (s.scriptType != 'http-response') {
        result.add(s);
        continue;
      }
      final path = s.scriptPath.trim();
      if (!path.startsWith('https://')) {
        // Reject non-HTTPS script paths (including http://) — scripts are
        // injected into MITM engine, so plaintext transport is unsafe.
        debugPrint('[ModuleDownloader] skipping non-HTTPS script path: $path');
        result.add(s);
        continue;
      }
      try {
        final jsCode = await download(path);
        debugPrint(
            '[ModuleDownloader] fetched script ${s.name}: ${jsCode.length} bytes');
        result.add(s.copyWith(scriptContent: jsCode));
      } catch (e) {
        debugPrint('[ModuleDownloader] failed to fetch script ${s.name}: $e');
        result.add(s); // keep with scriptContent = null
      }
    }
    return result;
  }

  static String _nameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final seg = uri.pathSegments;
      if (seg.isNotEmpty) {
        var name = seg.last;
        if (name.toLowerCase().endsWith('.sgmodule')) {
          name = name.substring(0, name.length - 9);
        }
        if (name.isNotEmpty) return name;
      }
      var host = uri.host;
      if (host.startsWith('www.')) host = host.substring(4);
      if (host.isNotEmpty) return host;
    } catch (_) {}
    return 'Module';
  }
}
