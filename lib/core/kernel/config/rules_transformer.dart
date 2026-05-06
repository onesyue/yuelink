import 'package:yaml/yaml.dart';

import 'yaml_indent_detector.dart';

class RulesTransformer {
  const RulesTransformer._();

  /// Domains that browsers use for built-in DoH (Secure DNS) lookups
  /// and for the Cloudflare ECH outer-SNI / config probe. Listed in the
  /// order Chrome / Firefox / Safari try them so any common provider
  /// flips into the user's main proxy group.
  static const _browserSecureDnsDomains = [
    'cloudflare-dns.com',
    'chrome.cloudflare-dns.com',
    'mozilla.cloudflare-dns.com',
    'dns.google',
    'cloudflare-ech.com',
  ];

  /// Sentinel comment marker for idempotency. Looking for a literal
  /// rule string (e.g. `DOMAIN-SUFFIX,cloudflare-dns.com,`) is too
  /// brittle — a subscription that already routes the domain to a
  /// different group on purpose would block the marker. The marker is
  /// only set by us, so re-process won't double-inject and a manual
  /// override stays untouched.
  static const _secureDnsMarker =
      '# yuelink:secure-dns-routing'; // do not translate

  /// Ensure connectivity-check domains are routed DIRECT in rules.
  static String ensureConnectivityRules(String config) {
    final rulesRange = YamlIndentDetector.findTopLevelSection(
      config,
      'rules',
      requireBlockHeader: true,
    );
    if (rulesRange == null) return config;

    const domains = [
      'connectivitycheck.gstatic.com',
      'connectivitycheck.android.com',
      'clients3.google.com',
      'connectivitycheck.platform.hicloud.com',
      'connectivitycheck.samsung.com',
      'connect.rom.miui.com',
      'connectivitycheck.platform.xiaomi.com',
      'conn1.coloros.com',
      'conn2.coloros.com',
      'connectivitycheck.platform.hihonorcloud.com',
      'connectivitycheck.meizu.com',
      'wifi.vivo.com.cn',
      'captive.apple.com',
      'www.msftconnecttest.com',
    ];

    // Tail-scan semantics preserved per S4 Step 2 spec.
    final ruleIndent = YamlIndentDetector.detectListItemIndent(
      config.substring(rulesRange.bodyStart),
      allowTabs: true,
    );
    var injection = '';
    for (final d in domains) {
      if (d.contains('google') || d.contains('gstatic') || d.contains('msft')) {
        continue;
      }
      if (!config.contains('DOMAIN,$d,')) {
        injection += '$ruleIndent- "DOMAIN,$d,DIRECT"\n';
      }
    }
    if (injection.isEmpty) return config;

    return config.substring(0, rulesRange.bodyStart) +
        injection +
        config.substring(rulesRange.bodyStart);
  }

  /// Front-load browser DoH (Secure DNS) and Cloudflare ECH-probe
  /// domains onto the same proxy group as the user's main cf-fronted
  /// services. Without this, Chrome/Firefox bypass mihomo's DNS by
  /// fetching `cloudflare-dns.com` directly: that lookup falls into the
  /// catch-all rule of the subscription, often a different region than
  /// the main service exit. Cloudflare then sees the DoH probe and the
  /// real connection coming from two countries and serves a JS challenge
  /// or hard-blocks (this surfaced as "ChatGPT/Claude won't load on TUN
  /// while system-proxy works" — system-proxy disables Chrome Secure DNS
  /// automatically, hiding the bug).
  ///
  /// Pairs with `cloudflare-ech.com` in the sniffer skip-domain list:
  /// the sniffer side stops outer-SNI overriding fake-ip routing for the
  /// real TLS connection; this side ensures the DoH and ECH-config
  /// fetches all share an exit with the user's primary proxy group.
  ///
  /// Target group is auto-detected. AI-themed selects win first so
  /// cf-fronted AI services keep the same exit as their DoH probes;
  /// otherwise we land on the typical front-page select group; failing
  /// both, this is a no-op (subscription too unusual to guess safely —
  /// users can override via OverwriteService).
  static String ensureBrowserSecureDnsRules(String config) {
    if (config.contains(_secureDnsMarker)) return config;

    final groupName = pickPrimaryProxyGroup(config);
    if (groupName == null) return config;

    final rulesRange = YamlIndentDetector.findTopLevelSection(
      config,
      'rules',
      requireBlockHeader: true,
    );
    if (rulesRange == null) return config;

    final rulesBody = config.substring(rulesRange.bodyStart);
    final ruleIndent = YamlIndentDetector.detectListItemIndent(
      rulesBody,
      allowTabs: true,
    );

    if (!_isSafeRuleTarget(groupName)) return config;
    final injection = StringBuffer()
      ..write('$ruleIndent$_secureDnsMarker -> $groupName\n');
    for (final domain in _browserSecureDnsDomains) {
      injection.write('$ruleIndent- "DOMAIN-SUFFIX,$domain,$groupName"\n');
    }

    return config.substring(0, rulesRange.bodyStart) +
        injection.toString() +
        config.substring(rulesRange.bodyStart);
  }

  /// Heuristic group selector exposed for testing. AI-themed groups win
  /// over generic main-select groups; both win over no-op.
  static String? pickPrimaryProxyGroup(String config) {
    final groups = _extractProxyGroups(config);
    if (groups.isEmpty) return null;

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
      // Skip our own internal chain wrapper groups.
      if (name.startsWith('_YueLink_Chain_')) continue;
      // Skip names we can't safely embed in a rule line.
      if (!_isSafeRuleTarget(name)) continue;
      if (bestAi == null && aiBoundaryRe.hasMatch(name)) bestAi = name;
      if (bestGeneric == null) {
        if (genericLatinRe.hasMatch(name) ||
            cjkKeywords.any(name.contains)) {
          bestGeneric = name;
        }
      }
    }

    return bestAi ?? bestGeneric;
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
