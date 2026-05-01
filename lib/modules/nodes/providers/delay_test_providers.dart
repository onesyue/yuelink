import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../core/providers/core_preferences_providers.dart';
import '../../../core/storage/settings_service.dart';
import '../../../infrastructure/repositories/proxy_repository.dart';
import '../../../shared/node_telemetry.dart';
import '../../../shared/telemetry.dart';
import 'delay_test_recovery.dart';

/// Node-latency testing surface — providers + the [DelayTestActions]
/// imperative action class that owns single-node and group-test flows.
///
/// Was inlined in `nodes_providers.dart` (~270 lines, half of that file).
/// Pulling it out separates the "list of proxy groups" concern (which
/// stays in nodes_providers) from the "running latency probes against
/// those proxies" concern (here). Both still re-export through
/// nodes_providers.dart so existing widget imports stay stable — see
/// the trailing `export` in nodes_providers.dart.

/// Custom URL used for latency testing. Defaults to the standard gstatic URL.
final testUrlProvider =
    StateProvider<String>((ref) => 'https://www.gstatic.com/generate_204');

/// Per-node latest delay (ms). -1 means "tested and timed out". Persisted
/// to SettingsService after each successful test so a re-launch shows
/// the user where they left off.
final delayResultsProvider = StateProvider<Map<String, int>>((ref) => {});

/// Set of node names with an in-flight latency test. UI uses this to
/// show the spinner / disable repeat-tap.
final delayTestingProvider = StateProvider<Set<String>>((ref) => {});

/// Imperative entry point for triggering tests. Reads/writes the two
/// state providers above and routes through [ProxyRepository] for the
/// real-mode HTTP call (or [CoreMock] in mock mode).
final delayTestProvider =
    Provider<DelayTestActions>((ref) => DelayTestActions(ref));

class DelayTestActions {
  final Ref ref;
  DelayTestActions(this.ref);

  ProxyRepository get _repo => ref.read(proxyRepositoryProvider);

  /// Test delay for a single proxy node.
  ///
  /// The unmark step is wrapped in `try/finally` so the node doesn't stay
  /// stuck showing "testing…" in the UI when the await below throws
  /// (network error, core restart, timeout). Previously the unmark was
  /// unreachable on the error path and the user had to refresh the page
  /// to clear the stale state.
  Future<int> testDelay(String proxyName) async {
    final testing = Set<String>.from(ref.read(delayTestingProvider));
    testing.add(proxyName);
    ref.read(delayTestingProvider.notifier).state = testing;

    try {
      final manager = CoreManager.instance;
      final testUrl = ref.read(testUrlProvider);
      int delay;

      // Accumulate results in a single map — write state once at the end.
      final results = Map<String, int>.from(ref.read(delayResultsProvider));

      if (manager.isMockMode) {
        delay = await manager.core.testDelay(proxyName);
      } else {
        delay = await _repo.testDelayWithBatch(
          proxyName,
          url: testUrl,
          onResult: (name, d) {
            results[name] = d;
            ref.read(delayResultsProvider.notifier).state =
                Map<String, int>.from(results);
          },
        );
      }

      results[proxyName] = delay;
      ref.read(delayResultsProvider.notifier).state = results;
      SettingsService.setDelayResults(results);

      // Opt-in telemetry — anonymous fingerprint + latency only.
      NodeTelemetry.recordUrlTestByName(name: proxyName, delayMs: delay);
      // v1 closed-schema event — single-node tests don't know their group,
      // so we omit it.
      NodeTelemetry.recordProbeResultByName(
        name: proxyName,
        testUrl: testUrl,
        delayMs: delay,
        connectionMode: ref.read(connectionModeProvider),
      );

      return delay;
    } finally {
      final doneSet = Set<String>.from(ref.read(delayTestingProvider));
      doneSet.remove(proxyName);
      ref.read(delayTestingProvider.notifier).state = doneSet;
    }
  }

  /// Test all proxies in a group.
  ///
  /// In real mode, uses the REST API group delay test (parallel).
  /// In mock mode, falls back to sequential testing.
  ///
  /// Auto-recovery: when the HTTP call succeeds but the result map shows
  /// every node as timed-out (mihomo's DNS / fake-IP / connection pool
  /// carrying stale state from a previous session), we silently flush
  /// client-side connections + fake-IP cache and retry up to twice
  /// before surfacing the failure.
  ///
  /// Bug this fixes: after "disconnect → reconnect → test speed" the
  /// whole group used to flash red because mihomo's internal state from
  /// the previous session was not fully reset by stop→start. Users had
  /// to either wait, reopen the app, or hit the manual "restart core"
  /// button in connection_repair_page.
  Future<void> testGroup(String groupName, List<String> proxyNames) async {
    final manager = CoreManager.instance;

    if (!manager.isMockMode) {
      final testing = Set<String>.from(ref.read(delayTestingProvider));
      testing.addAll(proxyNames);
      ref.read(delayTestingProvider.notifier).state = testing;

      final testUrl = ref.read(testUrlProvider);
      try {
        // v1.0.21 hotfix P0-3: both "all timed out" AND "HTTP call threw"
        // must go through the same flush+retry recovery path. Previously
        // the catch branch below marked every node red immediately,
        // producing the "test speed after reconnect is solid red" UX
        // the user hit. Now the helper handles both cases uniformly.
        final outcome = await runGroupDelayWithRecovery(
          runTest: () => _repo.testGroupDelay(groupName, url: testUrl),
          flushConnections: () async {
            try {
              await manager.api.closeAllConnections();
            } catch (_) {}
          },
          flushFakeIp: () async {
            try {
              await manager.api.flushFakeIpCache();
            } catch (_) {}
          },
          // v1.0.22 P0-2: clear the stale URL-test cache that selector
          // groups otherwise reuse across a stop→start cycle. Without
          // this, the first delay-test after a reconnect sees the
          // previous run's timeout values and renders the whole group
          // red even when the underlying proxies are healthy.
          // GET /providers/proxies/{name}/healthcheck refreshes the
          // selector's per-node delay cache. Per-call swallowed because
          // healthcheck on a Compatible-vehicleType provider (mihomo's
          // synthetic wrapper for inline proxies) returns 4xx — that's
          // expected, not a failure of recovery.
          //
          // v1.0.22 P3-D: parallelise across providers and cap each
          // call at 12 s. Pre-fix, every healthcheck went through
          // MihomoApi._withRetry (3×10 s) serially per provider per
          // recovery round — N providers × 30 s × 3 rounds easily ran
          // into multiple minutes when mihomo was slow right after a
          // reconnect, surfacing as the "测速一直转圈" report. The
          // outer recovery still has its own wall-clock budget below.
          healthCheckProviders: () async {
            try {
              final providers = await manager.api
                  .getProxyProviders()
                  .timeout(const Duration(seconds: 5));
              final names =
                  (providers['providers'] as Map?)?.keys.cast<String>() ??
                      const <String>[];
              if (names.isEmpty) return;
              await Future.wait(
                names.map((name) async {
                  try {
                    await manager.api
                        .healthCheckProvider(name)
                        .timeout(const Duration(seconds: 12));
                  } catch (_) {
                    // ignore per-provider failures (timeout, 4xx, etc.)
                  }
                }),
                eagerError: false,
              );
            } catch (_) {
              // /providers/proxies itself may 404/5xx during early init
              // — the runTest() retry will surface the real state.
            }
          },
          isAllTimeout: (r) => _isAllTimeout(r, proxyNames),
          // v1.0.22 P3-D: hard cap on the entire recovery loop. mihomo
          // post-reconnect is occasionally slow enough that even with
          // parallel healthchecks the three retry rounds can stretch
          // beyond a minute — at which point the user has long since
          // assumed the app is hung. 60 s gives the first attempt
          // (30 s) one realistic recovery shot then surrenders so the
          // spinner clears and the group shows red as a last resort.
          totalBudget: const Duration(seconds: 60),
        );

        if (outcome.failureReason != null) {
          Telemetry.event(
            TelemetryEvents.delayTestAllTimeout,
            props: {
              'group': groupName,
              'count': proxyNames.length,
              // 'all_timeout' vs 'exception' — the dashboard can now
              // distinguish stale-core-state failures from HTTP errors.
              'reason': outcome.failureReason,
            },
          );
        }
        if (outcome.recovered) {
          Telemetry.event(TelemetryEvents.delayTestAutoRecovered);
        }

        final results = outcome.results;
        if (results != null) {
          // Results shape: {proxyName: {delay: int}} or {proxyName: int}
          final current =
              Map<String, int>.from(ref.read(delayResultsProvider));
          for (final entry in results.entries) {
            final value = entry.value;
            if (value is int) {
              current[entry.key] = value;
            } else if (value is Map) {
              current[entry.key] = (value['delay'] as num?)?.toInt() ?? -1;
            }
          }
          ref.read(delayResultsProvider.notifier).state = current;
          SettingsService.setDelayResults(current);

          // Opt-in telemetry — one event per tested node.
          final connMode = ref.read(connectionModeProvider);
          for (final name in proxyNames) {
            final delay = current[name];
            if (delay != null) {
              NodeTelemetry.recordUrlTestByName(name: name, delayMs: delay);
              NodeTelemetry.recordProbeResultByName(
                name: name,
                testUrl: testUrl,
                delayMs: delay,
                group: groupName,
                connectionMode: connMode,
              );
            }
          }
        } else {
          // Every recovery round also failed — mark all red as last resort.
          debugPrint('[DelayTest] group "$groupName" '
              '(${proxyNames.length} nodes) failed after recovery '
              '(reason=${outcome.failureReason})');
          final current =
              Map<String, int>.from(ref.read(delayResultsProvider));
          final connMode = ref.read(connectionModeProvider);
          for (final name in proxyNames) {
            current[name] = -1;
            NodeTelemetry.recordUrlTestByName(
              name: name,
              delayMs: -1,
              reason: outcome.failureReason ?? 'timeout',
            );
            NodeTelemetry.recordProbeResultByName(
              name: name,
              testUrl: testUrl,
              delayMs: -1,
              group: groupName,
              connectionMode: connMode,
            );
          }
          ref.read(delayResultsProvider.notifier).state = current;
        }
      } finally {
        // Unmark all — always runs, even if the unexpected happens
        // (StateError during state write, etc.). Without this users see
        // perpetual "testing…" dots.
        final doneSet = Set<String>.from(ref.read(delayTestingProvider));
        doneSet.removeAll(proxyNames);
        ref.read(delayTestingProvider.notifier).state = doneSet;
      }
    } else {
      // Mock: test sequentially
      for (final name in proxyNames) {
        await testDelay(name);
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  // Treat a group-test result as "all timed out" when at least 3 of the
  // requested nodes came back with delay <= 0. The floor of 3 avoids
  // false positives on truly tiny groups (a 2-proxy DIRECT/REJECT setup
  // where 0 is legitimate) while still catching the real failure mode
  // where every proxy in a group reports 0. Dropped from 5 so that
  // user-curated groups (e.g. 3-4 hand-picked nodes) also get the
  // auto-recovery path after a reconnect.
  bool _isAllTimeout(Map<String, dynamic> results, List<String> proxyNames) {
    if (proxyNames.length < 3) return false;
    var checked = 0;
    var timedOut = 0;
    for (final name in proxyNames) {
      final v = results[name];
      int? delay;
      if (v is int) {
        delay = v;
      } else if (v is Map) {
        delay = (v['delay'] as num?)?.toInt();
      }
      if (delay == null) continue;
      checked++;
      if (delay <= 0) timedOut++;
    }
    if (checked < 3) return false;
    return timedOut / checked >= 0.9;
  }
}
