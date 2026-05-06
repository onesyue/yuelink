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
/// v2 fingerprint input order is intentionally shared with server-side
/// identity code:
///
///   type | server | port | uuid/password | sni/host | node_id
///
/// The uuid/password is used only as local hash input and is never uploaded.
class NodeTelemetry {
  NodeTelemetry._();

  static const _fpAlgorithmVersion = 2;

  /// In-memory `name → fp` map, populated on [recordInventory] so later
  /// URL-test / connect events can look up fingerprints by the string
  /// identifier mihomo uses. Lives only for the current process lifetime —
  /// the next subscription sync overwrites the entire map.
  static final Map<String, String> _nameToFp = {};
  static final Map<String, String> _nameToType = {};
  static final Map<String, Map<String, dynamic>> _nameToMeta = {};
  static final Map<String, List<DateTime>> _probeFailureWindows = {};

  static const _aiTargets = {'claude', 'chatgpt'};
  static const _failureWindow = Duration(minutes: 5);
  static const _maxFailuresPerWindow = 3;

  /// Lookup a fingerprint by mihomo node name. Returns null when the node
  /// wasn't part of the most-recent inventory (e.g. edge case during a
  /// live profile swap). Callers should guard on null and skip telemetry.
  static String? fpForName(String name) => _nameToFp[name];

  /// Lookup the protocol type for a node name (hy2 / vless / trojan / …).
  static String? typeForName(String name) => _nameToType[name];

  /// Lookup the sanitized identity metadata used by node events.
  static Map<String, dynamic>? metadataForName(String name) {
    final meta = _nameToMeta[name];
    return meta == null ? null : Map<String, dynamic>.unmodifiable(meta);
  }

  static void resetForTest() {
    _nameToFp.clear();
    _nameToType.clear();
    _nameToMeta.clear();
    _probeFailureWindows.clear();
  }

  /// Compute the 16-hex fingerprint for a mihomo proxy entry.
  static String fingerprint(Map<String, dynamic> proxy) {
    final parts = <String>[
      _nodeType(proxy),
      _string(proxy, 'server'),
      _string(proxy, 'port'),
      _credential(proxy),
      _sniOrHost(proxy),
      _nodeId(proxy),
    ];

    final digest = sha256.convert(utf8.encode(parts.join('|')));
    return digest.toString().substring(0, 16);
  }

  /// Normalize a proxy into the inventory row schema — only fp + classifying
  /// metadata, never raw server/port/sni.
  static Map<String, dynamic> inventoryRow(Map<String, dynamic> proxy) {
    return _metadata(proxy);
  }

  static Map<String, dynamic> _metadata(Map<String, dynamic> proxy) {
    final label = _firstString(proxy, const ['label', 'name']);
    final region = _region(proxy);
    final xbServerId = _xbServerId(proxy);
    final sid = _sid(proxy, fallbackLabel: label);
    final row = <String, dynamic>{
      'fp': fingerprint(proxy),
      'type': _nodeType(proxy),
    };
    if (xbServerId != null) {
      row['xb_server_id'] = xbServerId;
    } else if (sid != null && sid.isNotEmpty) {
      row['sid'] = sid;
    }
    if (region.isNotEmpty) row['region'] = region;
    if (label.isNotEmpty) row['label'] = label;
    return row;
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
    _nameToMeta.clear();
    for (final p in proxies) {
      final name = (p['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final meta = _metadata(p);
      _nameToFp[name] = meta['fp'] as String;
      _nameToType[name] = meta['type'] as String;
      _nameToMeta[name] = meta;
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
    int? xbServerId,
    String? sid,
    String? region,
    required int delayMs,
    required bool ok,
    String? reason,
  }) {
    if (!Telemetry.isEnabled) return;
    Telemetry.event(
      'node_urltest',
      props: {
        'fp': fp,
        'type': type.toLowerCase(),
        'delay_ms': delayMs.clamp(0, 60000),
        'ok': ok,
        'xb_server_id': ?xbServerId,
        if (sid != null && sid.isNotEmpty) 'sid': sid,
        if (region != null && region.isNotEmpty) 'region': region,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
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
    String? reason,
  }) {
    final meta = _nameToMeta[name];
    final fp = meta?['fp'] as String? ?? _nameToFp[name];
    final type = meta?['type'] as String? ?? _nameToType[name];
    if (fp == null || type == null) return;
    final ok = delayMs > 0 && delayMs < 10000;
    recordUrlTest(
      fp: fp,
      type: type,
      xbServerId: meta?['xb_server_id'] as int?,
      sid: meta?['sid'] as String?,
      region: meta?['region'] as String?,
      delayMs: delayMs > 0 ? delayMs : 5000,
      // mihomo returns 0 for unreachable; clamp to ok=false there.
      ok: ok,
      reason: ok ? null : (reason ?? _urlTestFailureReason(delayMs)),
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
        'reason': ?reason,
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

  /// Map a probe URL to a target category. Closed set: transport / claude /
  /// chatgpt / google / youtube / netflix / github / other. Mirrors the
  /// matrix in scripts/sre/probe_nodes.py so RUM and active probe agree.
  static String classifyTarget(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return 'other';
    if (host.endsWith('claude.ai') || host.endsWith('anthropic.com')) {
      return 'claude';
    }
    if (host.endsWith('chatgpt.com') || host.endsWith('chat.openai.com')) {
      return 'chatgpt';
    }
    if (host.endsWith('netflix.com')) return 'netflix';
    if (host.endsWith('github.com') || host.endsWith('githubusercontent.com')) {
      return 'github';
    }
    if (host.endsWith('youtube.com') || host.endsWith('youtu.be')) {
      return 'youtube';
    }
    if (host.endsWith('google.com') || host.endsWith('gstatic.com')) {
      // The default delay-test URL is gstatic.com/generate_204 — kept as a
      // distinct `transport` bucket (vs the user-facing `google` site) so
      // dashboards can separate "node carries packets" from "Google search
      // is reachable" instead of conflating them.
      if (host == 'www.gstatic.com' || host == 'gstatic.com') {
        return 'transport';
      }
      return 'google';
    }
    return 'other';
  }

  /// Emit a [TelemetryEvents.nodeProbeResultV1] event with the closed
  /// field schema. Reject silently if telemetry is opted-out OR if the
  /// node isn't in inventory (no fp resolution possible).
  ///
  /// Field whitelist (in addition to the envelope's automatic
  /// `client_id / session_id / platform / version / ts`):
  ///   - `fp`             non-reversible 16-hex node hash
  ///   - `type`           lowercase protocol (vless / hysteria2 / …)
  ///   - `xb_server_id`   XBoard v2_server.id, optional. Used by the
  ///                       server-side enrichment pipeline to derive
  ///                       `path_class` (direct / via_v4_relay / via_v6_relay)
  ///                       from inventory; clients deliberately do NOT
  ///                       derive path_class themselves because many nodes
  ///                       share host=v4.yuetoto.net.
  ///   - `group`          proxy-group name (optional — null when called
  ///                       from a single-node test)
  ///   - `node_name_hash` SHA-256/16 of the mihomo label, never raw label
  ///   - `target`         classifyTarget result, closed set
  ///   - `ok`             bool, derived from latency
  ///   - `status`         `ok` or normalized error class
  ///   - `latency_ms`     int, clamped to [0, 60000]
  ///   - `timeout_ms`     probe budget when known
  ///   - `error_class`    timeout / dns_failed / tcp_failed / tls_failed /
  ///                       reality_auth_failed / http_403 / http_429 /
  ///                       cloudflare_block / ai_blocked / unknown
  ///   - `status_code`    HTTP status when available (raw probe), else null
  ///   - `is_ai_target`   bool for Claude / ChatGPT split
  ///   - `core_version`   mihomo version string (best-effort, may be empty)
  ///   - `mode`           'global' / 'rule' / 'tun' / 'system_proxy' /
  ///                       etc. — caller resolves
  ///   - `sample_rate`    numeric sampling rate used by the caller
  ///   - `network_type`, `client_region`, `exit_country`, `exit_isp`
  ///                       coarse optional metadata when available
  ///
  /// Hard rule: this method MUST NOT include any of:
  /// `server / port / uuid / password / sni / servername / public-key /
  ///  short-id / path / host`. The covering test
  /// `node_probe_result_v1_does_not_leak_secrets` enforces this.
  static void recordProbeResult({
    required String fp,
    required String type,
    int? xbServerId,
    String? group,
    String? nodeNameHash,
    required String target,
    required bool ok,
    required int latencyMs,
    int? timeoutMs,
    String? errorClass,
    int? statusCode,
    String? coreVersion,
    String? connectionMode,
    bool? tunEnabled,
    String? tunStack,
    bool? routeOk,
    bool? dnsOk,
    bool? controllerOk,
    String? networkType,
    String? clientRegion,
    String? exitCountry,
    String? exitIsp,
    double sampleRate = 1.0,
  }) {
    if (!Telemetry.isEnabled) return;
    final normalizedError = normalizeErrorClass(
      target: target,
      ok: ok,
      statusCode: statusCode,
      errorClass: errorClass,
    );
    if (!ok && !_allowFailureProbe(fp, target, normalizedError)) return;
    final status = ok ? 'ok' : normalizedError;
    final isAiTarget = _aiTargets.contains(target);
    Telemetry.event(
      TelemetryEvents.nodeProbeResultV1,
      // Failed probes are diagnostically valuable — survive buffer prune.
      priority: !ok,
      props: {
        'fp': fp,
        'type': type.toLowerCase(),
        'xb_server_id': ?xbServerId,
        if (group != null && group.isNotEmpty) 'group': group,
        if (nodeNameHash != null && nodeNameHash.isNotEmpty)
          'node_name_hash': nodeNameHash,
        'target': target,
        'ok': ok,
        'status': status,
        'latency_ms': latencyMs.clamp(0, 60000),
        if (timeoutMs != null) 'timeout_ms': timeoutMs.clamp(0, 60000),
        if (!ok) 'error_class': normalizedError,
        'status_code': ?statusCode,
        'is_ai_target': isAiTarget,
        if (coreVersion != null && coreVersion.isNotEmpty)
          'core_version': coreVersion,
        if (connectionMode != null && connectionMode.isNotEmpty)
          'connection_mode': connectionMode,
        if (connectionMode != null && connectionMode.isNotEmpty)
          'mode': _normalizeMode(connectionMode),
        'tun_enabled': ?tunEnabled,
        if (tunStack != null && tunStack.isNotEmpty) 'tun_stack': tunStack,
        'route_ok': ?routeOk,
        'dns_ok': ?dnsOk,
        'controller_ok': ?controllerOk,
        if (networkType != null && networkType.isNotEmpty)
          'network_type': networkType,
        if (clientRegion != null && clientRegion.isNotEmpty)
          'client_region': clientRegion,
        if (exitCountry != null && exitCountry.isNotEmpty)
          'exit_country': exitCountry,
        if (exitIsp != null && exitIsp.isNotEmpty) 'exit_isp': exitIsp,
        'sample_rate': sampleRate.clamp(0.0, 1.0),
      },
    );
  }

  static String normalizeErrorClass({
    required String target,
    required bool ok,
    int? statusCode,
    String? errorClass,
  }) {
    if (ok) return 'ok';
    final raw = (errorClass ?? '').trim().toLowerCase();
    if (raw.contains('reality') && raw.contains('auth')) {
      return 'reality_auth_failed';
    }
    if (raw == 'context deadline exceeded') return 'timeout';
    if (raw == 'socket') return 'tcp_failed';
    if (raw == 'handshake') return 'tls_failed';
    if (raw == 'dns_fail') return 'dns_failed';
    if (raw == 'cloudflare_block' || raw == 'ai_blocked') return raw;
    const allowed = {
      'timeout',
      'dns_failed',
      'tcp_failed',
      'tls_failed',
      'reality_auth_failed',
      'proxy_auth_failed',
      'connection_reset',
      'http_403',
      'http_429',
      'cloudflare_block',
      'ai_blocked',
      'unknown',
    };
    if (allowed.contains(raw)) return raw;
    if (statusCode == 1020) return 'cloudflare_block';
    if (statusCode == 403) {
      return _aiTargets.contains(target) ? 'ai_blocked' : 'http_403';
    }
    if (statusCode == 429) return 'http_429';
    return raw.isEmpty ? 'unknown' : 'unknown';
  }

  /// Convenience overload: resolves fp + type from the in-process
  /// inventory, classifies the target URL. Silent no-op when the node
  /// isn't in inventory.
  ///
  /// Maps the mihomo `/delay` semantics:
  ///   - `delayMs > 0` → ok, latency = delayMs
  ///   - `delayMs <= 0` → !ok, latency = timeoutMs, error_class = 'timeout'
  static void recordProbeResultByName({
    required String name,
    required String testUrl,
    required int delayMs,
    String? group,
    String? coreVersion,
    String? connectionMode,
    bool? tunEnabled,
    String? tunStack,
    bool? routeOk,
    bool? dnsOk,
    bool? controllerOk,
    String? networkType,
    String? clientRegion,
    String? exitCountry,
    String? exitIsp,
    int timeoutMs = 5000,
    double sampleRate = 1.0,
  }) {
    final meta = _nameToMeta[name];
    final fp = meta?['fp'] as String? ?? _nameToFp[name];
    final type = meta?['type'] as String? ?? _nameToType[name];
    if (fp == null || type == null) return;
    final ok = delayMs > 0 && delayMs < 60000;
    recordProbeResult(
      fp: fp,
      type: type,
      xbServerId: meta?['xb_server_id'] as int?,
      group: group,
      nodeNameHash: _hashText(name),
      target: classifyTarget(testUrl),
      ok: ok,
      latencyMs: ok ? delayMs : timeoutMs,
      timeoutMs: timeoutMs,
      errorClass: ok ? null : 'timeout',
      coreVersion: coreVersion,
      connectionMode: connectionMode,
      tunEnabled: tunEnabled,
      tunStack: tunStack,
      routeOk: routeOk,
      dnsOk: dnsOk,
      controllerOk: controllerOk,
      networkType: networkType,
      clientRegion: clientRegion,
      exitCountry: exitCountry,
      exitIsp: exitIsp,
      sampleRate: sampleRate,
    );
  }

  static String _normalizeMode(String value) {
    switch (value) {
      case 'systemProxy':
        return 'system_proxy';
      case 'tun':
      case 'rule':
      case 'global':
      case 'direct':
        return value;
      default:
        return value.toLowerCase();
    }
  }

  static String _hashText(String value) {
    return sha256.convert(utf8.encode(value)).toString().substring(0, 16);
  }

  static bool _allowFailureProbe(String fp, String target, String errorClass) {
    final key = '$fp|$target|$errorClass';
    final now = DateTime.now();
    final cutoff = now.subtract(_failureWindow);
    final window = _probeFailureWindows.putIfAbsent(key, () => <DateTime>[]);
    window.removeWhere((ts) => ts.isBefore(cutoff));
    if (window.length >= _maxFailuresPerWindow) return false;
    window.add(now);
    return true;
  }

  static String _nodeType(Map<dynamic, dynamic> proxy) {
    final raw = _string(proxy, 'type').toLowerCase();
    return raw == 'hy2' ? 'hysteria2' : raw;
  }

  static String _credential(Map<dynamic, dynamic> proxy) {
    final type = _nodeType(proxy);
    if (type == 'vless' || type == 'vmess') {
      return _firstString(proxy, const ['uuid', 'password', 'passwd']);
    }
    return _firstString(proxy, const ['password', 'passwd', 'uuid']);
  }

  static String _sniOrHost(Map<dynamic, dynamic> proxy) {
    final direct = _firstString(proxy, const [
      'sni',
      'servername',
      'server-name',
      'host',
    ]);
    if (direct.isNotEmpty) return direct;

    final wsOpts = _map(proxy, 'ws-opts') ?? _map(proxy, 'wsOpts');
    final headers = wsOpts == null ? null : _map(wsOpts, 'headers');
    final host = headers == null
        ? ''
        : _firstString(headers, const ['Host', 'host', 'HOST']);
    if (host.isNotEmpty) return host;

    final httpOpts = _map(proxy, 'http-opts') ?? _map(proxy, 'httpOpts');
    final httpHeaders = httpOpts == null ? null : _map(httpOpts, 'headers');
    return httpHeaders == null
        ? ''
        : _firstString(httpHeaders, const ['Host', 'host', 'HOST']);
  }

  static String _nodeId(Map<dynamic, dynamic> proxy) {
    final id = _firstString(proxy, const [
      'node_id',
      'node-id',
      'nodeId',
      'xb_server_id',
      'xb-server-id',
      'xbServerId',
      'server_id',
      'server-id',
      'serverId',
    ]);
    if (id.isNotEmpty) return id;
    return _firstString(proxy, const ['sid', 'server_sid', 'serverSid']);
  }

  static int? _xbServerId(Map<dynamic, dynamic> proxy) {
    for (final key in const [
      'xb_server_id',
      'xb-server-id',
      'xbServerId',
      'server_id',
      'server-id',
      'serverId',
      'node_id',
      'node-id',
      'nodeId',
    ]) {
      final parsed = _parseInt(proxy[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return int.tryParse(text) ?? double.tryParse(text)?.toInt();
  }

  static String? _sid(
    Map<dynamic, dynamic> proxy, {
    required String fallbackLabel,
  }) {
    final explicit = _firstString(proxy, const [
      'sid',
      'server_sid',
      'server-sid',
      'serverSid',
      'node_sid',
      'node-sid',
      'nodeSid',
    ]);
    if (explicit.isNotEmpty) return explicit;
    final id = _nodeId(proxy);
    if (id.isNotEmpty && _parseInt(id) == null) return id;
    return fallbackLabel.isEmpty ? null : fallbackLabel;
  }

  static String _region(Map<dynamic, dynamic> proxy) {
    final explicit = _firstString(proxy, const [
      'region',
      'country_code',
      'country-code',
      'countryCode',
      'country',
      'cc',
    ]).toUpperCase();
    if (explicit.isNotEmpty) return explicit;
    return _guessRegion(_string(proxy, 'name'));
  }

  static String _urlTestFailureReason(int delayMs) {
    if (delayMs <= 0) return 'timeout';
    if (delayMs >= 10000) return 'timeout';
    return 'failed';
  }

  static Map<dynamic, dynamic>? _map(Map<dynamic, dynamic> proxy, String key) {
    final value = proxy[key];
    return value is Map ? value : null;
  }

  static String _firstString(Map<dynamic, dynamic> proxy, List<String> keys) {
    for (final key in keys) {
      final value = _string(proxy, key);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _string(Map<dynamic, dynamic> proxy, String key) {
    final value = proxy[key];
    if (value == null) return '';
    final text = value.toString().trim();
    return text;
  }

  /// Coarse region hint based on flag emojis + common tokens.
  static String _guessRegion(String name) {
    final lower = name.toLowerCase();
    if (name.contains('🇭🇰') ||
        lower.contains('hk') ||
        lower.contains('hong')) {
      return 'HK';
    }
    if (name.contains('🇺🇸') ||
        lower.contains('us ') ||
        lower.contains('美国')) {
      return 'US';
    }
    if (name.contains('🇯🇵') || lower.contains('jp') || lower.contains('日本')) {
      return 'JP';
    }
    if (name.contains('🇸🇬') ||
        lower.contains('sg') ||
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
