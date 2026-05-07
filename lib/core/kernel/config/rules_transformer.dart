import 'package:yaml/yaml.dart';

import 'dns_policy_catalog.dart';
import 'yaml_indent_detector.dart';

class RulesTransformer {
  const RulesTransformer._();

  /// Domains that browsers use for built-in DoH (Secure DNS) lookups
  /// and for the Cloudflare ECH outer-SNI / config probe. All four DoH
  /// endpoints + the ECH probe must share the AI / cf-fronted exit IP:
  ///
  /// - For ECH the IP-affinity requirement is hard — Cloudflare's WAF
  ///   correlates the outer-SNI probe with the subsequent inner TLS
  ///   connection and challenges on mismatch.
  /// - For DoH the IP-affinity requirement is soft but still preferred
  ///   — Chrome's anti-fingerprint fix shipped 2025 prefers the same
  ///   exit for the DoH probe and the cf-fronted TCP, otherwise
  ///   "Just a moment" challenges fire on chatgpt.com / claude.ai.
  ///
  /// Earlier (May 6) this list was split, with DoH routed to the
  /// generic main group and ECH alone on AI, on the theory that DoH
  /// resilience matters more than IP affinity. That regressed the
  /// v1.1.19 cf-fronted fix and was reverted once the server template
  /// was fixed to populate the AI group with actual unlock nodes
  /// (see docs/releases/v1.1.20.md). The right invariant
  /// is "AI group has real unlock nodes", not "DoH escapes from AI".
  ///
  /// Single source of truth is [DnsPolicyCatalog.secureDnsDomains].
  /// Tests reference the catalog directly; this getter only exists for
  /// readable error messages in legacy code paths.
  static List<String> get _browserSecureDnsDomains =>
      DnsPolicyCatalog.secureDnsDomains;

  /// Sentinel comment marker for idempotency. Looking for a literal
  /// rule string (e.g. `DOMAIN-SUFFIX,cloudflare-dns.com,`) is too
  /// brittle — a subscription that already routes the domain to a
  /// different group on purpose would block the marker. The marker is
  /// only set by us, so re-process won't double-inject and a manual
  /// override stays untouched.
  static const _secureDnsMarker =
      '# yuelink:secure-dns-routing'; // do not translate

  /// Synthetic fallback proxy-group injected when both an AI-themed
  /// group and a generic main-select group are present in the
  /// subscription. DoH / ECH rules target this group instead of the AI
  /// group directly, so when the AI group's nodes are completely
  /// unreachable (e.g. all nodes were Cloudflare-WAF-blocklisted and
  /// the user has no AI-unlock plan), mihomo's fallback health-check
  /// auto-routes those domains to the main group — preserving Chrome
  /// SecureDNS / DoH for non-cf services like google.com / github.com
  /// even though cf-fronted services (chatgpt / claude) will still get
  /// challenged. This is a connectivity-tier fallback, not a
  /// reputation-tier one — the latter still depends on the server
  /// template populating AI with cf-friendly nodes.
  static const _secureDnsFallbackGroupName = '_YueLink_SecureDNS';

  /// Ensure connectivity-check domains are routed DIRECT in rules.
  ///
  /// Domain list is sourced from
  /// [DnsPolicyCatalog.rulesConnectivityDomains] which already excludes
  /// google/gstatic/msft (those typically resolve DIRECT via geosite:cn
  /// carve-outs in mainstream subscriptions, so injecting duplicates
  /// would just be rule-list noise).
  static String ensureConnectivityRules(String config) {
    final rulesRange = YamlIndentDetector.findTopLevelSection(
      config,
      'rules',
      requireBlockHeader: true,
    );
    if (rulesRange == null) return config;

    final domains = DnsPolicyCatalog.rulesConnectivityDomains();

    // Tail-scan semantics preserved per S4 Step 2 spec.
    final ruleIndent = YamlIndentDetector.detectListItemIndent(
      config.substring(rulesRange.bodyStart),
      allowTabs: true,
    );
    var injection = '';
    for (final d in domains) {
      // Strip wildcard prefix when checking for an existing rule —
      // catalog uses `+.connectivitycheck.android.com` for fake-ip-filter
      // form, but the rule injection writes the bare hostname.
      final bare = d.startsWith('+.') ? d.substring(2) : d;
      if (!config.contains('DOMAIN,$bare,')) {
        injection += '$ruleIndent- "DOMAIN,$bare,DIRECT"\n';
      }
    }
    if (injection.isEmpty) return config;

    return config.substring(0, rulesRange.bodyStart) +
        injection +
        config.substring(rulesRange.bodyStart);
  }

  /// Front-load browser DoH (Secure DNS) and Cloudflare ECH-probe
  /// domains onto the same proxy group as the user's main cf-fronted
  /// services (AI-themed group preferred). All five domains share an
  /// exit so Cloudflare WAF sees a consistent IP between the DNS probe
  /// and the actual TLS connection — without that consistency, ChatGPT
  /// / Claude / other cf-fronted endpoints serve a JS challenge or
  /// hard-block. This depends on the AI group containing real unlock
  /// nodes (see server template `xboard-templates/clashmeta.yaml` —
  /// the `悦 · AI 解锁聚合` sub-group health-checked against
  /// `chrome.cloudflare-dns.com/cdn-cgi/trace`). If the AI group is
  /// stuffed with general-IDC nodes (Cloudflare WAF blocklist), the
  /// route works but every cf-fronted call gets challenged. The fix
  /// for that lives at the server-template layer, not here.
  ///
  /// Target group is auto-detected. AI-themed selects win first;
  /// otherwise we land on the typical front-page select group; failing
  /// both, this is a no-op (subscription too unusual to guess safely —
  /// users can override via OverwriteService).
  static String ensureBrowserSecureDnsRules(String config) {
    if (config.contains(_secureDnsMarker)) return config;

    final picks = pickAiAndMainProxyGroup(config);
    final ai = picks.ai;
    final main = picks.main;

    // Decide rule target.
    //   - both groups present → inject _YueLink_SecureDNS fallback
    //     group, route DoH/ECH there
    //   - only one group present → preserve legacy single-target
    //     behaviour (no synthetic group needed)
    //   - neither → no-op (subscription too unusual to guess)
    String? target;
    var injectFallback = false;
    final aiSafe = ai != null && _isSafeRuleTarget(ai);
    final mainSafe = main != null && _isSafeRuleTarget(main);
    if (aiSafe && mainSafe) {
      target = _secureDnsFallbackGroupName;
      injectFallback = true;
    } else if (aiSafe) {
      target = ai;
    } else if (mainSafe) {
      target = main;
    }
    if (target == null) return config;

    var working = config;
    if (injectFallback) {
      final after = _ensureSecureDnsFallbackGroup(working, ai!, main!);
      if (after == working) {
        // Couldn't append the synthetic group (no proxy-groups block,
        // already exists with mismatched name, etc.) — degrade to
        // routing DoH directly to the AI group.
        target = ai;
        injectFallback = false;
      } else {
        working = after;
      }
    }

    final rulesRange = YamlIndentDetector.findTopLevelSection(
      working,
      'rules',
      requireBlockHeader: true,
    );
    if (rulesRange == null) return config;

    final rulesBody = working.substring(rulesRange.bodyStart);
    final ruleIndent = YamlIndentDetector.detectListItemIndent(
      rulesBody,
      allowTabs: true,
    );

    final injection = StringBuffer()
      ..write('$ruleIndent$_secureDnsMarker -> $target\n');
    for (final domain in _browserSecureDnsDomains) {
      injection.write('$ruleIndent- "DOMAIN-SUFFIX,$domain,$target"\n');
    }

    return working.substring(0, rulesRange.bodyStart) +
        injection.toString() +
        working.substring(rulesRange.bodyStart);
  }

  /// Append the synthetic [_secureDnsFallbackGroupName] fallback group
  /// to the end of `proxy-groups`. Idempotent: if a group with that
  /// name already exists, returns [config] unchanged. Returns [config]
  /// unchanged when there is no `proxy-groups:` block-style header to
  /// extend.
  static String _ensureSecureDnsFallbackGroup(
    String config,
    String aiName,
    String mainName,
  ) {
    if (config.contains('name: $_secureDnsFallbackGroupName') ||
        config.contains('name: "$_secureDnsFallbackGroupName"') ||
        config.contains("name: '$_secureDnsFallbackGroupName'")) {
      return config;
    }

    final pgRange = YamlIndentDetector.findTopLevelSection(
      config,
      'proxy-groups',
      requireBlockHeader: true,
    );
    if (pgRange == null) return config;

    final body = config.substring(pgRange.bodyStart, pgRange.end);
    final itemIndent = YamlIndentDetector.detectListItemIndent(
      body,
      allowTabs: true,
    );
    final keyIndent = '$itemIndent  ';

    // Group names may contain emoji / CJK / spaces — wrap in
    // double-quotes so YAML's plain-scalar parser doesn't choke. We've
    // already filtered out names containing `,` or `"` upstream via
    // _isSafeRuleTarget, so the quoting is collision-free.
    final entry = StringBuffer()
      ..write('$itemIndent- name: "$_secureDnsFallbackGroupName"\n')
      ..write('${keyIndent}type: fallback\n')
      ..write('${keyIndent}proxies:\n')
      ..write('$keyIndent  - "$aiName"\n')
      ..write('$keyIndent  - "$mainName"\n')
      // generate_204 is a connectivity probe, not a cf-reputation
      // probe — fallback flips to `mainName` when AI nodes are dead
      // (no network), not when AI nodes are alive but cf-blacklisted.
      // The latter is the server-side template's responsibility.
      ..write('${keyIndent}url: "http://www.gstatic.com/generate_204"\n')
      ..write('${keyIndent}interval: 300\n');

    // pgRange.end sits at the start of the next top-level key (or
    // EOF). Splicing in front of it preserves the document's trailing
    // sections without disturbing their indent.
    return config.substring(0, pgRange.end) +
        entry.toString() +
        config.substring(pgRange.end);
  }

  /// Heuristic group selector exposed for testing. AI-themed groups win
  /// over generic main-select groups; both win over no-op.
  static String? pickPrimaryProxyGroup(String config) {
    final r = pickAiAndMainProxyGroup(config);
    return r.ai ?? r.main;
  }

  /// Same scan as [pickPrimaryProxyGroup] but returns both classifier
  /// hits separately so callers (e.g. the SecureDNS fallback group
  /// builder) can decide whether to compose them. Either field may be
  /// null when the corresponding category is absent or all candidates
  /// failed the [_isSafeRuleTarget] filter.
  static ({String? ai, String? main}) pickAiAndMainProxyGroup(String config) {
    final groups = _extractProxyGroups(config);
    if (groups.isEmpty) return (ai: null, main: null);

    String? bestAi;
    String? bestGeneric;

    // AI keywords need word-ish boundaries because raw `name.contains('AI')`
    // matches `DAILY`, `MAINSTREAM`, etc. Latin-only boundary check
    // (`(?:^|[^A-Za-z])AI(?:[^A-Za-z]|$)`) lets mixed-script names like
    // `🇺🇸 美国 AI 解锁` and `AI-Premium` win without false-matching
    // `Daily`. ChatGPT/OpenAI/Claude/Gemini are unique enough as raw
    // substrings — case-insensitive so `chatgpt-premium` etc still wins.
    final aiBoundaryRe = RegExp(
      r'(?:^|[^A-Za-z])(?:AI|ChatGPT|OpenAI|Claude|Gemini)(?:[^A-Za-z]|$)',
      caseSensitive: false,
    );
    // Generic main-select keywords: case-insensitive boundary match for
    // ASCII words so `PROXY` / `Proxy` / `Auto` / `AUTO` all hit; plain
    // contains for CJK/emoji where the cluster has no neighbouring
    // letters anyway.
    final genericLatinRe = RegExp(
      r'(?:^|[^A-Za-z])(?:GLOBAL|PROXY|AUTO)(?:[^A-Za-z]|$)',
      caseSensitive: false,
    );
    const cjkKeywords = ['节点选择', '🚀', '手动切换', '自动选择', '全部节点'];

    for (final g in groups) {
      final name = g['name'];
      if (name is! String) continue;
      if (name.startsWith('_YueLink_Chain_')) continue;
      if (!_isSafeRuleTarget(name)) continue;
      if (bestAi == null && aiBoundaryRe.hasMatch(name)) bestAi = name;
      if (bestGeneric == null) {
        if (genericLatinRe.hasMatch(name) || cjkKeywords.any(name.contains)) {
          bestGeneric = name;
        }
      }
    }

    return (ai: bestAi, main: bestGeneric);
  }

  /// Parse `proxy-groups` and return each entry as a Dart map. Returns
  /// an empty list on malformed YAML — caller should treat that as
  /// "skip injection".
  static List<Map<String, dynamic>> _extractProxyGroups(String config) {
    try {
      final parsed = loadYaml(config);
      if (parsed is! YamlMap) return const [];
      final raw = parsed['proxy-groups'];
      if (raw is! YamlList) return const [];
      final result = <Map<String, dynamic>>[];
      for (final entry in raw) {
        if (entry is YamlMap) {
          result.add({
            for (final e in entry.entries) e.key.toString(): e.value,
          });
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// mihomo rule targets are comma-separated; embedded commas / quotes
  /// would break the rule line. Sane subscriptions don't use such
  /// names — when one slips in, refuse the injection silently.
  static bool _isSafeRuleTarget(String name) =>
      !name.contains(',') && !name.contains('"');

  /// Apply the configured QUIC fallback policy.
  static String ensureQuicReject(String config, String policy) {
    switch (policy) {
      case 'off':
        return config;
      case 'googlevideo':
        return _ensureGooglevideoQuicReject(config);
      case 'all':
        return _ensureGlobalQuicReject(config);
      default:
        return config;
    }
  }

  /// Reject UDP/QUIC to YouTube video CDN so clients fall back to TCP/HTTP/2.
  static String _ensureGooglevideoQuicReject(String config) {
    final rulesRange = YamlIndentDetector.findTopLevelSection(
      config,
      'rules',
      requireBlockHeader: true,
    );
    if (rulesRange == null) return config;

    final rulesBody = config.substring(rulesRange.bodyStart);
    final alreadyHandled = RegExp(
      r'googlevideo\.com[^\n]*REJECT',
      caseSensitive: false,
    ).hasMatch(rulesBody);
    if (alreadyHandled || _hasGlobalUdp443Reject(rulesBody)) return config;

    final ruleIndent = YamlIndentDetector.detectListItemIndent(
      rulesBody,
      allowTabs: true,
    );

    final injection =
        '$ruleIndent- "AND,((DOMAIN-SUFFIX,googlevideo.com),(NETWORK,UDP)),REJECT-DROP"\n';

    return config.substring(0, rulesRange.bodyStart) +
        injection +
        config.substring(rulesRange.bodyStart);
  }

  /// Reject QUIC (all UDP/443) so apps fall back to TCP/TLS.
  static String _ensureGlobalQuicReject(String config) {
    final rulesRange = YamlIndentDetector.findTopLevelSection(
      config,
      'rules',
      requireBlockHeader: true,
    );
    if (rulesRange == null) return config;

    final rulesBody = config.substring(rulesRange.bodyStart);
    if (_hasGlobalUdp443Reject(rulesBody)) return config;

    final ruleIndent = YamlIndentDetector.detectListItemIndent(
      rulesBody,
      allowTabs: true,
    );

    final injection =
        '$ruleIndent- "AND,((NETWORK,UDP),(DST-PORT,443)),REJECT-DROP"\n';

    return config.substring(0, rulesRange.bodyStart) +
        injection +
        config.substring(rulesRange.bodyStart);
  }

  static bool _hasGlobalUdp443Reject(String rulesBody) {
    return RegExp(
      r'AND,\(\(NETWORK,UDP\),\(DST-PORT,443\)\),REJECT'
      r'|AND,\(\(DST-PORT,443\),\(NETWORK,UDP\)\),REJECT',
      caseSensitive: false,
    ).hasMatch(rulesBody);
  }
}
