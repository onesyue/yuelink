import 'yaml_helpers.dart';
import 'yaml_indent_detector.dart';

class StaticSectionsTransformer {
  const StaticSectionsTransformer._();

  /// Force sniffer with override-destination: true for TLS/HTTP/QUIC.
  /// Always overwrite — subscription templates may have override-destination:
  /// false which breaks server-side audit rules.
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
        '    - "+.push.apple.com"\n';
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
