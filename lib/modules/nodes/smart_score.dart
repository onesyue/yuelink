/// Pure scoring for the "Smart Recommend" node sort mode.
///
/// Behind the `smart_node_recommend` feature flag. The score is computed
/// locally from the latest delay-test snapshot — no server call, no
/// Riverpod dependency — so it stays unit-testable and deterministic.
///
/// Score model (0-100, higher = better):
///   - 100 start, linearly subtract normalized latency
///     (0ms → 100, 1500ms+ → 0)
///   - Failed test (delay <= 0): score 0 (a -30 penalty is moot once
///     latency is missing — we clamp to 0)
///   - No data (no entry in map): score 0
library;

/// Compute a 0-100 health score for a single node [name] given a snapshot
/// of delay results.
///
/// [delays] maps node name → latency in ms. Missing entries and
/// non-positive values (failed tests / timeouts) yield 0.
int smartNodeScore(String name, Map<String, int> delays) {
  final d = delays[name];
  if (d == null) return 0;
  if (d <= 0) return 0; // failed or never responded

  // Normalize: 0ms → 100, 1500ms+ → 0, linear in between.
  const maxLatency = 1500;
  if (d >= maxLatency) return 0;
  final score = 100 - ((d / maxLatency) * 100).round();
  if (score < 0) return 0;
  if (score > 100) return 100;
  return score;
}

/// Sort [nodes] descending by [smartNodeScore]. Stable for equal scores
/// (preserves original relative order).
List<String> sortBySmartScore(List<String> nodes, Map<String, int> delays) {
  final copy = List<String>.from(nodes);
  // Decorate-sort-undecorate to keep the sort stable.
  final decorated = <MapEntry<int, int>>[];
  for (var i = 0; i < copy.length; i++) {
    decorated.add(MapEntry(i, smartNodeScore(copy[i], delays)));
  }
  decorated.sort((a, b) {
    final cmp = b.value.compareTo(a.value); // desc
    if (cmp != 0) return cmp;
    return a.key.compareTo(b.key); // stable
  });
  return [for (final e in decorated) copy[e.key]];
}
