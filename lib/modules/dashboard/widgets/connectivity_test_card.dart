import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../theme.dart';

/// D-④ P4-4: Dashboard 连通性体检卡。
///
/// 6 个目标的轻量级 generate_204 / HEAD 探测,通过 mihomo 的 mixed-port
/// 出去 —— 用户能直观看见"是否真的能访问 GitHub / Google / Anthropic"。
///
/// 不依赖系统代理状态:每次都强制走 `127.0.0.1:<mixedPort>` HTTP CONNECT,
/// 即使用户在 systemProxy 模式还没把代理写进 OS 也能拿到结果。
class ConnectivityTestCard extends ConsumerStatefulWidget {
  const ConnectivityTestCard({super.key});

  @override
  ConsumerState<ConnectivityTestCard> createState() =>
      _ConnectivityTestCardState();
}

class _ConnectivityTestCardState extends ConsumerState<ConnectivityTestCard> {
  // ── Probe targets ───────────────────────────────────────────────
  // Hand-picked: 6 representative regions/clouds. Each probe endpoint
  // is small + cacheable + responds with a deterministic small body.
  static const _targets = <_ProbeTarget>[
    _ProbeTarget(
      name: 'Google',
      url: 'https://www.gstatic.com/generate_204',
      flag: '🇺🇸',
    ),
    _ProbeTarget(
      name: 'Cloudflare',
      url: 'https://www.cloudflare.com/cdn-cgi/trace',
      flag: '🌐',
    ),
    _ProbeTarget(
      name: 'GitHub',
      url: 'https://api.github.com/zen',
      flag: '🐙',
    ),
    _ProbeTarget(
      name: 'YouTube',
      url: 'https://www.youtube.com/generate_204',
      flag: '🎥',
    ),
    _ProbeTarget(
      name: 'Anthropic',
      url: 'https://www.anthropic.com/favicon.ico',
      flag: '🤖',
    ),
    _ProbeTarget(
      name: 'Apple',
      url: 'https://www.apple.com/library/test/success.html',
      flag: '🍎',
    ),
  ];

  final Map<String, _ProbeResult> _results = {};
  bool _running = false;

  Future<void> _runAll() async {
    if (_running) return;
    setState(() {
      _running = true;
      _results.clear();
    });

    final mixedPort = CoreManager.instance.mixedPort;
    // Run all 6 in parallel; each individual probe is bounded by its
    // own connection timeout, so total wall time ≈ slowest probe.
    await Future.wait(
      _targets.map((t) async {
        final result = await _probe(t, mixedPort);
        if (mounted) setState(() => _results[t.name] = result);
      }),
    );
    if (mounted) setState(() => _running = false);
  }

  Future<_ProbeResult> _probe(_ProbeTarget target, int mixedPort) async {
    // Dart HttpClient cascade-arrow-function parser bug — set each
    // property as a separate statement (CLAUDE.md `TLS / HTTP` § 5).
    final client = HttpClient();
    client.findProxy = (uri) => 'PROXY 127.0.0.1:$mixedPort';
    client.connectionTimeout = const Duration(seconds: 5);
    final stopwatch = Stopwatch()..start();
    try {
      final req = await client
          .headUrl(Uri.parse(target.url))
          .timeout(const Duration(seconds: 8));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      // Drain body to free socket; size is tiny.
      // ignore: unused_local_variable
      final _ = await resp.drain<void>();
      stopwatch.stop();
      // 2xx / 204 / 3xx all count as reachable. 4xx still means we
      // talked to the host, but mark them as warning for visibility.
      final ok = resp.statusCode >= 200 && resp.statusCode < 400;
      return _ProbeResult(
        ok: ok,
        latencyMs: stopwatch.elapsedMilliseconds,
        statusCode: resp.statusCode,
      );
    } on TimeoutException {
      stopwatch.stop();
      return const _ProbeResult(
        ok: false,
        error: 'timeout',
      );
    } catch (e) {
      stopwatch.stop();
      return _ProbeResult(
        ok: false,
        error: e.toString().split('\n').first,
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : YLColors.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(YLRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.network_check_rounded, size: 16, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '连通性体检',
                  style: YLText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              SizedBox(
                height: 28,
                child: TextButton(
                  onPressed: _running ? null : _runAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: _running
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          '测试',
                          style: YLText.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._targets.map((t) => _row(t, _results[t.name], fg, isDark)),
        ],
      ),
    );
  }

  Widget _row(_ProbeTarget t, _ProbeResult? r, Color fg, bool isDark) {
    Widget tail;
    if (r == null) {
      // Either not run yet, or running.
      if (_running) {
        tail = const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        );
      } else {
        tail = Text('—', style: YLText.caption.copyWith(color: fg));
      }
    } else if (r.ok) {
      tail = Text(
        '${r.latencyMs} ms',
        style: YLText.caption.copyWith(
          color: Colors.green.shade(isDark ? 300 : 700),
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    } else {
      tail = Text(
        r.error ?? 'HTTP ${r.statusCode}',
        style: YLText.caption.copyWith(
          color: isDark ? Colors.red.shade300 : Colors.red.shade700,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(t.flag, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.name,
              style: YLText.caption.copyWith(color: fg),
            ),
          ),
          tail,
        ],
      ),
    );
  }
}

class _ProbeTarget {
  final String name;
  final String url;
  final String flag;
  const _ProbeTarget({
    required this.name,
    required this.url,
    required this.flag,
  });
}

class _ProbeResult {
  final bool ok;
  final int? latencyMs;
  final int? statusCode;
  final String? error;
  const _ProbeResult({
    required this.ok,
    this.latencyMs,
    this.statusCode,
    this.error,
  });
}

extension _ColorShade on MaterialColor {
  Color shade(int weight) => this[weight] ?? this;
}
