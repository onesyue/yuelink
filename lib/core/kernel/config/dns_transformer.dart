import 'dns_policy_catalog.dart';
import 'yaml_helpers.dart';
import 'yaml_indent_detector.dart';

class DnsTransformer {
  const DnsTransformer._();

  static final _reEnableTrue = RegExp(r'\benable:\s*true');
  static final _reEnableFalse = RegExp(r'\benable:\s*false');

  /// Match a single fake-ip-filter list entry for [domain], tolerant of
  /// quoting variants (`- foo`, `- "foo"`, `- 'foo'`) and surrounding
  /// whitespace + optional inline comment.
  static RegExp _filterEntryRegex(String domain) {
    return RegExp(
      // ignore: prefer_adjacent_string_concatenation
      r'''^[ \t]*-\s+["']?''' +
          RegExp.escape(domain) +
          r'''["']?\s*(?:#.*)?$''',
      multiLine: true,
    );
  }

  /// Locate the body of the `fake-ip-filter` subsection within [slice]
  /// (typically the dns section body). Returns null when no
  /// `fake-ip-filter:` header is present.
  ///
  /// Subsection ends at the first line that is NOT a list item, comment,
  /// or blank line — i.e. the next sibling key under dns
  /// (`default-nameserver:` etc.) or EOF. Bounds are relative to [slice].
  ///
  /// `assets/default_config.yaml` uses `# ── tier ──` dividers inside
  /// fake-ip-filter; an earlier `^(?![ \t]+- )` boundary regex would
  /// truncate the subsection at the first comment, marking everything
  /// after as "outside fake-ip-filter" and causing duplicate inject on
  /// the next ensureDns() pass. Comments and blank lines are valid
  /// continuations of a YAML block sequence and must NOT terminate it.
  static ({int start, int end})? _findFakeIpFilterSubrange(String slice) {
    final filterMatch = RegExp(r'fake-ip-filter:\s*\n').firstMatch(slice);
    if (filterMatch == null) return null;
    final start = filterMatch.end;
    final tail = slice.substring(start);
    final boundaryMatch =
        RegExp(r'^(?![ \t]*(?:$|#|- ))', multiLine: true).firstMatch(tail);
    final end =
        boundaryMatch != null ? start + boundaryMatch.start : slice.length;
    return (start: start, end: end);
  }

  /// `true` when [domain] already appears as a list entry inside the
  /// fake-ip-filter subsection at [filterBody]. **Subsection-scoped** —
  /// guards against false positives where the same domain shows up as a
  /// `nameserver-policy` key elsewhere in the dns section (e.g.
  /// `geosite:cn:` under nameserver-policy was matching a naive
  /// `dnsSection.contains('geosite:cn')` and silently skipping the
  /// fake-ip-filter inject — see governance/client-comparison-deep-dive
  /// 2026-05-07 §3 P1-2a).
  static bool _filterContains(String filterBody, String domain) {
    return _filterEntryRegex(domain).hasMatch(filterBody);
  }

  /// `true` when [domain] already appears as a YAML mapping key inside
  /// [dnsSection] (typical use: nameserver-policy entries). Tolerates
  /// quoted (`"+.openai.com": …`), single-quoted (`'+.openai.com': …`),
  /// and bare (`+.openai.com: …`) forms in both **block** style
  /// (start-of-line) and **flow** style (after `{` or `,`).
  ///
  /// Anchored to either start-of-line or a flow-style separator so a
  /// list entry (`- "+.openai.com"`, no trailing colon) cannot
  /// false-match.
  static bool _hasPolicyKey(String dnsSection, String domain) {
    return RegExp(
      // ignore: prefer_adjacent_string_concatenation
      r'''(?:^|[,{])[ \t]*["']?''' +
          RegExp.escape(domain) +
          r'''["']?[ \t]*:''',
      multiLine: true,
    ).hasMatch(dnsSection);
  }

  /// Test-only accessor for [_hasPolicyKey]. Named with `debug` prefix
  /// to signal it's not part of the production API; production callers
  /// should use the private `_hasPolicyKey` directly.
  static bool debugHasPolicyKey(String dnsSection, String domain) =>
      _hasPolicyKey(dnsSection, domain);

  /// Catalog-aware list of domains that must end up in fake-ip-filter
  /// when the subscription doesn't ship its own. Order: LAN/IETF →
  /// Win/NTP/STUN/games → Apple → router/NAS → connectivity (catalog)
  /// → CN-critical (catalog) → `geosite:cn` catch-all last.
  static List<String> get _freshFakeIpFilterDomains => <String>[
        // LAN / mDNS / IETF reserved
        '+.lan', '+.local', '+.direct', '+.home', '+.home.arpa',
        '+.localdomain', '+.invalid', '+.localhost', '+.test',
        '+.in-addr.arpa', '+.ip6.arpa',
        // Windows / NTP / STUN / games
        '+.msftconnecttest.com', '+.msftncsi.com',
        'localhost.ptlogin2.qq.com', 'localhost.work.weixin.qq.com',
        '+.srv.nintendo.net', '+.stun.playstation.net', '+.xboxlive.com',
        'stun.*.*', 'stun.*.*.*', 'xbox.*.microsoft.com',
        '+.ntp.org', '+.pool.ntp.org', '+.time.edu.cn',
        'time.*.com', 'time.*.gov',
        // Apple ecosystem
        '+.apple.com', '+.icloud.com', '+.cdn-apple.com',
        '+.mzstatic.com', '+.push.apple.com',
        // Home routers (CN-dominant brands)
        'tplogin.cn', 'tplinklogin.net',
        '+.router.asus.com', 'router.asus.com',
        '+.miwifi.com', 'miwifi.com', 'router.miwifi.com',
        'melogin.cn', 'falogin.cn', 'tendawifi.com',
        'routerlogin.net', 'linksyssmartwifi.com', 'dlinkrouter.local',
        // NAS
        '+.synology.me', '+.quickconnect.to',
        '+.qnap.com', '+.myqnapcloud.com',
        // OEM connectivity (catalog single-source)
        ...DnsPolicyCatalog.connectivityDomains,
        // CN-critical services (P1-4: 银行/运营商/企业内网/AD)
        ...DnsPolicyCatalog.chinaCriticalDomains,
        // geosite catch-all (P1-2b: belt-and-suspenders for CN domains
        // a subscription's nameserver-policy doesn't carve out)
        DnsPolicyCatalog.geositeCn,
      ];

  /// Build the YAML literal for a list of DoH/IP servers used as a
  /// `nameserver-policy` value. mihomo accepts both block-style and
  /// flow-style lists; flow style keeps the policy table compact.
  static String _flowList(List<String> values) {
    return '[${values.map((v) => '"$v"').join(', ')}]';
  }

  /// Inject a fresh dns section when the subscription doesn't ship one.
  ///
  /// All domain content sourced from [DnsPolicyCatalog] so this stays
  /// in lock-step with `assets/default_config.yaml` and the rules
  /// transformer's Secure-DNS routing.
  static String _injectFreshDnsSection(String config) {
    final overseasFlow = _flowList(DnsPolicyCatalog.overseasDohServers);
    final cnFlow = _flowList(DnsPolicyCatalog.cnDnsServers);

    final buf = StringBuffer(config)
      ..write('\ndns:\n')
      ..write('  enable: true\n')
      ..write('  prefer-h3: true\n')
      // ARC cache (mihomo 1.18+) outperforms LRU on proxy-client
      // workloads — 20-40% better hit rate vs LRU per mihomo-party
      // benchmarks. CVR / FlClash / Party all default to arc.
      ..write('  cache-algorithm: arc\n')
      // Honour /etc/hosts entries — desktop users who pin a host
      // locally expect it to take effect, regardless of fake-IP.
      ..write('  use-system-hosts: true\n')
      ..write('  enhanced-mode: fake-ip\n')
      ..write('  fake-ip-range: 198.18.0.1/16\n')
      // Explicit blacklist mode: defensive against future upstream flips.
      ..write('  fake-ip-filter-mode: blacklist\n')
      ..write('  fake-ip-filter:\n');
    for (final domain in _freshFakeIpFilterDomains) {
      buf.write('    - "$domain"\n');
    }

    buf
      ..write('  default-nameserver:\n')
      ..write('    - 223.5.5.5\n')
      ..write('    - 119.29.29.29\n')
      ..write('    - 1.12.12.12\n')
      // nameserver order: AliDNS first — it negotiates H3 properly
      // against `prefer-h3: true` (doh.pub advertises no h3 Alt-Svc
      // as of 2025 and silently falls back to H2).
      ..write('  nameserver:\n')
      ..write('    - https://dns.alidns.com/dns-query\n')
      ..write('    - https://doh.pub/dns-query\n')
      ..write('  direct-nameserver:\n')
      ..write('    - https://dns.alidns.com/dns-query\n')
      ..write('    - https://doh.pub/dns-query\n')
      // P1-3: mihomo 1.18+ — DIRECT flows obey nameserver-policy too,
      // so corporate intranet `+.corp.example` -> private DNS works
      // without leaking to alidns/doh.pub.
      ..write('  direct-nameserver-follow-policy: true\n')
      // proxy-server-nameserver: plain-IP UDP first to break the
      // chicken-and-egg when the proxy isn't up yet.
      ..write('  proxy-server-nameserver:\n')
      ..write('    - 223.5.5.5\n')
      ..write('    - 119.29.29.29\n')
      ..write('    - 1.12.12.12\n')
      ..write('    - https://dns.alidns.com/dns-query\n')
      ..write('    - https://doh.pub/dns-query\n')
      ..write('  nameserver-policy:\n')
      // Catch-all for non-CN: routes to foreign DoH so CN providers
      // (AliDNS / TencentDNS) never see foreign-hostname queries.
      // mihomo policy priority: specific suffix > geosite group, so the
      // explicit AI / Apple / iCloud entries below still win.
      ..write('    "${DnsPolicyCatalog.geolocationNonCnKey}": $overseasFlow\n')
      // CN tier: explicit cn / private to CN DoH.
      ..write('    "${DnsPolicyCatalog.geositeCn}": $cnFlow\n')
      ..write('    "${DnsPolicyCatalog.geositePrivate}": $cnFlow\n')
      // Apple / iCloud — keep on CN DoH so push / iMessage / iCloud
      // pick the geographically-closest Apple edge.
      ..write('    "+.apple.com": $cnFlow\n')
      ..write('    "+.icloud.com": $cnFlow\n');
    // P1-1: explicit AI domain enumeration so we're not at the mercy
    // of geosite database lag (3-7 day publishing cycle).
    for (final ai in DnsPolicyCatalog.aiDomains) {
      buf.write('    "$ai": $overseasFlow\n');
    }

    buf
      // fallback: DoH only. `tls://...:853` is reliably blocked by the
      // GFW (gfw.report USENIX'23). DoH on 443 blends with HTTPS.
      // 0.0.0.0/32 + 240.0.0.0/4 ipcidr filter catches DNS-poisoning.
      ..write('  fallback:\n')
      ..write('    - "https://1.1.1.1/dns-query"\n')
      ..write('    - "https://dns.google/dns-query"\n')
      ..write('  fallback-filter:\n')
      ..write('    geoip: true\n')
      ..write('    geoip-code: CN\n')
      ..write('    geosite:\n')
      ..write('      - gfw\n')
      ..write('    ipcidr:\n')
      ..write('      - 240.0.0.0/4\n')
      ..write('      - 0.0.0.0/32\n')
      ..write('    domain:\n')
      ..write('      - "+.google.com"\n')
      ..write('      - "+.facebook.com"\n')
      ..write('      - "+.youtube.com"\n')
      ..write('      - "+.github.com"\n')
      ..write('      - "+.googleapis.com"\n');

    return buf.toString();
  }

  /// Ensure DNS is enabled with comprehensive fake-ip + fallback config.
  static String ensureDns(
    String config, {
    List<String> relayHostWhitelist = const [],
  }) {
    if (!hasKey(config, 'dns')) {
      config = _injectFreshDnsSection(config);
      return _appendRelayFakeIpFilter(config, relayHostWhitelist);
    }

    final range = YamlIndentDetector.findTopLevelSection(config, 'dns');
    if (range == null) return config;

    var afterDns = range.bodyStart;
    var dnsEnd = range.end;
    var dnsSection = config.substring(range.start, dnsEnd);

    if (_reEnableFalse.hasMatch(dnsSection)) {
      final newSection = dnsSection.replaceFirst(
        _reEnableFalse,
        'enable: true',
      );
      config =
          config.substring(0, range.start) +
          newSection +
          config.substring(dnsEnd);
      dnsEnd += newSection.length - dnsSection.length;
      dnsSection = newSection;
    } else if (!_reEnableTrue.hasMatch(dnsSection)) {
      const injection = '  enable: true\n';
      config =
          config.substring(0, afterDns) +
          injection +
          config.substring(afterDns);
      dnsEnd += injection.length;
      afterDns += injection.length;
      dnsSection = config.substring(range.start, dnsEnd);
    }

    final dnsBodyForIndent = bodyOf(dnsSection);
    final detectedIndent = YamlIndentDetector.detectChildIndent(
      dnsBodyForIndent,
      fallback: '',
      allowTabs: false,
    );
    if (detectedIndent.isNotEmpty) {
      final indent = detectedIndent;
      final entryIndent = YamlIndentDetector.detectListItemIndent(
        dnsBodyForIndent,
        fallback: '$indent  ',
        allowTabs: false,
      );
      final respectRulesEnabled = RegExp(
        r'respect-rules:\s*true\b',
      ).hasMatch(dnsSection);

      if (!respectRulesEnabled && !dnsSection.contains('prefer-h3')) {
        final injection = '${indent}prefer-h3: true\n';
        config =
            config.substring(0, afterDns) +
            injection +
            config.substring(afterDns);
        dnsEnd += injection.length;
        afterDns += injection.length;
        dnsSection = config.substring(range.start, dnsEnd);
      } else if (respectRulesEnabled) {
        dnsSection = dnsSection.replaceFirst(
          RegExp(r'\n\s*prefer-h3:\s*true\s*\n'),
          '\n',
        );
        config =
            config.substring(0, range.start) +
            dnsSection +
            config.substring(dnsEnd);
        dnsEnd = range.start + dnsSection.length;
      }

      // 2026 main-line additions: ARC cache + use-system-hosts +
      // explicit fake-ip-filter-mode. Inject only when missing so a
      // subscription that ships its own (e.g. lru / blacklist) wins.
      if (!dnsSection.contains('cache-algorithm:')) {
        final injection = '${indent}cache-algorithm: arc\n';
        config =
            config.substring(0, dnsEnd) + injection + config.substring(dnsEnd);
        dnsEnd += injection.length;
        dnsSection = config.substring(range.start, dnsEnd);
      }
      if (!dnsSection.contains('use-system-hosts:')) {
        final injection = '${indent}use-system-hosts: true\n';
        config =
            config.substring(0, dnsEnd) + injection + config.substring(dnsEnd);
        dnsEnd += injection.length;
        dnsSection = config.substring(range.start, dnsEnd);
      }
      if (!dnsSection.contains('fake-ip-filter-mode:')) {
        final injection = '${indent}fake-ip-filter-mode: blacklist\n';
        config =
            config.substring(0, dnsEnd) + injection + config.substring(dnsEnd);
        dnsEnd += injection.length;
        dnsSection = config.substring(range.start, dnsEnd);
      }

      // ── nameserver-policy: ensure section + catch-all + AI domains ──
      // Three sub-paths:
      //   (a) No nameserver-policy at all → inject section with
      //       catch-all + apple/icloud + every catalog AI domain.
      //   (b) Subscription has its own policy but no
      //       `geosite:geolocation-!cn` catch-all → splice catch-all in.
      //   (c) Policy exists (whether ours or subscription's) → for
      //       every AI domain in the catalog, inject if not present
      //       as a key. P1-1: subscription-shipped policies almost
      //       never enumerate the full AI domain list, and relying on
      //       geosite:geolocation-!cn alone leaves a 3-7 day window
      //       (geosite database lag) where new AI services leak to CN
      //       DoH. Catalog enumeration immunises against that lag.
      final overseasFlow = _flowList(DnsPolicyCatalog.overseasDohServers);
      final cnFlow = _flowList(DnsPolicyCatalog.cnDnsServers);

      if (!dnsSection.contains('nameserver-policy:')) {
        final policyBuf = StringBuffer()
          ..write('${indent}nameserver-policy:\n')
          ..write(
            '$entryIndent"${DnsPolicyCatalog.geolocationNonCnKey}": '
            '$overseasFlow\n',
          )
          ..write('$entryIndent"${DnsPolicyCatalog.geositeCn}": $cnFlow\n')
          ..write(
            '$entryIndent"${DnsPolicyCatalog.geositePrivate}": $cnFlow\n',
          )
          ..write('$entryIndent"+.apple.com": $cnFlow\n')
          ..write('$entryIndent"+.icloud.com": $cnFlow\n');
        for (final ai in DnsPolicyCatalog.aiDomains) {
          policyBuf.write('$entryIndent"$ai": $overseasFlow\n');
        }
        final policy = policyBuf.toString();
        config =
            config.substring(0, dnsEnd) + policy + config.substring(dnsEnd);
        dnsEnd += policy.length;
        dnsSection = config.substring(range.start, dnsEnd);
      } else if (!dnsSection.contains('geosite:geolocation-!cn')) {
        // Subscription already shipped its own nameserver-policy but it
        // doesn't cover non-CN domains as a catch-all. Splice the
        // geolocation-!cn rule in so CN DoH stops seeing foreign-domain
        // lookups. Handles both flow style (`policy: { 'a': [...] }`)
        // and block style (`policy:` + indented children).
        final flowMatch = RegExp(
          r'nameserver-policy:\s*\{',
        ).firstMatch(dnsSection);
        if (flowMatch != null) {
          final insertOffset = range.start + flowMatch.end;
          const entry =
              " 'geosite:geolocation-!cn': ['https://cloudflare-dns.com/dns-query', 'https://dns.google/dns-query'],";
          config =
              config.substring(0, insertOffset) +
              entry +
              config.substring(insertOffset);
          dnsEnd += entry.length;
          dnsSection = config.substring(range.start, dnsEnd);
        } else {
          final blockMatch = RegExp(
            r'nameserver-policy:[ \t]*\n',
          ).firstMatch(dnsSection);
          if (blockMatch != null) {
            final insertOffset = range.start + blockMatch.end;
            // Detect child indent by peeking at the next non-empty line
            // under nameserver-policy. Subscriptions in the wild use 2,
            // 4 or 6 spaces — never trust a fixed value.
            final remainder = config.substring(insertOffset);
            final childIndentMatch = RegExp(
              r'^([ \t]+)\S',
            ).firstMatch(remainder);
            final childIndent = childIndentMatch?.group(1) ?? entryIndent;
            final entry =
                '$childIndent'
                '"geosite:geolocation-!cn":\n'
                '$childIndent'
                '- https://cloudflare-dns.com/dns-query\n'
                '$childIndent'
                '- https://dns.google/dns-query\n';
            config =
                config.substring(0, insertOffset) +
                entry +
                config.substring(insertOffset);
            dnsEnd += entry.length;
            dnsSection = config.substring(range.start, dnsEnd);
          }
        }
      }

      // (c) Ensure every catalog AI domain is a policy key. Runs after
      // (a)/(b) so a freshly-injected policy from (a) is correctly
      // detected as "already covered" and we don't double-inject.
      dnsSection = config.substring(range.start, dnsEnd);
      final missingAiKeys = DnsPolicyCatalog.aiDomains
          .where((d) => !_hasPolicyKey(dnsSection, d))
          .toList(growable: false);
      if (missingAiKeys.isNotEmpty) {
        final flowMatch = RegExp(
          r'nameserver-policy:\s*\{',
        ).firstMatch(dnsSection);
        if (flowMatch != null) {
          // Flow style — insert each missing key as `'key': [...], `
          // immediately after the opening brace. mihomo accepts
          // trailing commas in flow mappings.
          final insertOffset = range.start + flowMatch.end;
          final buf = StringBuffer();
          for (final ai in missingAiKeys) {
            buf.write(
              " '$ai': "
              "['${DnsPolicyCatalog.overseasDohServers.join("', '")}'],",
            );
          }
          final entries = buf.toString();
          config =
              config.substring(0, insertOffset) +
              entries +
              config.substring(insertOffset);
          dnsEnd += entries.length;
          dnsSection = config.substring(range.start, dnsEnd);
        } else {
          final blockMatch = RegExp(
            r'nameserver-policy:[ \t]*\n',
          ).firstMatch(dnsSection);
          if (blockMatch != null) {
            final insertOffset = range.start + blockMatch.end;
            final remainder = config.substring(insertOffset);
            final childIndentMatch = RegExp(
              r'^([ \t]+)\S',
            ).firstMatch(remainder);
            final childIndent = childIndentMatch?.group(1) ?? entryIndent;
            final buf = StringBuffer();
            for (final ai in missingAiKeys) {
              buf.write('$childIndent"$ai": $overseasFlow\n');
            }
            final entries = buf.toString();
            config =
                config.substring(0, insertOffset) +
                entries +
                config.substring(insertOffset);
            dnsEnd += entries.length;
            dnsSection = config.substring(range.start, dnsEnd);
          }
        }
      }

      if (!dnsSection.contains('direct-nameserver:')) {
        final directNs =
            '$indent'
            'direct-nameserver:\n'
            '$entryIndent'
            '- https://dns.alidns.com/dns-query\n'
            '$entryIndent'
            '- https://doh.pub/dns-query\n';
        config =
            config.substring(0, dnsEnd) + directNs + config.substring(dnsEnd);
        dnsEnd += directNs.length;
        dnsSection = config.substring(range.start, dnsEnd);
      }

      if (!dnsSection.contains('proxy-server-nameserver:')) {
        final proxyNs =
            '${indent}proxy-server-nameserver:\n'
            '$entryIndent- 223.5.5.5\n'
            '$entryIndent- 119.29.29.29\n'
            '$entryIndent- 1.12.12.12\n'
            '$entryIndent- https://dns.alidns.com/dns-query\n'
            '$entryIndent- https://doh.pub/dns-query\n';
        config =
            config.substring(0, dnsEnd) + proxyNs + config.substring(dnsEnd);
        dnsEnd += proxyNs.length;
        dnsSection = config.substring(range.start, dnsEnd);
      }

      // P1-3: mihomo 1.18+ — DIRECT flows obey nameserver-policy too,
      // not just the `direct-nameserver` chain. Without this, a user-
      // defined `+.corp.example.com -> 192.168.1.53` policy is ignored
      // for DIRECT-routed connections and the intranet domain leaks to
      // alidns/doh.pub. Inject only when missing so a subscription that
      // explicitly sets `false` keeps its choice.
      if (!dnsSection.contains('direct-nameserver-follow-policy:')) {
        final injection =
            '${indent}direct-nameserver-follow-policy: true\n';
        config =
            config.substring(0, dnsEnd) + injection + config.substring(dnsEnd);
        dnsEnd += injection.length;
        dnsSection = config.substring(range.start, dnsEnd);
      }

      // ── fake-ip-filter sync ────────────────────────────────────────
      // Single source of truth: catalog. Three tiers in priority:
      //   1. Connectivity probes (OEM 13 brands)  — keeps "internet OK"
      //      icon green when the proxy is up.
      //   2. CN-critical (P1-4)                   — bank / 运营商 /
      //      enterprise intranet / AD that break under fake-ip when
      //      subscription's nameserver-policy doesn't carve them out.
      //   3. `geosite:cn` catch-all (P1-2b)       — belt-and-suspenders.
      //
      // Plus historical extras (LAN/IETF/router/NAS/STUN/games) that
      // pre-date the catalog; kept inline for now.
      const inlineExtras = <String>[
        '+.home', '+.home.arpa', '+.localdomain', '+.invalid',
        '+.localhost', '+.test', '+.in-addr.arpa', '+.ip6.arpa',
        'tplogin.cn', 'tplinklogin.net',
        '+.router.asus.com', 'router.asus.com',
        '+.miwifi.com', 'miwifi.com', 'router.miwifi.com',
        'melogin.cn', 'falogin.cn', 'tendawifi.com',
        'routerlogin.net', 'linksyssmartwifi.com', 'dlinkrouter.local',
        '+.synology.me', '+.quickconnect.to',
        '+.qnap.com', '+.myqnapcloud.com',
        'stun.*.*', 'stun.*.*.*', 'xbox.*.microsoft.com',
        'time.*.com', 'time.*.gov',
        'localhost.work.weixin.qq.com',
      ];
      final wantedDomains = <String>[
        ...DnsPolicyCatalog.connectivityDomains,
        ...inlineExtras,
        ...DnsPolicyCatalog.chinaCriticalDomains,
        DnsPolicyCatalog.geositeCn,
      ];

      dnsSection = config.substring(range.start, dnsEnd);
      if (dnsSection.contains('fake-ip-filter:')) {
        // P1-2a: dedup against the fake-ip-filter SUBSECTION only, not
        // the entire dns section. Pre-fix this used `dnsSection.contains
        // (domain)` which silently skipped `geosite:cn` / AI domains
        // because they appeared as `nameserver-policy` keys elsewhere
        // in the same dns section.
        final subrange = _findFakeIpFilterSubrange(dnsSection);
        if (subrange != null) {
          final filterBody =
              dnsSection.substring(subrange.start, subrange.end);
          final insertOffset = range.start + subrange.end;
          var injection = '';
          for (final domain in wantedDomains) {
            if (!_filterContains(filterBody, domain)) {
              injection += '$entryIndent- "$domain"\n';
            }
          }
          if (injection.isNotEmpty) {
            config =
                config.substring(0, insertOffset) +
                injection +
                config.substring(insertOffset);
            dnsEnd += injection.length;
          }
        }
      } else {
        final filterBlock =
            '${indent}fake-ip-filter:\n'
            '${wantedDomains.map((d) => '$entryIndent- "$d"').join('\n')}\n';
        config =
            config.substring(0, dnsEnd) +
            filterBlock +
            config.substring(dnsEnd);
      }
    }

    return _appendRelayFakeIpFilter(config, relayHostWhitelist);
  }

  static String _appendRelayFakeIpFilter(String config, List<String> hosts) {
    if (hosts.isEmpty) return config;
    if (!hasKey(config, 'dns')) return config;

    final range = YamlIndentDetector.findTopLevelSection(config, 'dns');
    if (range == null) return config;
    final dnsSection = config.substring(range.start, range.end);

    // P1-2a: subsection-scoped lookup. Pre-fix this used
    // `dnsSection.contains('"$trimmed"')` which would match the same
    // host appearing as a `nameserver-policy` key (e.g. when relay
    // host equals an AI domain we ship a policy for).
    final subrange = _findFakeIpFilterSubrange(dnsSection);
    if (subrange == null) return config;
    final filterBody = dnsSection.substring(subrange.start, subrange.end);

    final entryIndent = YamlIndentDetector.detectListItemIndent(
      bodyOf(dnsSection),
      fallback: '    ',
      allowTabs: false,
    );

    var injection = '';
    for (final h in hosts) {
      final trimmed = h.trim();
      if (trimmed.isEmpty) continue;
      if (_filterContains(filterBody, trimmed)) continue;
      injection += '$entryIndent- "$trimmed"\n';
    }
    if (injection.isEmpty) return config;

    final insertOffset = range.start + subrange.end;
    return config.substring(0, insertOffset) +
        injection +
        config.substring(insertOffset);
  }
}
