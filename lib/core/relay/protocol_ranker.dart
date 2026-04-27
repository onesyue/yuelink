/// Heuristic "how GFW-resistant is this transport" scoring.
///
/// Used by the selector as a *tie-break only* — never as a primary sort key.
/// Latency wins; rank decides ties.
///
/// Scoring is driven by `type + extras`, not `type` alone. The difference
/// between a naked VLESS and a VLESS wrapped in REALITY is the entire point.
///
/// Numbers reflect 2026 empirical consensus (gfw.report USENIX'23/'25,
/// S&P'25). They are not eternal truth — if a protocol gets cracked or a
/// new one gets validated, change [_rankTable]; nothing outside this file
/// should need updating.
class ProtocolRanker {
  ProtocolRanker._();

  /// Coarse tier used by telemetry. Never exports raw rank.
  static String tier(int rank) {
    if (rank >= 80) return 'high';
    if (rank >= 45) return 'medium';
    return 'low';
  }

  /// Rank the given transport. Higher is better.
  /// Unknown / malformed inputs return the neutral [_unknownRank].
  static int rank(String? type, Map<String, dynamic> extras) {
    final t = (type ?? '').trim().toLowerCase();
    if (t.isEmpty) return _unknownRank;

    final hasReality = _hasReality(extras);
    final hasTls = _hasTls(extras);

    switch (t) {
      case 'vless':
        if (hasReality) return 100;
        if (hasTls) return 70;
        return 50;
      case 'trojan':
        if (hasReality) return 95;
        if (hasTls) return 65;
        return 50;
      case 'anytls':
        return 60;
      case 'hysteria2':
      case 'hy2':
        return 55;
      case 'tuic':
        return 55;
      case 'vmess':
        return hasTls ? 45 : 40;
      case 'shadowsocks':
      case 'ss':
        return 30;
      case 'socks5':
      case 'http':
        return 20;
      default:
        return _unknownRank;
    }
  }

  static const _unknownRank = 50;

  static bool _hasReality(Map<String, dynamic> extras) {
    final v = extras['reality-opts'];
    if (v is Map && v.isNotEmpty) return true;
    // Some configs carry the flag under different keys; keep the parser
    // strict but allow the most common alternates so a subscription that
    // uses `reality: {...}` is still ranked correctly.
    final alt = extras['reality'];
    if (alt is Map && alt.isNotEmpty) return true;
    return false;
  }

  static bool _hasTls(Map<String, dynamic> extras) {
    final v = extras['tls'];
    return v == true;
  }
}
