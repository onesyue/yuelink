import 'yaml_indent_detector.dart';

class RulesTransformer {
  const RulesTransformer._();

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
