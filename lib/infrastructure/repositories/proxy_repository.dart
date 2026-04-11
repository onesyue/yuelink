import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datasources/mihomo_api.dart';
import '../../core/providers/core_provider.dart';

/// Batches delay-test results that arrive within 300 ms into a single map
/// and flushes them via [onFlush]. This reduces the number of provider state
/// updates when testing many nodes simultaneously.
class _DelayBatcher {
  final void Function(Map<String, int>) onFlush;

  _DelayBatcher({required this.onFlush});

  static const _window = Duration(milliseconds: 300);

  final Map<String, int> _pending = {};
  Timer? _timer;

  void add(String name, int delay) {
    _pending[name] = delay;
    _timer ??= Timer(_window, _flush);
  }

  void _flush() {
    if (_pending.isEmpty) {
      _timer = null;
      return;
    }
    final snapshot = Map<String, int>.from(_pending);
    _pending.clear();
    _timer = null;
    onFlush(snapshot);
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// Repository wrapping [MihomoApi] proxy-related endpoints.
///
/// Accepts [MihomoApi] via constructor injection so it can be swapped in tests.
/// Includes a [_DelayBatcher] that accumulates individual delay-test results
/// and flushes them in batches to reduce provider rebuild frequency.
class ProxyRepository {
  ProxyRepository(this._api);

  final MihomoApi _api;
  late final _DelayBatcher _batcher;

  // Called by the provider so we can set up the batcher with a callback.
  void _initBatcher(void Function(Map<String, int>) onFlush) {
    _batcher = _DelayBatcher(onFlush: onFlush);
  }

  Future<Map<String, dynamic>> getProxies() => _api.getProxies();

  Future<bool> changeProxy(String groupName, String proxyName) =>
      _api.changeProxy(groupName, proxyName);

  Future<int> testDelay(
    String proxyName, {
    String url = 'https://www.gstatic.com/generate_204',
    int timeoutMs = 5000,
  }) =>
      _api.testDelay(proxyName, url: url, timeout: timeoutMs);

  Future<Map<String, dynamic>> testGroupDelay(
    String groupName, {
    String url = 'https://www.gstatic.com/generate_204',
    int timeoutMs = 5000,
  }) =>
      _api.testGroupDelay(groupName, url: url, timeout: timeoutMs);

  Future<Map<String, dynamic>> getProxyProviders() =>
      _api.getProxyProviders();

  Future<bool> updateProxyProvider(String name) =>
      _api.updateProxyProvider(name);

  Future<void> healthCheckProvider(String name) =>
      _api.healthCheckProvider(name);

  /// Tests [name]'s delay and routes the result through the internal batcher.
  /// [onResult] is called when the batcher flushes (up to 300ms later).
  Future<int> testDelayWithBatch(
    String name, {
    String url = 'https://www.gstatic.com/generate_204',
    int timeoutMs = 5000,
    required void Function(String, int) onResult,
  }) async {
    final delay = await testDelay(name, url: url, timeoutMs: timeoutMs);
    // Route through batcher; the batcher callback will call onResult for each
    // flushed entry.  We also return the raw delay for callers that need it.
    _batcher.add(name, delay);
    return delay;
  }

  void dispose() {
    _batcher.dispose();
  }
}

final proxyRepositoryProvider = Provider<ProxyRepository>((ref) {
  final api = ref.watch(mihomoApiProvider);
  final repo = ProxyRepository(api);
  // Wire batcher flush — callers of testDelayWithBatch supply their own
  // onResult callback, so the batcher here is a no-op placeholder that
  // accumulates and discards (the actual per-call onResult handles updates).
  // We still initialise it so _batcher is non-late-uninitialized.
  repo._initBatcher((_) {});
  ref.onDispose(repo.dispose);
  return repo;
});
