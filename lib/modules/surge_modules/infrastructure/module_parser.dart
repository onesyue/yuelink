import 'package:flutter/foundation.dart';

import '../domain/module_entity.dart';

/// Result of parsing a .sgmodule file.
class ModuleParseResult {
  final String name;
  final String desc;
  final String? author;
  final String? iconUrl;
  final String? homepage;
  final String? category;
  final String? versionTag;

  final List<ModuleRule> rules;
  final List<String> mitmHostnames;
  final List<UrlRewriteRule> urlRewrites;
  final List<HeaderRewriteRule> headerRewrites;
  final List<ModuleScript> scripts;
  final List<MapLocalRule> mapLocals;

  final UnsupportedCounts unsupportedCounts;
  final List<String> warnings;

  const ModuleParseResult({
    required this.name,
    required this.desc,
    this.author,
    this.iconUrl,
    this.homepage,
    this.category,
    this.versionTag,
    required this.rules,
    required this.mitmHostnames,
    required this.urlRewrites,
    required this.headerRewrites,
    required this.scripts,
    required this.mapLocals,
    required this.unsupportedCounts,
    required this.warnings,
  });
}

/// Pure Dart parser for Surge .sgmodule INI-format files.
///
/// Handles:
/// - Metadata directives: #!name, #!desc, #!author, #!icon, #!homepage,
///   #!category, #!version
/// - Sections: [Rule], [URL Rewrite], [Header Rewrite], [Script], [Map Local],
///   [MITM], [Panel] (Panel is recorded but contents not parsed)
/// - Unknown sections are skipped gracefully
/// - One bad line never fails the whole parse
class ModuleParser {
  static const _tag = '[ModuleParser]';

  // Known section names
  static const _secRule = 'rule';
  static const _secUrlRewrite = 'url rewrite';
  static const _secHeaderRewrite = 'header rewrite';
  static const _secScript = 'script';
  static const _secMapLocal = 'map local';
  static const _secMitm = 'mitm';
  static const _secPanel = 'panel';

  /// Parse raw .sgmodule content into a [ModuleParseResult].
  static ModuleParseResult parse(String content) {
    // Mutable state
    String name = '';
    String desc = '';
    String? author;
    String? iconUrl;
    String? homepage;
    String? category;
    String? versionTag;

    final rules = <ModuleRule>[];
    final mitmHostnames = <String>[];
    final urlRewrites = <UrlRewriteRule>[];
    final headerRewrites = <HeaderRewriteRule>[];
    final scripts = <ModuleScript>[];
    final mapLocals = <MapLocalRule>[];
    final warnings = <String>[];

    int panelCount = 0;

    String? currentSection;
    int lineNum = 0;

    for (final rawLine in content.split('\n')) {
      lineNum++;
      final line = rawLine.trim();

      // Skip empty lines
      if (line.isEmpty) continue;

      // Metadata directives (#!key = value) — must come before comment skip
      if (line.startsWith('#!')) {
        final eqIdx = line.indexOf('=');
        if (eqIdx > 2) {
          final key = line.substring(2, eqIdx).trim().toLowerCase();
          final value = line.substring(eqIdx + 1).trim();
          switch (key) {
            case 'name':
              name = value;
            case 'desc':
            case 'description':
              desc = value;
            case 'author':
              author = value;
            case 'icon':
              iconUrl = value;
            case 'homepage':
              homepage = value;
            case 'category':
              category = value;
            case 'version':
              versionTag = value;
          }
        }
        continue;
      }

      // Skip regular comment lines
      if (line.startsWith('#') || line.startsWith(';')) continue;

      // Section header
      if (line.startsWith('[') && line.endsWith(']')) {
        currentSection = line.substring(1, line.length - 1).toLowerCase().trim();
        debugPrint('$_tag section: [$currentSection]');
        continue;
      }

      // Content line — route to current section parser
      if (currentSection == null) continue;

      try {
        switch (currentSection) {
          case _secRule:
            final rule = _parseRule(line);
            if (rule != null) rules.add(rule);

          case _secUrlRewrite:
            final rw = _parseUrlRewrite(line);
            if (rw != null) urlRewrites.add(rw);

          case _secHeaderRewrite:
            final hr = _parseHeaderRewrite(line);
            if (hr != null) headerRewrites.add(hr);

          case _secScript:
            final sc = _parseScript(line);
            if (sc != null) scripts.add(sc);

          case _secMapLocal:
            final ml = _parseMapLocal(line);
            if (ml != null) mapLocals.add(ml);

          case _secMitm:
            _parseMitmLine(line, mitmHostnames);

          case _secPanel:
            panelCount++;

          default:
            // Unknown section — skip silently
            break;
        }
      } catch (e) {
        final msg = 'Line $lineNum parse error: $e';
        debugPrint('$_tag $msg');
        warnings.add(msg);
      }
    }

    if (name.isEmpty) {
      warnings.add('No #!name directive found — using URL basename as name');
    }

    final unsupported = UnsupportedCounts(
      mitmCount: mitmHostnames.length,
      urlRewriteCount: urlRewrites.length,
      headerRewriteCount: headerRewrites.length,
      scriptCount: scripts.length,
      mapLocalCount: mapLocals.length,
      panelCount: panelCount,
    );

    debugPrint('$_tag parsed: name=$name rules=${rules.length} '
        'mitm=${mitmHostnames.length} urlRewrites=${urlRewrites.length} '
        'scripts=${scripts.length} mapLocals=${mapLocals.length} '
        'panels=$panelCount warnings=${warnings.length}');

    return ModuleParseResult(
      name: name,
      desc: desc,
      author: author,
      iconUrl: iconUrl,
      homepage: homepage,
      category: category,
      versionTag: versionTag,
      rules: rules,
      mitmHostnames: mitmHostnames,
      urlRewrites: urlRewrites,
      headerRewrites: headerRewrites,
      scripts: scripts,
      mapLocals: mapLocals,
      unsupportedCounts: unsupported,
      warnings: warnings,
    );
  }

  // ── Rule parser ─────────────────────────────────────────────────────────────

  /// Parse a single Surge rule line: TYPE,TARGET,ACTION[,OPTIONS]
  static ModuleRule? _parseRule(String line) {
    final parts = line.split(',');
    if (parts.isEmpty) return null;

    final type = parts[0].trim().toUpperCase();

    // Rules with no target: FINAL, MATCH
    if (type == 'FINAL' || type == 'MATCH') {
      final action = parts.length > 1 ? parts[1].trim() : 'DIRECT';
      return ModuleRule(raw: line, type: type, action: action);
    }

    if (parts.length < 3) {
      // Could be "TYPE,ACTION" (e.g. some short rules) — lenient
      if (parts.length == 2) {
        return ModuleRule(
          raw: line,
          type: type,
          target: parts[1].trim(),
          action: 'DIRECT',
        );
      }
      return null;
    }

    final target = parts[1].trim();
    final action = parts[2].trim();
    final options = parts.length > 3 ? parts.sublist(3).join(',').trim() : null;

    return ModuleRule(
      raw: line,
      type: type,
      target: target,
      action: action,
      options: options?.isNotEmpty == true ? options : null,
    );
  }

  // ── URL Rewrite parser ──────────────────────────────────────────────────────

  /// Format: PATTERN [REPLACEMENT] TYPE
  /// or:     PATTERN - reject
  static UrlRewriteRule? _parseUrlRewrite(String line) {
    // Split on whitespace, respecting quoted strings is not needed for Surge
    final parts = _splitWhitespace(line);
    if (parts.isEmpty) return null;

    if (parts.length == 1) {
      return UrlRewriteRule(
        pattern: parts[0],
        rewriteType: 'reject',
        raw: line,
      );
    }

    // Last token is always the type
    final lastToken = parts.last.toLowerCase();
    const knownTypes = {'reject', '302', '307', 'header', 'reject-200',
        'reject-img', 'reject-dict', 'reject-array'};

    if (knownTypes.contains(lastToken)) {
      final pattern = parts[0];
      final replacement = parts.length > 2 ? parts.sublist(1, parts.length - 1).join(' ') : null;
      return UrlRewriteRule(
        pattern: pattern,
        replacement: replacement,
        rewriteType: lastToken,
        raw: line,
      );
    }

    // Two-token: PATTERN TYPE
    if (parts.length == 2) {
      return UrlRewriteRule(
        pattern: parts[0],
        rewriteType: parts[1].toLowerCase(),
        raw: line,
      );
    }

    // Three+ tokens: PATTERN REPLACEMENT TYPE (standard)
    return UrlRewriteRule(
      pattern: parts[0],
      replacement: parts.sublist(1, parts.length - 1).join(' '),
      rewriteType: parts.last.toLowerCase(),
      raw: line,
    );
  }

  // ── Header Rewrite parser ───────────────────────────────────────────────────

  /// Format: PATTERN ACTION HEADER_NAME [HEADER_VALUE]
  static HeaderRewriteRule? _parseHeaderRewrite(String line) {
    final parts = _splitWhitespace(line);
    if (parts.length < 2) return null;

    final pattern = parts[0];
    final action = parts.length > 1 ? parts[1].toLowerCase() : 'header-replace';

    String? headerName;
    String? headerValue;

    if (parts.length >= 3) {
      headerName = parts[2];
    }
    if (parts.length >= 4) {
      headerValue = parts.sublist(3).join(' ');
    }

    return HeaderRewriteRule(
      pattern: pattern,
      headerAction: action,
      headerName: headerName,
      headerValue: headerValue,
      raw: line,
    );
  }

  // ── Script parser ───────────────────────────────────────────────────────────

  /// Format: NAME = type=http-request,pattern=PATTERN,script-path=PATH[,...]
  static ModuleScript? _parseScript(String line) {
    final eqIdx = line.indexOf('=');
    if (eqIdx < 0) return null;

    final scriptName = line.substring(0, eqIdx).trim();
    final valueStr = line.substring(eqIdx + 1).trim();

    // Parse key=value pairs separated by commas
    // Be lenient — split by comma, then by first '='
    final attrs = <String, String>{};
    for (final part in valueStr.split(',')) {
      final kv = part.trim();
      final kvEq = kv.indexOf('=');
      if (kvEq > 0) {
        final k = kv.substring(0, kvEq).trim().toLowerCase();
        final v = kv.substring(kvEq + 1).trim();
        attrs[k] = v;
      }
    }

    final scriptType = attrs['type'] ?? 'generic';
    final pattern = attrs['pattern'];
    final scriptPath = attrs['script-path'] ?? attrs['path'] ?? '';
    final requiresBody = (attrs['requires-body'] ?? 'false').toLowerCase() == 'true';
    final cronExpression = attrs['cron-expression'] ?? attrs['cron'];

    return ModuleScript(
      name: scriptName,
      scriptType: scriptType,
      pattern: pattern,
      scriptPath: scriptPath,
      requiresBody: requiresBody,
      cronExpression: cronExpression,
      raw: line,
    );
  }

  // ── Map Local parser ────────────────────────────────────────────────────────

  /// Format: PATTERN DATA_URL
  static MapLocalRule? _parseMapLocal(String line) {
    final parts = _splitWhitespace(line);
    if (parts.length < 2) return null;
    return MapLocalRule(
      pattern: parts[0],
      dataUrl: parts.sublist(1).join(' '),
      raw: line,
    );
  }

  // ── MITM parser ─────────────────────────────────────────────────────────────

  /// MITM section lines look like:
  ///   hostname = %APPEND% domain1, domain2
  ///   hostname = domain1, domain2   (full replace)
  static void _parseMitmLine(String line, List<String> hostnames) {
    final eqIdx = line.indexOf('=');
    if (eqIdx < 0) return;

    final key = line.substring(0, eqIdx).trim().toLowerCase();
    if (key != 'hostname') return;

    var value = line.substring(eqIdx + 1).trim();

    // Strip %APPEND% or %INSERT% prefix
    value = value
        .replaceFirst(RegExp(r'^%APPEND%\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^%INSERT%\s*', caseSensitive: false), '');

    for (final host in value.split(',')) {
      final h = host.trim();
      if (h.isNotEmpty) {
        hostnames.add(h);
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static List<String> _splitWhitespace(String s) =>
      s.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
}
