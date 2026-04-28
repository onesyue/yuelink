/// Represents a single proxy node.
///
/// Fully immutable — every field is final. Live delay-test results live in
/// `delayResultsProvider`, not on this model. Keeping the data class
/// immutable lets us define structural `==` / `hashCode` so Riverpod's
/// equality short-circuit reliably suppresses no-op rebuilds when the
/// `/proxies` response is unchanged round-to-round.
class ProxyNode {
  final String name;
  final String type; // ss, vmess, trojan, etc.
  final int? delay; // latency in ms, null = untested
  final bool alive;

  const ProxyNode({
    required this.name,
    required this.type,
    this.delay,
    this.alive = true,
  });

  factory ProxyNode.fromJson(Map<String, dynamic> json) {
    return ProxyNode(
      name: json['name'] as String,
      type: json['type'] as String,
      delay: json['delay'] as int?,
      alive: json['alive'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProxyNode &&
          name == other.name &&
          type == other.type &&
          delay == other.delay &&
          alive == other.alive;

  @override
  int get hashCode => Object.hash(name, type, delay, alive);
}

/// Represents a proxy group (Selector, URLTest, Fallback, etc.)
///
/// Fully immutable — see [ProxyNode] for the same rationale. `==` walks
/// the `all` list element-by-element so two groups with the same node
/// roster but different list instances compare equal, which is what
/// Riverpod needs to skip rebuilds.
class ProxyGroup {
  final String name;
  final String type; // Selector, URLTest, Fallback, LoadBalance
  final List<String> all; // all proxy names in this group
  final String now; // currently selected proxy name

  const ProxyGroup({
    required this.name,
    required this.type,
    required this.all,
    required this.now,
  });

  factory ProxyGroup.fromJson(Map<String, dynamic> json) {
    return ProxyGroup(
      name: json['name'] as String,
      type: json['type'] as String,
      all: (json['all'] as List?)?.cast<String>() ?? const [],
      now: json['now'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ProxyGroup) return false;
    if (name != other.name) return false;
    if (type != other.type) return false;
    if (now != other.now) return false;
    if (all.length != other.all.length) return false;
    for (var i = 0; i < all.length; i++) {
      if (all[i] != other.all[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, type, now, Object.hashAll(all));
}
