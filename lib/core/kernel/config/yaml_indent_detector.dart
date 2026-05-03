/// String-range view of a top-level YAML section. Pure substring offsets;
/// no YAML parsing performed. Use [body] for indent detection or sub-key
/// search; use [start]..[end] for delete / replace / range-aware insert.
class YamlSectionRange {
  /// Index of the first character of the `key:` line in the source config.
  final int start;

  /// Index of the first character after the `key:\n` header line — where
  /// the body content begins. Equal to [end] when the section header has
  /// no body before the next top-level key.
  final int bodyStart;

  /// Index one past the last character of the section. Equal to the start
  /// of the next top-level key, or `config.length` at EOF.
  final int end;

  /// Convenience: `config.substring(bodyStart, end)`. Empty when the
  /// section has no body content.
  final String body;

  const YamlSectionRange({
    required this.start,
    required this.bodyStart,
    required this.end,
    required this.body,
  });
}

/// Centralised string-range / indent helpers for the `_ensureX` family in
/// `config_template.dart`. The functions here are deliberately narrow —
/// they only **read** structure, they do not insert or replace. Each
/// `_ensureX` call site keeps doing its own substring-concat write so the
/// insertion point is visible at the call.
///
/// All functions are stateless and operate on raw substrings; no YAML
/// parser is involved.
class YamlIndentDetector {
  const YamlIndentDetector._();

  /// Locate the top-level [key] block in [config]. Returns null when the
  /// key is not present at column 0.
  ///
  /// [topLevelCommentsEndSection] picks which "next top-level key"
  /// regex closes the section:
  ///   * `false` (default) — `^[^\s#]`: comments at column 0 are NOT
  ///     treated as section boundaries. Matches the historical
  ///     `_reTopLevel` behaviour used by `_disableTun`, `_ensureDns`,
  ///     `_ensureFakeIpForTun`, `_removeSection`,
  ///     `_appendRelayFakeIpFilter`.
  ///   * `true` — `^\S`: ANY non-whitespace at column 0 ends the
  ///     section, including a `# comment` line. Matches the historical
  ///     behaviour of `_injectProxyDirectInBlock`. The two callers
  ///     produce different bodies for configs that contain top-level
  ///     comments between sections, and that difference must be
  ///     preserved for byte-identical output.
  ///
  /// [requireBlockHeader] toggles between two header shapes:
  ///   * `false` (default) — `^key:`: matches the key regardless of
  ///     what follows. Inline forms like `rules: []` or `dns: false`
  ///     are accepted; the body is whatever lives below the first
  ///     newline. Matches the `_reDnsKey` / `_reTunKey` historical
  ///     shape used by `_disableTun`, `_ensureDns`,
  ///     `_ensureFakeIpForTun`, `_appendRelayFakeIpFilter`,
  ///     `_removeSection`.
  ///   * `true` — `^key:\s*\n`: only matches a block-style header
  ///     (key, optional trailing whitespace, then a newline). Inline
  ///     forms like `rules: []` are deliberately rejected so callers
  ///     don't blindly inject children into a flow-style empty list
  ///     and produce malformed YAML. Matches the rules-injector
  ///     family (`_ensureProcessBypassRules`, `_ensureConnectivityRules`,
  ///     `_ensureGooglevideoQuicReject`, `_ensureGlobalQuicReject`)
  ///     and `_injectProxyDirectInBlock`.
  static YamlSectionRange? findTopLevelSection(
    String config,
    String key, {
    bool topLevelCommentsEndSection = false,
    bool requireBlockHeader = false,
  }) {
    final keyPattern = requireBlockHeader
        ? RegExp('^${RegExp.escape(key)}:\\s*\\n', multiLine: true)
        : RegExp('^${RegExp.escape(key)}:', multiLine: true);
    final match = keyPattern.firstMatch(config);
    if (match == null) return null;

    // For block-header mode the pattern already consumed `\s*\n`, so
    // `match.end` IS the body start (and respects greedy consumption of
    // any blank lines between the header line and the first child).
    // For the lax form the pattern stops at `:`, so we walk to the next
    // newline ourselves — same behaviour as the historical
    // `config.indexOf('\n', match.start) + 1` pattern.
    final int bodyStart;
    if (requireBlockHeader) {
      bodyStart = match.end;
    } else {
      final newlineAfterHeader = config.indexOf('\n', match.start);
      bodyStart = newlineAfterHeader >= 0
          ? newlineAfterHeader + 1
          : config.length;
    }

    final boundaryPattern = topLevelCommentsEndSection
        ? RegExp(r'^\S', multiLine: true)
        : RegExp(r'^[^\s#]', multiLine: true);
    final tail = config.substring(bodyStart);
    final boundary = boundaryPattern.firstMatch(tail);
    final end = boundary != null ? bodyStart + boundary.start : config.length;

    return YamlSectionRange(
      start: match.start,
      bodyStart: bodyStart,
      end: end,
      body: config.substring(bodyStart, end),
    );
  }

  /// Detect the leading-space indent of the first non-blank child line in
  /// [body]. Returns [fallback] when [body] has no indented child line.
  ///
  /// `allowTabs: false` matches the historical `\n( +)\S` shape used at
  /// the three `_ensureDns` call sites — spaces only.
  /// `allowTabs: true` matches the `^([ \t]+)\S` shape used by
  /// `_injectProxyDirectInBlock` — spaces or tabs.
  ///
  /// Implementation note: the regex anchors to `^` with `multiLine: true`
  /// rather than the historical `\n(...)`, so the first character of
  /// [body] is itself eligible to start the indent. This is intentional:
  /// callers pass body-only strings (header already stripped via
  /// `YamlSectionRange.body`), so the very first line *is* the first
  /// child line and must not be skipped.
  static String detectChildIndent(
    String body, {
    String fallback = '  ',
    required bool allowTabs,
  }) {
    final pattern = allowTabs
        ? RegExp(r'^([ \t]+)\S', multiLine: true)
        : RegExp(r'^( +)\S', multiLine: true);
    final match = pattern.firstMatch(body);
    return match?.group(1) ?? fallback;
  }

  /// Detect the leading-whitespace indent of the first YAML list item
  /// (`- ...`) in [body]. Returns [fallback] when no list item is found.
  ///
  /// `allowTabs: false` matches the historical `\n( +)- ` shape used by
  /// the two `_ensureDns` / `_ensureFakeIpForTun` filter-list sites —
  /// one-or-more spaces, then `- ` (with mandatory trailing space).
  /// `allowTabs: true` matches `^([ \t]*)-\s` used by the three
  /// rules-list sites — zero-or-more spaces or tabs, then `-`, then any
  /// whitespace. The two regex shapes produce different captures on
  /// configs whose first list item is at column 0 or uses tab indent;
  /// the existing call sites depend on those differences.
  ///
  /// Same body-relative anchoring rationale as [detectChildIndent].
  static String detectListItemIndent(
    String body, {
    String fallback = '  ',
    required bool allowTabs,
  }) {
    final pattern = allowTabs
        ? RegExp(r'^([ \t]*)-\s', multiLine: true)
        : RegExp(r'^( +)- ', multiLine: true);
    final match = pattern.firstMatch(body);
    return match?.group(1) ?? fallback;
  }
}
