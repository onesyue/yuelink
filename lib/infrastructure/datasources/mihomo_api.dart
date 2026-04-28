import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'circuit_breaker.dart';

/// Client for the mihomo RESTful API (external-controller).
///
/// Communicates with a running mihomo instance via HTTP on 127.0.0.1:9090.
/// This is the standard way all major Clash clients (Clash Verge Rev, FlClash,
/// metacubexd) interact with the mihomo core for proxy/traffic/connection data.
class MihomoApi {
  MihomoApi({
    this.host = '127.0.0.1',
    this.port = 9090,
    this.secret,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String host;
  final int port;
  final String? secret;
  final CircuitBreaker _breaker = CircuitBreaker();

  /// HTTP client used for every request. Production callers leave it
  /// null and get a stock `http.Client()` (which today is an `IOClient`
  /// wrapping the platform's HttpClient). Tests inject a
  /// `MockClient.handler` from `package:http/testing.dart` to stub
  /// responses without binding a real socket. The instance is owned —
  /// hold a single MihomoApi for the process lifetime; recreate (don't
  /// reuse) when `host`/`port`/`secret` change.
  final http.Client _client;

  /// Release the underlying HTTP client. Call from
  /// `CoreManager.stop()` / on session teardown so `IOClient` returns
  /// its connection-pool sockets to the OS instead of waiting for GC.
  /// Idempotent — once-closed clients silently no-op subsequent
  /// requests with `ClientException` which the retry path treats as
  /// transient.
  void dispose() {
    _client.close();
  }

  String get _baseUrl => 'http://$host:$port';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (secret != null) 'Authorization': 'Bearer $secret',
      };

  // ------------------------------------------------------------------
  // Version / Health
  // ------------------------------------------------------------------

  /// Check if mihomo is reachable.
  /// Bypasses the circuit breaker — this is the health check itself.
  Future<bool> isAvailable() async => (await healthSnapshot()).ok;

  /// Same probe as [isAvailable] but returns a classified failure
  /// reason for diagnostic logging. Used by the heartbeat manager
  /// (v1.0.22 P1-1) to distinguish "network down" from "mihomo
  /// hung" from "secret mismatch" in user-facing event-log exports
  /// without making every healthcheck site pay the bool→record cost.
  ///
  /// Reason values are a closed set:
  ///   * `'ok'`        — HTTP 200, healthy
  ///   * `'socket'`    — `SocketException` (port not listening / network gone)
  ///   * `'timeout'`   — 2 s budget elapsed (mihomo alive but unresponsive)
  ///   * `'http_<N>'`  — non-200 HTTP response (e.g. `http_401` = secret bad)
  ///   * `'other'`     — anything else (malformed response, TLS mismatch, …)
  Future<({bool ok, String reason})> healthSnapshot() async {
    try {
      final resp = await _client
          .get(Uri.parse('$_baseUrl/version'), headers: _headers)
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200) {
        _breaker.reset();
        return (ok: true, reason: 'ok');
      }
      debugPrint(
          '[MihomoApi] /version returned HTTP ${resp.statusCode} @ $_baseUrl');
      return (ok: false, reason: 'http_${resp.statusCode}');
    } on SocketException {
      return (ok: false, reason: 'socket');
    } on TimeoutException {
      return (ok: false, reason: 'timeout');
    } catch (e) {
      debugPrint('[MihomoApi] /version health-check unexpected failure: $e');
      return (ok: false, reason: 'other');
    }
  }

  // ------------------------------------------------------------------
  // Proxies
  // ------------------------------------------------------------------

  /// Get all proxies and groups.
  Future<Map<String, dynamic>> getProxies() async {
    return _get('/proxies');
  }

  /// Get a specific proxy info.
  Future<Map<String, dynamic>> getProxy(String name) async {
    return _get('/proxies/${Uri.encodeComponent(name)}');
  }

  /// Select a proxy in a group.
  Future<bool> changeProxy(String groupName, String proxyName) async {
    final resp = await _put(
      '/proxies/${Uri.encodeComponent(groupName)}',
      body: {'name': proxyName},
    );
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  /// Test proxy delay.
  Future<int> testDelay(String proxyName,
      {String url = 'https://www.gstatic.com/generate_204',
      int timeout = 5000}) async {
    try {
      final resp = await _get(
        '/proxies/${Uri.encodeComponent(proxyName)}/delay'
        '?url=${Uri.encodeComponent(url)}&timeout=$timeout',
      );
      return resp['delay'] as int? ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// Test all proxies in a group.
  Future<Map<String, dynamic>> testGroupDelay(String groupName,
      {String url = 'https://www.gstatic.com/generate_204',
      int timeout = 5000}) async {
    final resp = await _client
        .get(
          Uri.parse(
            '$_baseUrl/group/${Uri.encodeComponent(groupName)}/delay'
            '?url=${Uri.encodeComponent(url)}&timeout=$timeout',
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw MihomoApiException(resp.statusCode, resp.body);
    }
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  // ------------------------------------------------------------------
  // Connections
  // ------------------------------------------------------------------

  /// Get active connections.
  Future<Map<String, dynamic>> getConnections() async {
    return _get('/connections');
  }

  /// Close a specific connection.
  Future<bool> closeConnection(String id) async {
    final resp = await _delete('/connections/$id');
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  /// Close all connections.
  Future<bool> closeAllConnections() async {
    final resp = await _delete('/connections');
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  /// Flush fake-ip cache. Call on network-change so stale fake-IP → real-IP
  /// mappings from the previous network (with its own DNS pollution pattern)
  /// don't poison the new network's request-routing decisions. Matches FlClash's
  /// behaviour on Wi-Fi ↔ cellular transitions.
  Future<bool> flushFakeIpCache() async {
    final resp = await _post('/cache/fakeip/flush');
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  /// Update a rule-provider on demand (mihomo /providers/rules/{name}).
  /// Refreshes the rule set without requiring a full core restart.
  Future<bool> updateRuleProvider(String name) async {
    final resp = await _put('/providers/rules/${Uri.encodeComponent(name)}');
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  /// List all rule providers (name → info map). Empty if the config has
  /// no `rule-providers` section.
  Future<Map<String, dynamic>> listRuleProviders() async {
    try {
      final data = await _get('/providers/rules');
      final raw = data['providers'];
      if (raw is Map<String, dynamic>) return raw;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Refresh all rule providers in parallel. Returns (succeeded, failed)
  /// counts.
  Future<({int ok, int failed})> refreshAllRuleProviders() async {
    final list = await listRuleProviders();
    if (list.isEmpty) return (ok: 0, failed: 0);
    final results = await Future.wait(
      list.keys.map((name) => updateRuleProvider(name).catchError((_) => false)),
    );
    var ok = 0;
    var failed = 0;
    for (final r in results) {
      if (r) {
        ok++;
      } else {
        failed++;
      }
    }
    return (ok: ok, failed: failed);
  }

  // ------------------------------------------------------------------
  // Config
  // ------------------------------------------------------------------

  /// Get current running config.
  Future<Map<String, dynamic>> getConfig() async {
    return _get('/configs');
  }

  /// Patch running config (partial update).
  Future<bool> patchConfig(Map<String, dynamic> patch) async {
    final resp = await _patch('/configs', body: patch);
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  /// Set routing mode: "rule" | "global" | "direct".
  Future<bool> setRoutingMode(String mode) => patchConfig({'mode': mode});

  /// Set log level: "info" | "debug" | "warning" | "error" | "silent".
  Future<bool> setLogLevel(String level) =>
      patchConfig({'log-level': level});

  /// Get current routing mode from running config.
  Future<String> getRoutingMode() async {
    try {
      final cfg = await getConfig();
      return (cfg['mode'] as String?) ?? 'rule';
    } catch (_) {
      return 'rule';
    }
  }

  /// Reload config from file path. Throws [MihomoApiException] on failure.
  Future<bool> reloadConfig(String path, {bool force = false}) async {
    final resp = await _put(
      '/configs?force=$force',
      body: {'path': path},
    );
    if (resp.statusCode == 204 || resp.statusCode == 200) return true;
    throw MihomoApiException(resp.statusCode, resp.body);
  }

  /// Push a config YAML string directly to mihomo without touching the disk.
  /// Preferred over [reloadConfig] for runtime patches (e.g. chain proxy)
  /// because it avoids YAML round-trip corruption from file read/write.
  Future<void> pushConfig(String yamlContent, {bool force = true}) async {
    final resp = await _put(
      '/configs?force=$force',
      body: {'payload': yamlContent},
    );
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw MihomoApiException(resp.statusCode, resp.body);
    }
  }

  // ------------------------------------------------------------------
  // Rules
  // ------------------------------------------------------------------

  /// Get all rules.
  Future<Map<String, dynamic>> getRules() async {
    return _get('/rules');
  }

  // ------------------------------------------------------------------
  // Providers
  // ------------------------------------------------------------------

  /// Get all proxy providers.
  Future<Map<String, dynamic>> getProxyProviders() async {
    return _get('/providers/proxies');
  }

  /// Update a proxy provider (trigger re-download).
  Future<bool> updateProxyProvider(String name) async {
    final resp = await _put('/providers/proxies/${Uri.encodeComponent(name)}');
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  /// Health check a proxy provider.
  Future<void> healthCheckProvider(String name) async {
    await _get('/providers/proxies/${Uri.encodeComponent(name)}/healthcheck');
  }

  // ------------------------------------------------------------------
  // DNS
  // ------------------------------------------------------------------

  /// Query DNS.
  Future<Map<String, dynamic>> queryDns(String name,
      {String type = 'A'}) async {
    return _get('/dns/query?name=${Uri.encodeComponent(name)}&type=$type');
  }

  // ------------------------------------------------------------------
  // Streaming (WebSocket-like via long-polling)
  // ------------------------------------------------------------------

  /// Get a single traffic snapshot.
  /// For real-time, poll this or use WebSocket on /traffic.
  Future<({int up, int down})> getTraffic() async {
    final data = await _get('/traffic');
    return (
      up: (data['up'] as num?)?.toInt() ?? 0,
      down: (data['down'] as num?)?.toInt() ?? 0,
    );
  }

  /// Get memory usage.
  Future<int> getMemory() async {
    final data = await _get('/memory');
    return (data['inuse'] as num?)?.toInt() ?? 0;
  }

  // ------------------------------------------------------------------
  // HTTP helpers with retry
  // ------------------------------------------------------------------

  static const _kTimeout = Duration(seconds: 10);
  static const _maxRetries = 3;
  static const _retryDelays = [
    Duration(milliseconds: 300),
    Duration(milliseconds: 600),
    Duration(seconds: 1),
  ];

  /// Whether an error is transient and safe to retry.
  static bool _isTransient(Object e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is HttpException) return true;
    if (e is MihomoApiException && e.statusCode >= 500) return true;
    return false;
  }

  /// Execute [fn] with automatic retry on transient errors.
  /// Respects the circuit breaker — throws immediately if the breaker is open.
  Future<T> _withRetry<T>(Future<T> Function() fn) async {
    if (_breaker.isOpen) {
      throw MihomoApiException(
        503,
        'Circuit breaker open — mihomo API unavailable, retry after cooldown',
      );
    }
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final result = await fn();
        _breaker.recordSuccess();
        return result;
      } catch (e) {
        final isLast = attempt == _maxRetries - 1;
        if (!_isTransient(e)) rethrow;
        if (isLast) {
          _breaker.recordFailure();
          rethrow;
        }
        debugPrint('[MihomoApi] Retry ${attempt + 1}/$_maxRetries after: $e');
        await Future.delayed(_retryDelays[attempt]);
      }
    }
    throw StateError('unreachable');
  }

  /// Threshold (bytes) above which JSON decoding is offloaded to a
  /// background isolate. The 20 KB knee chosen in v1.0.23-pre P1.C
  /// turned out to put the common `/proxies` payload (50–200 KB for
  /// users with ~200 inline nodes + 30 rule-providers) on the isolate
  /// path on every fetch — and `Isolate.run` with a closure-captured
  /// String body intermittently hung on Android and Windows release
  /// builds. The wrapper's `catch (_)` in `ProxyRepository.getProxies`
  /// swallowed the failure silently, leaving `proxyGroupsProvider`
  /// state at `[]` for the entire session: dashboard stuck on
  /// '处理中', Nodes tab stuck on the loading spinner.
  ///
  /// 256 KB keeps `/proxies`, `/connections`, single-proxy reads,
  /// and small ack endpoints all on the main thread. JSON decode of
  /// 150 KB is ~5–10 ms on a mid-tier Android — comfortably under
  /// a 16 ms frame budget, and far cheaper than re-shipping a hung
  /// release. The isolate path is retained only for genuinely
  /// pathological payloads (>256 KB) where one frame jank beats
  /// the cost of a spawn.
  static const _kIsolateDecodeThreshold = 256 * 1024;

  Future<Map<String, dynamic>> _get(String path) => _withRetry(() async {
    final resp = await _client
        .get(Uri.parse('$_baseUrl$path'), headers: _headers)
        .timeout(_kTimeout);
    if (resp.statusCode != 200) {
      throw MihomoApiException(resp.statusCode, resp.body);
    }
    // Large responses (`/proxies`, `/connections`) are commonly 50 KB+
    // and decode > 1 frame on low-end Android. Threshold rationale at
    // [_kIsolateDecodeThreshold].
    final body = resp.body;
    if (body.length > _kIsolateDecodeThreshold) {
      return Isolate.run(() => json.decode(body) as Map<String, dynamic>);
    }
    return json.decode(body) as Map<String, dynamic>;
  });

  Future<http.Response> _put(String path,
      {Map<String, dynamic>? body}) async {
    return _client
        .put(
          Uri.parse('$_baseUrl$path'),
          headers: _headers,
          body: body != null ? json.encode(body) : null,
        )
        .timeout(_kTimeout);
  }

  Future<http.Response> _patch(String path,
      {Map<String, dynamic>? body}) async {
    return _client
        .patch(
          Uri.parse('$_baseUrl$path'),
          headers: _headers,
          body: body != null ? json.encode(body) : null,
        )
        .timeout(_kTimeout);
  }

  Future<http.Response> _delete(String path) async {
    return _client
        .delete(Uri.parse('$_baseUrl$path'), headers: _headers)
        .timeout(_kTimeout);
  }

  Future<http.Response> _post(String path,
      {Map<String, dynamic>? body}) async {
    return _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: _headers,
          body: body != null ? json.encode(body) : null,
        )
        .timeout(_kTimeout);
  }
}

/// Exception from mihomo API.
class MihomoApiException implements Exception {
  final int statusCode;
  final String body;
  MihomoApiException(this.statusCode, this.body);

  @override
  String toString() => 'MihomoApiException($statusCode): $body';
}
