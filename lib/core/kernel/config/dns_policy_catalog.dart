/// Single source of truth for DNS policy domain lists.
///
/// Both [DnsTransformer] (nameserver-policy / fake-ip-filter) and
/// [RulesTransformer] (Secure-DNS / ECH probe routing) read from this
/// catalog so the two transformers never drift out of sync. Tests can
/// reference these `const` lists directly without poking at private
/// transformer internals.
class DnsPolicyCatalog {
  const DnsPolicyCatalog._();

  // ── Overseas DoH endpoints (used as nameserver-policy values) ──────────
  /// Cloudflare + Google DoH on 443. `tls://...:853` is reliably blocked
  /// by the GFW (gfw.report USENIX'23 — TCP RST on 853); DoH on 443 blends
  /// with normal HTTPS and survives.
  static const overseasDohServers = <String>[
    'https://cloudflare-dns.com/dns-query',
    'https://dns.google/dns-query',
  ];

  // ── ECH / Secure-DNS probe domains ─────────────────────────────────────
  /// Domains browsers use for built-in DoH (Secure DNS) lookups and the
  /// Cloudflare ECH outer-SNI / config probe. All four DoH endpoints + the
  /// ECH probe must share the AI / cf-fronted exit IP — Cloudflare WAF
  /// correlates the outer-SNI probe with the subsequent inner TLS
  /// connection and challenges on mismatch.
  ///
  /// See `rules_transformer.dart` `ensureBrowserSecureDnsRules` for the
  /// "AI group has real unlock nodes" invariant that gates this routing.
  static const secureDnsDomains = <String>[
    'cloudflare-dns.com',
    'chrome.cloudflare-dns.com',
    'mozilla.cloudflare-dns.com',
    'dns.google',
    'cloudflare-ech.com',
  ];

  // ── AI domains routed to overseas DoH via nameserver-policy ────────────
  /// Explicit enumeration of AI / cf-fronted service domains that MUST
  /// resolve via [overseasDohServers]. Geosite-based catch-alls
  /// (`geosite:geolocation-!cn`) are still used as the safety net, but
  /// this explicit list immunises us against geosite database lag —
  /// when a new AI service launches, geosite typically takes 3–7 days to
  /// pick it up; in that window any unlisted AI domain falls back to CN
  /// DoH (AliDNS / 腾讯), leaking the user's AI-usage profile to CN DNS
  /// providers + breaking the service when CN DoH returns CN CDN IPs.
  ///
  /// Kept in sync with `assets/default_config.yaml` nameserver-policy.
  /// When adding a domain: add here, add to default_config, run the
  /// `catalog vs default_config` golden test.
  static const aiDomains = <String>[
    // OpenAI
    '+.openai.com',
    '+.cdn.openai.com',
    '+.chatgpt.com',
    '+.chat.openai.com',
    '+.operator.chatgpt.com',
    '+.oaistatic.com',
    '+.oaiusercontent.com',
    '+.sora.com',
    // Anthropic
    '+.anthropic.com',
    '+.claude.ai',
    '+.claude.site',
    '+.claudeusercontent.com',
    // Google AI
    '+.gemini.google.com',
    '+.bard.google.com',
    '+.notebooklm.google',
    '+.ai.google.dev',
    '+.aistudio.google.com',
    '+.generativelanguage.googleapis.com',
    '+.deepmind.google',
    '+.labs.google',
    // Microsoft / Bing
    '+.copilot.microsoft.com',
    '+.sydney.bing.com',
    // xAI / Meta
    '+.x.ai',
    '+.grok.com',
    '+.meta.ai',
    // Other LLM providers
    '+.perplexity.ai',
    '+.poe.com',
    '+.huggingface.co',
    '+.cohere.com',
    '+.mistral.ai',
    '+.together.ai',
    '+.groq.com',
    '+.fireworks.ai',
    '+.replicate.com',
    '+.openrouter.ai',
    '+.lmsys.org',
    // Code editors / agents
    '+.cursor.com',
    '+.cursor.sh',
    '+.codeium.com',
    '+.windsurf.com',
    '+.bolt.new',
    '+.v0.dev',
    '+.replit.com',
    '+.replit.dev',
    '+.vercel.ai',
    '+.devin.ai',
    '+.cognition.ai',
    '+.lovable.dev',
    // Image / video / voice
    '+.midjourney.com',
    '+.stability.ai',
    '+.runway.com',
    '+.runwayml.com',
    '+.suno.ai',
    '+.suno.com',
    '+.udio.com',
    '+.elevenlabs.io',
    '+.heygen.com',
    '+.synthesia.io',
    // Platforms / dev tools
    '+.dify.ai',
    '+.coze.com',
    '+.character.ai',
    '+.jasper.ai',
  ];

  // ── Connectivity-check domains (DOMAIN/DIRECT rules + fake-ip-filter) ──
  /// OEM connectivity-check probes. DIRECT in rules + fake-ip-filter in
  /// DNS so the system "internet OK" indicator stays green when proxy is
  /// up. Covers 13 OEM brands + carrier captive portals.
  ///
  /// `forFakeIpFilter` returns the broader set including LAN / NAS /
  /// router admin / NTP / STUN / games / Apple-ecosystem / IETF reserved.
  /// `forRules` returns only the OEM probe subset (most rule writers
  /// already let LAN/Apple DIRECT via geosite; injecting a hundred lines
  /// of duplicates would noisy up the rules section).
  static const connectivityDomains = <String>[
    'connectivitycheck.gstatic.com',
    'www.gstatic.com',
    '+.connectivitycheck.android.com',
    'clients1.google.com',
    'clients3.google.com',
    'clients4.google.com',
    'play.googleapis.com',
    'captive.apple.com',
    'gsp-ssl.ls.apple.com',
    'gsp-ssl.ls-apple.com.akadns.net',
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
    'www.msftconnecttest.com',
    'www.msftncsi.com',
    'dns.msftncsi.com',
  ];

  /// Subset of [connectivityDomains] used by `RulesTransformer` for the
  /// `DOMAIN,X,DIRECT` rule injection. Excludes Google/MS — most
  /// subscriptions already DIRECT them via `geosite:cn` carve-outs and
  /// mirroring would be noise.
  static List<String> rulesConnectivityDomains() {
    return connectivityDomains
        .where(
          (d) =>
              !d.contains('google') &&
              !d.contains('gstatic') &&
              !d.contains('msft'),
        )
        .toList(growable: false);
  }

  // ── China-critical domains (银行 / 运营商 / 企业内网 / IETF) ────────────
  /// Domestic services that break under fake-ip when subscription's
  /// nameserver-policy doesn't carve them out. Covers:
  ///   * carrier auth (cmpassport / wosms / 10086 / 10010 / 10099)
  ///   * banking (cmbchina / icbc / abchina / boc / ccb / bankcomm)
  ///   * insurance / fintech (pingan)
  ///   * travel / mobility (jegotrip / icitymobile)
  ///   * gaming auth (blzstatic — Battle.net China auth)
  ///   * enterprise intranet (microdone / id6 / mail.wo.cn)
  ///   * Active Directory (`PDC._msDCS.*` / `DC._msDCS.*` / `GC._msDCS.*`)
  ///
  /// New 2026-05 — added because OpenClash mainstream config carries
  /// these and yuelink users (Android 175 / Win 50 / mac 13 / iOS 5
  /// per platform priorities memo) report bank / 12306 / 移动认证
  /// failures while connected.
  static const chinaCriticalDomains = <String>[
    // 中国移动
    '+.cmpassport.com',
    '+.10086.cn',
    '+.wosms.cn',
    // 中国联通
    '+.10010.com',
    '+.10099.com.cn',
    'open.e.189.cn',
    'opencloud.wostore.cn',
    'id.mail.wo.cn',
    'mdn.open.wo.cn',
    'hmrz.wo.cn',
    'nishub1.10010.com',
    'enrichgw.10010.com',
    // 中国电信
    '+.189.cn',
    // 银行
    '+.cmbchina.com',
    '+.icbc.com.cn',
    '+.abchina.com',
    '+.boc.cn',
    '+.ccb.com',
    '+.bankcomm.com',
    '+.bocomcc.com',
    '+.cmbc.com.cn',
    '+.cgbchina.com.cn',
    // 保险 / 支付
    '+.pingan.com.cn',
    '+.alipay.com',
    '+.alipayobjects.com',
    // 出行 / 服务
    '+.jegotrip.com.cn',
    '+.icitymobile.mobi',
    '+.blzstatic.cn',
    // 企业 / 内网
    '+.microdone.cn',
    'id6.me',
    // Active Directory (企业内网)
    'PDC._msDCS.*.*',
    'DC._msDCS.*.*',
    'GC._msDCS.*.*',
  ];

  // ── CN DNS servers (used as nameserver-policy values for CN domains) ───
  static const cnDnsServers = <String>[
    'https://dns.alidns.com/dns-query',
    'https://doh.pub/dns-query',
  ];

  // ── nameserver-policy non-CN catch-all ─────────────────────────────────
  /// Catch-all for non-CN domains: routes them to foreign DoH so CN
  /// providers (AliDNS / TencentDNS) never see queries for foreign
  /// hostnames the user accesses. Without this, the default `nameserver`
  /// chain (CN DoH) is hit for any foreign domain not covered by a more-
  /// specific rule, leaking the user's full foreign-traffic profile to
  /// CN DNS providers.
  ///
  /// mihomo policy priority: specific suffix > geosite group, so the
  /// apple/icloud overrides still win over this.
  static const geolocationNonCnKey = 'geosite:geolocation-!cn';
  static const geositeCn = 'geosite:cn';
  static const geositePrivate = 'geosite:private';
}
