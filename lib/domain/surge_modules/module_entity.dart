import 'dart:convert';

// ── ModuleRule ────────────────────────────────────────────────────────────────

class ModuleRule {
  final String raw;
  final String type;
  final String? target;
  final String action;
  final String? options;

  const ModuleRule({
    required this.raw,
    required this.type,
    this.target,
    required this.action,
    this.options,
  });

  ModuleRule copyWith({
    String? raw,
    String? type,
    String? target,
    String? action,
    String? options,
  }) =>
      ModuleRule(
        raw: raw ?? this.raw,
        type: type ?? this.type,
        target: target ?? this.target,
        action: action ?? this.action,
        options: options ?? this.options,
      );

  Map<String, dynamic> toJson() => {
        'raw': raw,
        'type': type,
        if (target != null) 'target': target,
        'action': action,
        if (options != null) 'options': options,
      };

  factory ModuleRule.fromJson(Map<String, dynamic> j) => ModuleRule(
        raw: j['raw'] as String,
        type: j['type'] as String,
        target: j['target'] as String?,
        action: j['action'] as String,
        options: j['options'] as String?,
      );
}

// ── UrlRewriteRule ────────────────────────────────────────────────────────────

class UrlRewriteRule {
  final String pattern;
  final String? replacement;
  final String rewriteType;
  final String raw;

  const UrlRewriteRule({
    required this.pattern,
    this.replacement,
    required this.rewriteType,
    required this.raw,
  });

  UrlRewriteRule copyWith({
    String? pattern,
    String? replacement,
    String? rewriteType,
    String? raw,
  }) =>
      UrlRewriteRule(
        pattern: pattern ?? this.pattern,
        replacement: replacement ?? this.replacement,
        rewriteType: rewriteType ?? this.rewriteType,
        raw: raw ?? this.raw,
      );

  Map<String, dynamic> toJson() => {
        'pattern': pattern,
        if (replacement != null) 'replacement': replacement,
        'rewriteType': rewriteType,
        'raw': raw,
      };

  factory UrlRewriteRule.fromJson(Map<String, dynamic> j) => UrlRewriteRule(
        pattern: j['pattern'] as String,
        replacement: j['replacement'] as String?,
        rewriteType: j['rewriteType'] as String,
        raw: j['raw'] as String,
      );
}

// ── HeaderRewriteRule ─────────────────────────────────────────────────────────

class HeaderRewriteRule {
  final String pattern;
  final String headerAction;
  final String? headerName;
  final String? headerValue;
  final String raw;

  const HeaderRewriteRule({
    required this.pattern,
    required this.headerAction,
    this.headerName,
    this.headerValue,
    required this.raw,
  });

  HeaderRewriteRule copyWith({
    String? pattern,
    String? headerAction,
    String? headerName,
    String? headerValue,
    String? raw,
  }) =>
      HeaderRewriteRule(
        pattern: pattern ?? this.pattern,
        headerAction: headerAction ?? this.headerAction,
        headerName: headerName ?? this.headerName,
        headerValue: headerValue ?? this.headerValue,
        raw: raw ?? this.raw,
      );

  Map<String, dynamic> toJson() => {
        'pattern': pattern,
        'headerAction': headerAction,
        if (headerName != null) 'headerName': headerName,
        if (headerValue != null) 'headerValue': headerValue,
        'raw': raw,
      };

  factory HeaderRewriteRule.fromJson(Map<String, dynamic> j) =>
      HeaderRewriteRule(
        pattern: j['pattern'] as String,
        headerAction: j['headerAction'] as String,
        headerName: j['headerName'] as String?,
        headerValue: j['headerValue'] as String?,
        raw: j['raw'] as String,
      );
}

// ── ModuleScript ──────────────────────────────────────────────────────────────

class ModuleScript {
  final String name;
  final String scriptType;
  final String? pattern;
  final String scriptPath;
  /// Fetched JavaScript source for http-response scripts. Null until downloaded.
  final String? scriptContent;
  final bool requiresBody;
  final String? cronExpression;
  final String raw;

  const ModuleScript({
    required this.name,
    required this.scriptType,
    this.pattern,
    required this.scriptPath,
    this.scriptContent,
    required this.requiresBody,
    this.cronExpression,
    required this.raw,
  });

  ModuleScript copyWith({
    String? name,
    String? scriptType,
    String? pattern,
    String? scriptPath,
    Object? scriptContent = _sentinel,
    bool? requiresBody,
    String? cronExpression,
    String? raw,
  }) =>
      ModuleScript(
        name: name ?? this.name,
        scriptType: scriptType ?? this.scriptType,
        pattern: pattern ?? this.pattern,
        scriptPath: scriptPath ?? this.scriptPath,
        scriptContent: scriptContent == _sentinel
            ? this.scriptContent
            : scriptContent as String?,
        requiresBody: requiresBody ?? this.requiresBody,
        cronExpression: cronExpression ?? this.cronExpression,
        raw: raw ?? this.raw,
      );

  static const _sentinel = Object();

  Map<String, dynamic> toJson() => {
        'name': name,
        'scriptType': scriptType,
        if (pattern != null) 'pattern': pattern,
        'scriptPath': scriptPath,
        if (scriptContent != null) 'scriptContent': scriptContent,
        'requiresBody': requiresBody,
        if (cronExpression != null) 'cronExpression': cronExpression,
        'raw': raw,
      };

  factory ModuleScript.fromJson(Map<String, dynamic> j) => ModuleScript(
        name: j['name'] as String,
        scriptType: j['scriptType'] as String,
        pattern: j['pattern'] as String?,
        scriptPath: j['scriptPath'] as String,
        scriptContent: j['scriptContent'] as String?,
        requiresBody: j['requiresBody'] as bool? ?? false,
        cronExpression: j['cronExpression'] as String?,
        raw: j['raw'] as String,
      );
}

// ── MapLocalRule ──────────────────────────────────────────────────────────────

class MapLocalRule {
  final String pattern;
  final String dataUrl;
  final String raw;

  const MapLocalRule({
    required this.pattern,
    required this.dataUrl,
    required this.raw,
  });

  MapLocalRule copyWith({
    String? pattern,
    String? dataUrl,
    String? raw,
  }) =>
      MapLocalRule(
        pattern: pattern ?? this.pattern,
        dataUrl: dataUrl ?? this.dataUrl,
        raw: raw ?? this.raw,
      );

  Map<String, dynamic> toJson() => {
        'pattern': pattern,
        'dataUrl': dataUrl,
        'raw': raw,
      };

  factory MapLocalRule.fromJson(Map<String, dynamic> j) => MapLocalRule(
        pattern: j['pattern'] as String,
        dataUrl: j['dataUrl'] as String,
        raw: j['raw'] as String,
      );
}

// ── UnsupportedCounts ─────────────────────────────────────────────────────────

class UnsupportedCounts {
  final int mitmCount;
  final int urlRewriteCount;
  final int headerRewriteCount;
  final int scriptCount;
  final int mapLocalCount;
  final int panelCount;

  const UnsupportedCounts({
    this.mitmCount = 0,
    this.urlRewriteCount = 0,
    this.headerRewriteCount = 0,
    this.scriptCount = 0,
    this.mapLocalCount = 0,
    this.panelCount = 0,
  });

  int get total =>
      mitmCount +
      urlRewriteCount +
      headerRewriteCount +
      scriptCount +
      mapLocalCount +
      panelCount;

  bool get hasUnsupported => total > 0;

  UnsupportedCounts copyWith({
    int? mitmCount,
    int? urlRewriteCount,
    int? headerRewriteCount,
    int? scriptCount,
    int? mapLocalCount,
    int? panelCount,
  }) =>
      UnsupportedCounts(
        mitmCount: mitmCount ?? this.mitmCount,
        urlRewriteCount: urlRewriteCount ?? this.urlRewriteCount,
        headerRewriteCount: headerRewriteCount ?? this.headerRewriteCount,
        scriptCount: scriptCount ?? this.scriptCount,
        mapLocalCount: mapLocalCount ?? this.mapLocalCount,
        panelCount: panelCount ?? this.panelCount,
      );

  Map<String, dynamic> toJson() => {
        'mitmCount': mitmCount,
        'urlRewriteCount': urlRewriteCount,
        'headerRewriteCount': headerRewriteCount,
        'scriptCount': scriptCount,
        'mapLocalCount': mapLocalCount,
        'panelCount': panelCount,
      };

  factory UnsupportedCounts.fromJson(Map<String, dynamic> j) =>
      UnsupportedCounts(
        mitmCount: j['mitmCount'] as int? ?? 0,
        urlRewriteCount: j['urlRewriteCount'] as int? ?? 0,
        headerRewriteCount: j['headerRewriteCount'] as int? ?? 0,
        scriptCount: j['scriptCount'] as int? ?? 0,
        mapLocalCount: j['mapLocalCount'] as int? ?? 0,
        panelCount: j['panelCount'] as int? ?? 0,
      );

  static const empty = UnsupportedCounts();
}

// ── ModuleRecord ──────────────────────────────────────────────────────────────

class ModuleRecord {
  final String id;
  final String name;
  final String desc;
  final String sourceUrl;
  final String originalContent;
  final String checksum;
  final bool enabled;
  final String? versionTag;
  final String? author;
  final String? iconUrl;
  final String? homepage;
  final String? category;

  // Parsed capabilities
  final List<ModuleRule> rules;
  final List<String> mitmHostnames;
  final List<UrlRewriteRule> urlRewrites;
  final List<HeaderRewriteRule> headerRewrites;
  final List<ModuleScript> scripts;
  final List<MapLocalRule> mapLocals;

  // Stats
  final UnsupportedCounts unsupportedCounts;
  final List<String> parseWarnings;

  // Timestamps
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastFetchedAt;
  final DateTime? lastAppliedAt;

  const ModuleRecord({
    required this.id,
    required this.name,
    required this.desc,
    required this.sourceUrl,
    required this.originalContent,
    required this.checksum,
    required this.enabled,
    this.versionTag,
    this.author,
    this.iconUrl,
    this.homepage,
    this.category,
    required this.rules,
    required this.mitmHostnames,
    required this.urlRewrites,
    required this.headerRewrites,
    required this.scripts,
    required this.mapLocals,
    required this.unsupportedCounts,
    required this.parseWarnings,
    required this.createdAt,
    required this.updatedAt,
    this.lastFetchedAt,
    this.lastAppliedAt,
  });

  ModuleRecord copyWith({
    String? id,
    String? name,
    String? desc,
    String? sourceUrl,
    String? originalContent,
    String? checksum,
    bool? enabled,
    Object? versionTag = _sentinel,
    Object? author = _sentinel,
    Object? iconUrl = _sentinel,
    Object? homepage = _sentinel,
    Object? category = _sentinel,
    List<ModuleRule>? rules,
    List<String>? mitmHostnames,
    List<UrlRewriteRule>? urlRewrites,
    List<HeaderRewriteRule>? headerRewrites,
    List<ModuleScript>? scripts,
    List<MapLocalRule>? mapLocals,
    UnsupportedCounts? unsupportedCounts,
    List<String>? parseWarnings,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? lastFetchedAt = _sentinel,
    Object? lastAppliedAt = _sentinel,
  }) =>
      ModuleRecord(
        id: id ?? this.id,
        name: name ?? this.name,
        desc: desc ?? this.desc,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        originalContent: originalContent ?? this.originalContent,
        checksum: checksum ?? this.checksum,
        enabled: enabled ?? this.enabled,
        versionTag: versionTag == _sentinel
            ? this.versionTag
            : versionTag as String?,
        author: author == _sentinel ? this.author : author as String?,
        iconUrl: iconUrl == _sentinel ? this.iconUrl : iconUrl as String?,
        homepage:
            homepage == _sentinel ? this.homepage : homepage as String?,
        category:
            category == _sentinel ? this.category : category as String?,
        rules: rules ?? this.rules,
        mitmHostnames: mitmHostnames ?? this.mitmHostnames,
        urlRewrites: urlRewrites ?? this.urlRewrites,
        headerRewrites: headerRewrites ?? this.headerRewrites,
        scripts: scripts ?? this.scripts,
        mapLocals: mapLocals ?? this.mapLocals,
        unsupportedCounts: unsupportedCounts ?? this.unsupportedCounts,
        parseWarnings: parseWarnings ?? this.parseWarnings,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastFetchedAt: lastFetchedAt == _sentinel
            ? this.lastFetchedAt
            : lastFetchedAt as DateTime?,
        lastAppliedAt: lastAppliedAt == _sentinel
            ? this.lastAppliedAt
            : lastAppliedAt as DateTime?,
      );

  static const _sentinel = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'desc': desc,
        'sourceUrl': sourceUrl,
        'originalContent': originalContent,
        'checksum': checksum,
        'enabled': enabled,
        if (versionTag != null) 'versionTag': versionTag,
        if (author != null) 'author': author,
        if (iconUrl != null) 'iconUrl': iconUrl,
        if (homepage != null) 'homepage': homepage,
        if (category != null) 'category': category,
        'rules': rules.map((r) => r.toJson()).toList(),
        'mitmHostnames': mitmHostnames,
        'urlRewrites': urlRewrites.map((r) => r.toJson()).toList(),
        'headerRewrites': headerRewrites.map((r) => r.toJson()).toList(),
        'scripts': scripts.map((s) => s.toJson()).toList(),
        'mapLocals': mapLocals.map((m) => m.toJson()).toList(),
        'unsupportedCounts': unsupportedCounts.toJson(),
        'parseWarnings': parseWarnings,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (lastFetchedAt != null)
          'lastFetchedAt': lastFetchedAt!.toIso8601String(),
        if (lastAppliedAt != null)
          'lastAppliedAt': lastAppliedAt!.toIso8601String(),
      };

  factory ModuleRecord.fromJson(Map<String, dynamic> j) => ModuleRecord(
        id: j['id'] as String,
        name: j['name'] as String,
        desc: j['desc'] as String? ?? '',
        sourceUrl: j['sourceUrl'] as String,
        originalContent: j['originalContent'] as String? ?? '',
        checksum: j['checksum'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? true,
        versionTag: j['versionTag'] as String?,
        author: j['author'] as String?,
        iconUrl: j['iconUrl'] as String?,
        homepage: j['homepage'] as String?,
        category: j['category'] as String?,
        rules: (j['rules'] as List<dynamic>? ?? [])
            .map((e) => ModuleRule.fromJson(e as Map<String, dynamic>))
            .toList(),
        mitmHostnames: (j['mitmHostnames'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        urlRewrites: (j['urlRewrites'] as List<dynamic>? ?? [])
            .map((e) => UrlRewriteRule.fromJson(e as Map<String, dynamic>))
            .toList(),
        headerRewrites: (j['headerRewrites'] as List<dynamic>? ?? [])
            .map((e) => HeaderRewriteRule.fromJson(e as Map<String, dynamic>))
            .toList(),
        scripts: (j['scripts'] as List<dynamic>? ?? [])
            .map((e) => ModuleScript.fromJson(e as Map<String, dynamic>))
            .toList(),
        mapLocals: (j['mapLocals'] as List<dynamic>? ?? [])
            .map((e) => MapLocalRule.fromJson(e as Map<String, dynamic>))
            .toList(),
        unsupportedCounts: j['unsupportedCounts'] != null
            ? UnsupportedCounts.fromJson(
                j['unsupportedCounts'] as Map<String, dynamic>)
            : UnsupportedCounts.empty,
        parseWarnings: (j['parseWarnings'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        lastFetchedAt: j['lastFetchedAt'] != null
            ? DateTime.parse(j['lastFetchedAt'] as String)
            : null,
        lastAppliedAt: j['lastAppliedAt'] != null
            ? DateTime.parse(j['lastAppliedAt'] as String)
            : null,
      );

  /// Encode to JSON string (for storage).
  String toJsonString() => jsonEncode(toJson());

  /// Decode from JSON string.
  factory ModuleRecord.fromJsonString(String s) =>
      ModuleRecord.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
