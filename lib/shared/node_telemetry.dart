import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

import 'telemetry.dart';

/// Per-node telemetry helper.
///
/// Computes a stable, non-reversible fingerprint for a proxy node so the
/// server can aggregate real-user metrics without ever receiving the
/// server IP / port / obfuscation parameters in plain text.
///
/// Fingerprint inputs capture "what makes the node connectable":
///   - hy2       : type, server, port, sni
///   - vless     : + flow, pubkey, short-id, ws path
///   - trojan/vmess: + ws path
/// Pure cosmetic changes (display name, tag) do NOT alter the fingerprint,
/// so node renames on the panel do not reset aggregated history.
///
/// IP rotation DOES change the fingerprint. The server-side identity layer
/// pins history across rotations via an fp→identity table so continuity is
/// preserved even when the panel cycles IPs.
class NodeTelemetry {
  NodeTelemetry._();

  static const _fpAlgorithmVersion = 1;

  /// In-memory `name → fp` map, populated on [recordInventory] so later
  /// URL-test / connect events can look up fingerprints by the string
  /// identifier mihomo uses. Lives only for the current process lifetime —
  /// the next subscription sync overwrites the entire map.
  static final Map<String, String> _nameToFp = {};
  static final Map<String, String> _nameToType = {};

  /// Lookup a fingerprint by mihomo node name. Returns null when the node
  /// wasn't part of the most-recent inventory (e.g. edge case during a
  /// live profile swap). Callers should guard on null and skip telemetry.
  static String? fpForName(String name) => _nameToFp[name];

  /// Lookup the protocol type for a node name (hy2 / vless / trojan / …).
  static String? typeForName(String name) => _nameToType[name];

  /// Compute the 16-hex fingerprint for a mihomo proxy entry.
  static String fingerprint(Map<String, dynamic> proxy) {
    String s(String key) {
      final v = proxy[key];
      return v == null ? '' : v.toString();
    }

    final type = s('type').toLowerCase();
    final parts = <String>[
      'v$_fpAlgorithmVersion',
      type,
      s('server'),
      s('port'),
    ];

    switch (type) {
      case 'hysteria2':
      case 'hy2':
        parts.addAll([s('sni'), s('password')]);
        break;
      case 'vless':
        parts.addAll([
          s('sni'),
          s('flow'),
          s('client-fingerprint'),
          proxy['reality-opts'] is Map
              ? (proxy['reality-opts'] as Map)['public-key']?.toString() ?? ''
              : '',
          proxy['reality-opts'] is Map
              ? (proxy['reality-opts'] as Map)['short-id']?.toString() ?? ''
              : '',
          proxy['ws-opts'] is Map
              ? (proxy['ws-opts'] as Map)['path']?.toString() ?? ''
              : '',
        ]);
        break;
      case 'trojan':
      case 'vmess':
        parts.addAll([
          s('sni'),
          proxy['ws-opts'] is Map
              ? (proxy['ws-opts'] as Map)['path']?.toString() ?? ''
              : '',
        ]);
        break;
      case 'ss':
      case 'shadowsocks':
        parts.add(s('cipher'));
        break;
    }

    final digest = sha1.convert(utf8.encode(parts.join('|')));
    return digest.toString().substring(0, 16);
  }

  /// Normalize a proxy into the inventory row schema — only fp + classifying
  /// metadata, never raw server/port/sni.
  static Map<String, dynamic> inventoryRow(Map<String, dynamic> proxy) {
    return {
      'fp': fingerprint(proxy),
      'type': (proxy['type'] ?? '').toString().toLowerCase(),
      'region': _guessRegion((proxy['name'] ?? '').toString()),
    };
  }

  /// Record the post-sync node catalog. Sent once per subscription update.
  /// Also rebuilds the in-process `name → fp` / `name → type` maps so
  /// [recordUrlTest] / [recordConnect] callers can pass just the node name.
  static void recordInventory(List<Map<String, dynamic>> proxies) {
    // Update in-memory maps even when telemetry is off — the UI layer
    // (smart-node sort, auto-fallback) may want to know fp/type for
    // reasons unrelated to uploading events.
    _nameToFp.clear();
    _nameToType.clear();
    for (final p in proxies) {
      final name = (p['name'] ?? '').toString();
      if (name.isEmpty) continue;
      _nameToFp[name] = fingerprint(p);
      _nameToType[name] = (p['type'] ?? '').toString().toLowerCase();
    }
    if (!Telemetry.isEnabled || proxies.isEmpty) return;
    final rows = proxies.map(inventoryRow).toList();
    final byType = <String, int>{};
    for (final r in rows) {
      final t = r['type'] as String? ?? '';
      byType[t] = (byType[t] ?? 0) + 1;
    }
    Telemetry.event(
      'node_inventory',
      props: {
        'count': rows.length,
        'hy2_count': byType['hysteria2'] ?? byType['hy2'] ?? 0,
        'vless_count': byType['vless'] ?? 0,
        'trojan_count': byType['trojan'] ?? 0,
        'vmess_count': byType['vmess'] ?? 0,
        'ss_count': byType['ss'] ?? byType['shadowsocks'] ?? 0,
        'fp_algo': _fpAlgorithmVersion,
        'nodes': rows,
      },
    );
  }

  /// Warm the in-process `name → fp` / `name → type` maps at startup so
  /// URL-test and smart-node features have lookups available before the
  /// user triggers a subscription sync.
  ///
  /// Idempotent: if the inventory cache is already populated, returns
  /// immediately. Otherwise invokes [loadActiveConfig] to fetch the active
  /// profile YAML, parses its `proxies:` list, and populates the maps.
  /// When [Telemetry] is opted in AND the cache was previously empty, also
  /// emits a `node_inventory` event.
  ///
  /// Never throws and never blocks — wrap the whole call in `unawaited(...)`
  /// at startup. On any failure we silently no-op.
  static Future<void> ensureInventoryLoaded({
    required Future<String?> Function() loadActiveConfig,
  }) async {
    try {
      if (_nameToFp.isNotEmpty) return;
      final yaml = await loadActiveConfig();
      if (yaml == null || yaml.isEmpty) return;
      final doc = loadYaml(yaml);
      if (doc is! Map) return;
      final rawProxies = doc['proxies'];
      if (rawProxies is! List) return;
      final proxies = <Map<String, dynamic>>[];
      for (final p in rawProxies) {
        if (p is Map) {
          proxies.add(
            Map<String, dynamic>.from(
              p.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        }
      }
      if (proxies.isEmpty) return;
      recordInventory(proxies);
    } catch (_) {
      // Swallow — warmup must never affect cold start.
    }
  }

  static void recordUrlTest({
    required String fp,
    required String type,
    required int delayMs,
    required bool ok,
  }) {
    if (!Telemetry.isEnabled) return;
    Telemetry.event(
      'node_urltest',
      props: {
        'fp': fp,
        'type': type.toLowerCase(),
        'delay_ms': delayMs.clamp(0, 60000),
        'ok': ok,
      },
    );
  }

  /// Convenience overload that looks up fp + type by mihomo node name.
  /// Silently no-ops if the node isn't in the current inventory (which
  /// means the subscription was never synced in this process — rare but
  /// possible after a hot-reload in debug).
  static void recordUrlTestByName({
    required String name,
    required int delayMs,
  }) {
    final fp = _nameToFp[name];
    final type = _nameToType[name];
    if (fp == null || type == null) return;
    recordUrlTest(
      fp: fp,
      type: type,
      delayMs: delayMs,
      // mihomo returns 0 for unreachable; clamp to ok=false there.
      ok: delayMs > 0 && delayMs < 10000,
    );
  }

  static void recordConnect({
    required String fp,
    required String type,
    required bool ok,
    String? reason,
    int? handshakeMs,
  }) {
    if (!Telemetry.isEnabled) return;
    Telemetry.event(
      'node_connect',
      priority: !ok,
      props: {
        'fp': fp,
        'type': type.toLowerCase(),
        'ok': ok,
        if (reason != null) 'reason': reason,
        if (handshakeMs != null) 'handshake_ms': handshakeMs.clamp(0, 60000),
      },
    );
  }

  static void recordSelect({
    required String fp,
    required String type,
    required String group,
  }) {
    if (!Telemetry.isEnabled) return;
    Telemetry.event(
      'node_select',
      props: {'fp': fp, 'type': type.toLowerCase(), 'group': group},
    );
  }

  /// Coarse region hint based on flag emojis + common tokens.
  static String _guessRegion(String name) {
    final lower = name.toLowerCase();
    if (name.contains('🇭🇰') || lower.contains('hk') || lower.contains('hong')) {
      return 'HK';
    }
    if (name.contains('🇺🇸') || lower.contains('us ') || lower.contains('美国')) {
      return 'US';
    }
    if (name.contains('🇯🇵') || lower.contains('jp') || lower.contains('日本')) {
      return 'JP';
    }
    if (name.contains('🇸🇬') || lower.contains('sg') ||
        lower.contains('新加坡')) {
      return 'SG';
    }
    if (name.contains('🇹🇼') || lower.contains('tw') || lower.contains('台湾')) {
      return 'TW';
    }
    if (name.contains('🇬🇧') || lower.contains('uk') || lower.contains('英国')) {
      return 'UK';
    }
    if (name.contains('🇰🇷') || lower.contains('kr') || lower.contains('韩国')) {
      return 'KR';
    }
    return 'OTHER';
  }
}
