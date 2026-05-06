import 'yaml_helpers.dart';
import 'yaml_indent_detector.dart';

class StaticSectionsTransformer {
  const StaticSectionsTransformer._();

  /// Force sniffer with override-destination: true for TLS/HTTP/QUIC.
  /// Always overwrite — subscription templates may have override-destination:
  /// false which breaks server-side audit rules.
  ///
  /// **Deliberately NO `parse-pure-ip` / `force-dns-mapping`** even
  /// though both look like 2026-mainstream wins on paper. v1.0.21 P1-4
  /// (commit ccfae5e) measured a ~30% throughput regression with both
  /// flags on (32 MB/s → 20 MB/s on the same node) and removed them
  /// from both the runtime template and the fallback asset. CVR /
  /// mihomo-party also keep them off in their shipped defaults. Don't
  /// re-add without re-running the throughput benchmark from that
  /// commit's user report.
  static String ensureSniffer(String config) {
    config = _removeSection(config, 'sniffer');
    return '$config\nsniffer:\n'
        '  enable: true\n'
        '  override-destination: true\n'
        '  sniff:\n'
        '    HTTP:\n'
        '      ports: [80, 8080-8880]\n'
        '      override-destination: true\n'
        '    TLS:\n'
        '      ports: [443, 8443]\n'
        '      override-destination: true\n'
        '    QUIC:\n'
        '      ports: [443, 8443]\n'
        '      override-destination: true\n'
        '  force-domain:\n'
        '    - "+.v2ex.com"\n'
        '  skip-domain:\n'
        '    - "Mijia Cloud"\n'
        '    - "+.push.apple.com"\n'
        // Cloudflare ECH outer SNI: every cf-fronted site (ChatGPT,
        // Claude, GitHub, Discord, …) shares "cloudflare-ech.com" as the
        // outer SNI when the browser enables Encrypted Client Hello.
        // Without skip-domain, sniffer overrides metadata.host to
        // cloudflare-ech.com and routes every cf-backed connection to
        // whatever rule that bare domain matches (usually fallback) —
        // breaking ChatGPT/Claude on TUN whenever the browser has
        // Secure DNS / ECH on. Skipping makes mihomo fall back to the
        // fake-ip reverse-lookup hostname (the real business domain),
        // which already has the correct rule.
        '    - "cloudflare-ech.com"\n';
  }

  /// Ensure geodata settings so GEOIP/GEOSITE rules resolve correctly.
  static String ensureGeodata(String config) {
    if (!hasKey(config, 'geodata-mode')) {
      config += '\ngeodata-mode: true\n';
    }
    if (!hasKey(config, 'geodata-loader')) {
      config += 'geodata-loader: memconservative\n';
    }
    if (!hasKey(config, 'geo-auto-update')) {
      config += 'geo-auto-update: true\n';
    }
    if (!hasKey(config, 'geo-update-interval')) {
      config += 'geo-update-interval: 24\n';
    }
    if (!hasKey(config, 'geox-url')) {
      config +=
          'geox-url:\n'
          '  geoip: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"\n'
          '  geosite: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"\n'
          '  mmdb: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"\n';
    }
    return config;
  }

  /// Ensure profile persistence settings.
  static String ensureProfile(String config) {
    if (hasKey(config, 'profile')) return config;
    return '$config\nprofile:\n'
        '  store-selected: true\n'
        '  store-fake-ip: false\n';
  }

  /// `experimental` policy: do NOT inject defaults. Aligned with mihomo
  /// upstream (both `quic-go-disable-gso` and `quic-go-disable-ecn` default
  /// to `false`). If a subscription ships its own block, keep it.
  static String ensureExperimental(String config) {
    return config;
  }

  static String _removeSection(String config, String key) {
    final range = YamlIndentDetector.findTopLevelSection(config, key);
    if (range == null) return config;
    return config.substring(0, range.start) + config.substring(range.end);
  }
}
