import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Tests whether popular streaming/AI services are accessible via the proxy.
///
/// Sends HTTP requests through the local mixed-port proxy (127.0.0.1:proxyPort).
class UnlockTestService {
  UnlockTestService._();
  static final instance = UnlockTestService._();

  static const services = [
    UnlockService(
      id: 'netflix',
      name: 'Netflix',
      icon: '🎬',
      testUrl: 'https://www.netflix.com/title/70143836',
      blockedKeyword: 'not-available',
    ),
    UnlockService(
      id: 'chatgpt',
      name: 'ChatGPT',
      icon: '🤖',
      testUrl: 'https://chat.openai.com/',
      blockedKeyword: 'VPN',
    ),
    UnlockService(
      id: 'youtube',
      name: 'YouTube Premium',
      icon: '▶️',
      testUrl: 'https://www.youtube.com/premium',
      blockedKeyword: 'not available',
    ),
    UnlockService(
      id: 'disney',
      name: 'Disney+',
      icon: '🏰',
      testUrl: 'https://www.disneyplus.com/',
      blockedKeyword: 'unavailable',
    ),
    UnlockService(
      id: 'spotify',
      name: 'Spotify',
      icon: '🎵',
      testUrl: 'https://open.spotify.com/',
      blockedKeyword: 'not available',
    ),
    UnlockService(
      id: 'tiktok',
      name: 'TikTok',
      icon: '🎤',
      testUrl: 'https://www.tiktok.com/',
      blockedKeyword: 'unavailable',
    ),
    UnlockService(
      id: 'github',
      name: 'GitHub',
      icon: '🐙',
      testUrl: 'https://github.com/',
      blockedKeyword: '',
    ),
    UnlockService(
      id: 'google',
      name: 'Google',
      icon: '🔍',
      testUrl: 'https://www.google.com/generate_204',
      blockedKeyword: '',
    ),
  ];

  /// Test all services in parallel through [proxyPort].
  Future<Map<String, UnlockResult>> testAll({int proxyPort = 7890}) async {
    final results = <String, UnlockResult>{};
    await Future.wait(services.map((svc) async {
      results[svc.id] = await _test(svc, proxyPort: proxyPort);
    }));
    return results;
  }

  Future<UnlockResult> _test(UnlockService svc,
      {required int proxyPort}) async {
    final sw = Stopwatch()..start();
    try {
      final client = HttpClient();
      client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';

      final req = await client
          .getUrl(Uri.parse(svc.testUrl))
          .timeout(const Duration(seconds: 8));
      req.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (compatible; YueLink/1.0)');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      sw.stop();

      final latency = sw.elapsedMilliseconds;

      // Read a limited amount of body for keyword check
      String body = '';
      if (svc.blockedKeyword.isNotEmpty) {
        final bytes = <int>[];
        await for (final chunk in resp.take(1)) {
          bytes.addAll(chunk);
          if (bytes.length > 4096) break;
        }
        body = utf8.decode(bytes, allowMalformed: true);
      } else {
        resp.drain<void>();
      }

      client.close();

      if (resp.statusCode == 204) {
        return UnlockResult(status: UnlockStatus.unlocked, latencyMs: latency);
      }
      if (resp.statusCode >= 400) {
        return UnlockResult(status: UnlockStatus.blocked, latencyMs: latency);
      }
      if (svc.blockedKeyword.isNotEmpty &&
          body.toLowerCase().contains(svc.blockedKeyword.toLowerCase())) {
        return UnlockResult(status: UnlockStatus.blocked, latencyMs: latency);
      }
      return UnlockResult(status: UnlockStatus.unlocked, latencyMs: latency);
    } on TimeoutException {
      return const UnlockResult(status: UnlockStatus.timeout);
    } catch (_) {
      return const UnlockResult(status: UnlockStatus.error);
    }
  }
}

class UnlockService {
  final String id;
  final String name;
  final String icon;
  final String testUrl;
  final String blockedKeyword;

  const UnlockService({
    required this.id,
    required this.name,
    required this.icon,
    required this.testUrl,
    required this.blockedKeyword,
  });
}

enum UnlockStatus { unlocked, blocked, timeout, error, testing }

class UnlockResult {
  final UnlockStatus status;
  final int? latencyMs;
  const UnlockResult({required this.status, this.latencyMs});

  String get label {
    switch (status) {
      case UnlockStatus.unlocked:
        return latencyMs != null ? '可用 ${latencyMs}ms' : '可用';
      case UnlockStatus.blocked:
        return '被封锁';
      case UnlockStatus.timeout:
        return '超时';
      case UnlockStatus.error:
        return '错误';
      case UnlockStatus.testing:
        return '检测中...';
    }
  }
}
