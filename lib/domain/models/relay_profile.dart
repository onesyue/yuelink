/// Source of a relay profile — only `commercial` is wired in Phase 1A.
/// The enum itself is forward-compatible for officialAccess / superPeer
/// so persisted JSON can carry the field before those paths ship.
enum RelaySource { commercial, officialAccess, superPeer }

/// How the relay is applied to subscription nodes.
///   - allVless:       every node whose `type == vless` is wrapped.
///   - allowlistNames: only nodes whose `name` appears in [RelayProfile.allowlistNames].
///
/// HY2 / hysteria2 nodes are intentionally out of scope for Phase 1A —
/// dialer-proxy + UDP-based transports is a separate validation track.
enum RelayTargetMode { allVless, allowlistNames }

/// Persistent description of a commercial dialer-proxy ("前置 relay").
///
/// A single relay wraps target nodes via mihomo's `dialer-proxy` field.
/// RelayInjector is responsible for materialising this into a
/// `_yue_relay` proxy node plus per-target dialer-proxy assignments.
class RelayProfile {
  final bool enabled;
  final RelaySource source;

  /// mihomo outbound type: `vless`, `trojan`, `hysteria2`, `socks5`, ...
  final String type;
  final String host;
  final int port;

  /// Protocol-specific fields merged verbatim into the generated proxy node
  /// (uuid, password, tls, servername, network, ws-opts, …). Unknown keys
  /// pass through untouched so new transports work without code changes.
  final Map<String, dynamic> extras;

  final RelayTargetMode targetMode;
  final List<String> allowlistNames;

  const RelayProfile({
    required this.enabled,
    this.source = RelaySource.commercial,
    required this.type,
    required this.host,
    required this.port,
    this.extras = const {},
    this.targetMode = RelayTargetMode.allVless,
    this.allowlistNames = const [],
  });

  const RelayProfile.disabled()
      : enabled = false,
        source = RelaySource.commercial,
        type = '',
        host = '',
        port = 0,
        extras = const {},
        targetMode = RelayTargetMode.allVless,
        allowlistNames = const [];

  /// A profile is "valid" only when Phase 1A can safely apply it.
  /// officialAccess / superPeer intentionally fail validation — they're
  /// placeholders for future phases and must not silently degrade to commercial.
  bool get isValid {
    if (!enabled) return false;
    if (source != RelaySource.commercial) return false;
    if (type.trim().isEmpty) return false;
    if (host.trim().isEmpty) return false;
    if (port <= 0 || port > 65535) return false;
    if (targetMode == RelayTargetMode.allowlistNames && allowlistNames.isEmpty) {
      return false;
    }
    return true;
  }

  /// Hosts that need fake-ip-filter / route-exclude bypass on iOS / TUN.
  /// Empty list when the profile is disabled or invalid — callers can
  /// forward this directly to ConfigTemplate without extra guards.
  List<String> get bypassHosts => isValid ? [host] : const [];

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'source': source.name,
        'type': type,
        'host': host,
        'port': port,
        'extras': extras,
        'targetMode': targetMode.name,
        'allowlistNames': allowlistNames,
      };

  factory RelayProfile.fromJson(Map<String, dynamic> json) {
    final sourceStr = json['source'] as String? ?? RelaySource.commercial.name;
    final source = RelaySource.values.firstWhere(
      (s) => s.name == sourceStr,
      orElse: () => RelaySource.commercial,
    );
    final modeStr =
        json['targetMode'] as String? ?? RelayTargetMode.allVless.name;
    final mode = RelayTargetMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => RelayTargetMode.allVless,
    );
    final extrasRaw = json['extras'];
    final extras = extrasRaw is Map
        ? Map<String, dynamic>.from(extrasRaw)
        : <String, dynamic>{};
    final namesRaw = json['allowlistNames'];
    final names = namesRaw is List
        ? namesRaw.whereType<String>().toList()
        : const <String>[];
    return RelayProfile(
      enabled: json['enabled'] as bool? ?? false,
      source: source,
      type: json['type'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      extras: extras,
      targetMode: mode,
      allowlistNames: names,
    );
  }
}
