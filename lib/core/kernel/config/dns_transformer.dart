import 'yaml_helpers.dart';
import 'yaml_indent_detector.dart';

class DnsTransformer {
  const DnsTransformer._();

  static final _reEnableTrue = RegExp(r'\benable:\s*true');
  static final _reEnableFalse = RegExp(r'\benable:\s*false');

  /// Ensure DNS is enabled with comprehensive fake-ip + fallback config.
  static String ensureDns(
    String config, {
    List<String> relayHostWhitelist = const [],
  }) {
    if (!hasKey(config, 'dns')) {
      config =
          '$config\ndns:\n'
          '  enable: true\n'
          '  prefer-h3: true\n'
          // ARC cache (mihomo 1.18+) outperforms LRU on
          // proxy-client workloads where the same hot domains repeat
          // every few seconds amid a long tail of one-shot lookups —
          // 20-40% better hit rate in mihomo-party benchmarks. CVR /
          // FlClash / Party all default to arc.
          '  cache-algorithm: arc\n'
          // Honour /etc/hosts entries — desktop users who pin a host
          // locally expect it to take effect, regardless of fake-IP.
          '  use-system-hosts: true\n'
          '  enhanced-mode: fake-ip\n'
          '  fake-ip-range: 198.18.0.1/16\n'
          // Explicit blacklist mode: mihomo's default has been
          // blacklist for years but having it written down means a
          // future upstream flip can't silently change our routing.
          '  fake-ip-filter-mode: blacklist\n'
          '  fake-ip-filter:\n'
          // ── LAN / mDNS / IETF reserved ─────────────────────────
          '    - "+.lan"\n'
          '    - "+.local"\n'
          '    - "+.direct"\n'
          '    - "+.home"\n'
          '    - "+.home.arpa"\n'
          '    - "+.localdomain"\n'
          '    - "+.invalid"\n'
          '    - "+.localhost"\n'
          '    - "+.test"\n'
          '    - "+.in-addr.arpa"\n'
          '    - "+.ip6.arpa"\n'
          // ── Windows / NTP / STUN / games ───────────────────────
          '    - "+.msftconnecttest.com"\n'
          '    - "+.msftncsi.com"\n'
          '    - "localhost.ptlogin2.qq.com"\n'
          '    - "localhost.work.weixin.qq.com"\n'
          '    - "+.srv.nintendo.net"\n'
          '    - "+.stun.playstation.net"\n'
          '    - "+.xboxlive.com"\n'
          '    - "stun.*.*"\n'
          '    - "stun.*.*.*"\n'
          '    - "xbox.*.microsoft.com"\n'
          '    - "+.ntp.org"\n'
          '    - "+.pool.ntp.org"\n'
          '    - "+.time.edu.cn"\n'
          '    - "time.*.com"\n'
          '    - "time.*.gov"\n'
          // ── Apple ecosystem ────────────────────────────────────
          '    - "+.apple.com"\n'
          '    - "+.icloud.com"\n'
          '    - "+.cdn-apple.com"\n'
          '    - "+.mzstatic.com"\n'
          '    - "+.push.apple.com"\n'
          // ── Home router admin panels (CN-dominant brands) ──────
          '    - "tplogin.cn"\n'
          '    - "tplinklogin.net"\n'
          '    - "+.router.asus.com"\n'
          '    - "router.asus.com"\n'
          '    - "+.miwifi.com"\n'
          '    - "miwifi.com"\n'
          '    - "router.miwifi.com"\n'
          '    - "melogin.cn"\n'
          '    - "falogin.cn"\n'
          '    - "tendawifi.com"\n'
          '    - "routerlogin.net"\n'
          '    - "linksyssmartwifi.com"\n'
          '    - "dlinkrouter.local"\n'
          // ── NAS ────────────────────────────────────────────────
          '    - "+.synology.me"\n'
          '    - "+.quickconnect.to"\n'
          '    - "+.qnap.com"\n'
          '    - "+.myqnapcloud.com"\n'
          // ── Connectivity checks (no "internet" icon false-alarms) ──
          // Google / Android
          '    - "connectivitycheck.gstatic.com"\n'
          '    - "www.gstatic.com"\n'
          '    - "+.connectivitycheck.android.com"\n'
          '    - "clients1.google.com"\n'
          '    - "clients3.google.com"\n'
          '    - "play.googleapis.com"\n'
          // Apple captive portal
          '    - "captive.apple.com"\n'
          '    - "gsp-ssl.ls.apple.com"\n'
          '    - "gsp-ssl.ls-apple.com.akadns.net"\n'
          // Huawei
          '    - "connectivitycheck.platform.hicloud.com"\n'
          '    - "+.wifi.huawei.com"\n'
          // Samsung
          '    - "connectivitycheck.samsung.com"\n'
          // Xiaomi
          '    - "connect.rom.miui.com"\n'
          '    - "connectivitycheck.platform.xiaomi.com"\n'
          // OPPO / Realme / ColorOS
          '    - "conn1.coloros.com"\n'
          '    - "conn2.coloros.com"\n'
          // Honor
          '    - "connectivitycheck.platform.hihonorcloud.com"\n'
          // Meizu
          '    - "connectivitycheck.meizu.com"\n'
          // Vivo / other
          '    - "wifi.vivo.com.cn"\n'
          '    - "noisyfox.cn"\n'
          '  default-nameserver:\n'
          '    - 223.5.5.5\n'
          '    - 119.29.29.29\n'
          '    - 1.12.12.12\n'
          // nameserver order: AliDNS first — it negotiates H3 properly
          // against `prefer-h3: true` (doh.pub advertises no h3 Alt-Svc
          // as of 2025 and silently falls back to H2).
          '  nameserver:\n'
          '    - https://dns.alidns.com/dns-query\n'
          '    - https://doh.pub/dns-query\n'
          '  direct-nameserver:\n'
          '    - https://dns.alidns.com/dns-query\n'
          '    - https://doh.pub/dns-query\n'
          // proxy-server-nameserver: plain-IP UDP first to break the
          // chicken-and-egg when the proxy isn't up yet.
          '  proxy-server-nameserver:\n'
          '    - 223.5.5.5\n'
          '    - 119.29.29.29\n'
          '    - 1.12.12.12\n'
          '    - https://dns.alidns.com/dns-query\n'
          '    - https://doh.pub/dns-query\n'
          '  nameserver-policy:\n'
          // Catch-all for non-CN domains: routes them to foreign DoH so
          // CN providers (AliDNS / TencentDNS) never see queries for
          // foreign hostnames the user accesses. Without this, the
          // default `nameserver` chain (CN DoH) is hit for any foreign
          // domain not covered by a more-specific rule, leaking the
          // user's full foreign-traffic profile to CN DNS providers.
          // mihomo policy priority: specific suffix > geosite group, so
          // the apple/icloud overrides below still win.
          '    "geosite:geolocation-!cn": ["https://cloudflare-dns.com/dns-query", "https://dns.google/dns-query"]\n'
          '    "+.apple.com": ["https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"]\n'
          '    "+.icloud.com": ["https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"]\n'
          // fallback: DoH only. `tls://...:853` is reliably blocked by
          // the GFW (gfw.report USENIX'23 — TCP RST on 853). DoH on 443
          // blends with normal HTTPS and survives. 0.0.0.0/32 + 240.0.0.0/4
          // ipcidr filter catches DNS-poisoning answers.
          '  fallback:\n'
          '    - "https://1.1.1.1/dns-query"\n'
          '    - "https://dns.google/dns-query"\n'
          '  fallback-filter:\n'
          '    geoip: true\n'
          '    geoip-code: CN\n'
          '    geosite:\n'
          '      - gfw\n'
          '    ipcidr:\n'
          '      - 240.0.0.0/4\n'
          '      - 0.0.0.0/32\n'
          '    domain:\n'
          '      - "+.google.com"\n'
          '      - "+.facebook.com"\n'
          '      - "+.youtube.com"\n'
          '      - "+.github.com"\n'
          '      - "+.googleapis.com"\n';
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

      if (!dnsSection.contains('nameserver-policy:')) {
        final policy =
            '$indent'
            'nameserver-policy:\n'
            '$entryIndent'
            '"geosite:geolocation-!cn": ["https://cloudflare-dns.com/dns-query", "https://dns.google/dns-query"]\n'
            '$entryIndent'
            '"+.apple.com": ["https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"]\n'
            '$entryIndent'
            '"+.icloud.com": ["https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"]\n';
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

      dnsSection = config.substring(range.start, dnsEnd);
      const connectivityDomains = [
        'connectivitycheck.gstatic.com',
        'www.gstatic.com',
        '+.connectivitycheck.android.com',
        'clients1.google.com',
        'clients3.google.com',
        'play.googleapis.com',
        'captive.apple.com',
        'gsp-ssl.ls.apple.com',
        'gsp-ssl.ls-apple.com.akadns.net',
        'www.msftconnecttest.com',
        'www.msftncsi.com',
        'dns.msftncsi.com',
        'connectivitycheck.platform.hicloud.com',
        '+.wifi.huawei.com',
        'connectivitycheck.samsung.com',
        'connect.rom.miui.com',
        'connectivitycheck.platform.xiaomi.com',
        'conn1.coloros.com',
        'conn2.coloros.com',
        'connectivitycheck.platform.hihonorcloud.com',
        'connectivitycheck.meizu.com',
        'wifi.vivo.com.cn',
        'noisyfox.cn',
        '+.home',
        '+.home.arpa',
        '+.localdomain',
        '+.invalid',
        '+.localhost',
        '+.test',
        '+.in-addr.arpa',
        '+.ip6.arpa',
        'tplogin.cn',
        'tplinklogin.net',
        '+.router.asus.com',
        'router.asus.com',
        '+.miwifi.com',
        'miwifi.com',
        'router.miwifi.com',
        'melogin.cn',
        'falogin.cn',
        'tendawifi.com',
        'routerlogin.net',
        'linksyssmartwifi.com',
        'dlinkrouter.local',
        '+.synology.me',
        '+.quickconnect.to',
        '+.qnap.com',
        '+.myqnapcloud.com',
        'stun.*.*',
        'stun.*.*.*',
        'xbox.*.microsoft.com',
        'time.*.com',
        'time.*.gov',
        'localhost.work.weixin.qq.com',
      ];
      if (dnsSection.contains('fake-ip-filter:')) {
        final filterMatch = RegExp(
          r'fake-ip-filter:\s*\n',
        ).firstMatch(dnsSection);
        if (filterMatch != null) {
          var insertOffset = range.start + filterMatch.end;
          final afterFilter = config.substring(insertOffset);
          final listEnd = RegExp(
            r'^(?![ \t]+- )',
            multiLine: true,
          ).firstMatch(afterFilter);
          if (listEnd != null) insertOffset += listEnd.start;
          final existingFilter = dnsSection;
          var injection = '';
          for (final domain in connectivityDomains) {
            if (!existingFilter.contains(domain)) {
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
            '${connectivityDomains.map((d) => '$entryIndent- "$d"').join('\n')}\n';
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

    final filterMatch = RegExp(r'fake-ip-filter:\s*\n').firstMatch(dnsSection);
    if (filterMatch == null) return config;

    final entryIndent = YamlIndentDetector.detectListItemIndent(
      bodyOf(dnsSection),
      fallback: '    ',
      allowTabs: false,
    );

    var injection = '';
    for (final h in hosts) {
      final trimmed = h.trim();
      if (trimmed.isEmpty) continue;
      if (dnsSection.contains('"$trimmed"') ||
          dnsSection.contains('- $trimmed\n')) {
        continue;
      }
      injection += '$entryIndent- "$trimmed"\n';
    }
    if (injection.isEmpty) return config;

    var insertOffset = range.start + filterMatch.end;
    final afterFilter = config.substring(insertOffset);
    final listEnd = RegExp(
      r'^(?![ \t]+- )',
      multiLine: true,
    ).firstMatch(afterFilter);
    if (listEnd != null) insertOffset += listEnd.start;

    return config.substring(0, insertOffset) +
        injection +
        config.substring(insertOffset);
  }
}
