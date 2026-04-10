import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../providers/core_provider.dart';
import '../../nodes/providers/nodes_providers.dart';

class ExitIpInfo {
  const ExitIpInfo({
    required this.ip,
    this.countryCode = '',
    this.country = '',
    this.city = '',
    this.isp = '',
  });

  final String ip;
  final String countryCode;
  final String country;
  final String city;
  final String isp;

  String get flagEmoji {
    if (countryCode.length != 2) return '';
    return countryCode.toUpperCase().runes
        .map((r) => String.fromCharCode(r - 0x41 + 0x1F1E6))
        .join();
  }

  String get locationLine {
    if (country.isEmpty) return '';
    if (city.isEmpty || city == country) return country;
    return '$country · $city';
  }
}

/// Fetches the exit IP by making an HTTP request through mihomo's mixed-port:
///   - **rule/global**: route through `127.0.0.1:mixedPort` → IP echo service
///   - **direct**: fetch local public IP directly (no proxy)
///
/// This approach works regardless of proxy type, group structure, or whether
/// proxy-provider nodes expose a `server` field in the API.
final exitIpInfoProvider = FutureProvider.autoDispose<ExitIpInfo?>((ref) async {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return null;

  // Mock mode: no real proxy — fetch local public IP directly (same as direct mode)
  if (CoreManager.instance.isMockMode) {
    return _fetchPublicIp();
  }

  // Watch routing mode so the IP refreshes when user switches mode
  final routingMode = ref.watch(routingModeProvider);

  try {
    if (routingMode == 'direct') {
      debugPrint('[ExitIP] direct mode → fetching local IP');
      return _fetchPublicIp();
    }

    // Rule / Global mode → fetch IP through mihomo's mixed-port proxy
    final port = CoreManager.instance.mixedPort;
    debugPrint('[ExitIP] mode=$routingMode, fetching via proxy 127.0.0.1:$port');
    return _fetchIpViaProxy(port);
  } catch (e) {
    debugPrint('[ExitIP] unexpected error: $e');
    return null;
  }
});

/// Fetch IP via mihomo's mixed-port proxy → IP echo service.
/// This gets the actual exit IP regardless of proxy type or API limitations.
Future<ExitIpInfo?> _fetchIpViaProxy(int port) async {
  final client = HttpClient();
  client.findProxy = (uri) => 'PROXY 127.0.0.1:$port';
  client.connectionTimeout = const Duration(seconds: 10);
  client.badCertificateCallback = (_, __, ___) => true;
  try {
    final req = await client.getUrl(Uri.parse('https://api.ip.sb/geoip'));
    req.headers.set('User-Agent', 'YueLink/1.0');
    req.headers.set('Accept', 'application/json');
    final resp = await req.close().timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      debugPrint('[ExitIP] proxy fetch HTTP ${resp.statusCode}');
      return null;
    }
    final body = await resp.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    return ExitIpInfo(
      ip: data['ip'] as String? ?? '',
      countryCode: (data['country_code'] as String? ?? '').toUpperCase(),
      country: data['country'] as String? ?? '',
      city: data['city'] as String? ?? '',
      isp: data['isp'] as String? ?? '',
    );
  } catch (e) {
    debugPrint('[ExitIP] proxy fetch failed: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Fetch the local public IP directly (no proxy) for direct mode.
Future<ExitIpInfo> _fetchPublicIp() async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 5);
  client.badCertificateCallback = (_, __, ___) => true;
  try {
    final req = await client.getUrl(Uri.parse('https://api.ip.sb/geoip'));
    req.headers.set('User-Agent', 'YueLink/1.0');
    req.headers.set('Accept', 'application/json');
    final resp = await req.close().timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) {
      debugPrint('[ExitIP] public IP fetch HTTP ${resp.statusCode}');
      return const ExitIpInfo(ip: 'DIRECT');
    }
    final body = await resp.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    return ExitIpInfo(
      ip: data['ip'] as String? ?? 'DIRECT',
      countryCode: (data['country_code'] as String? ?? '').toUpperCase(),
      country: data['country'] as String? ?? '',
      city: data['city'] as String? ?? '',
      isp: data['isp'] as String? ?? '',
    );
  } catch (e) {
    debugPrint('[ExitIP] public IP fetch failed: $e');
    return const ExitIpInfo(ip: 'DIRECT');
  } finally {
    client.close(force: true);
  }
}

// ── AI Unlock Detection ─────────────────────────────────────────────────────

/// Common AI proxy group name patterns.
const _aiGroupPatterns = ['ai', 'chatgpt', 'openai', 'gpt', 'gemini', '人工智能'];

class AiUnlockInfo {
  final String groupName;
  final String nodeName;
  final bool? unlocked; // null = testing
  const AiUnlockInfo({
    required this.groupName,
    required this.nodeName,
    this.unlocked,
  });
}

/// Finds the AI proxy group and its selected node.
final aiGroupInfoProvider = Provider<AiUnlockInfo?>((ref) {
  final groups = ref.watch(proxyGroupsProvider);
  if (groups.isEmpty) return null;

  for (final g in groups) {
    final lower = g.name.toLowerCase();
    if (_aiGroupPatterns.any((p) => lower.contains(p))) {
      return AiUnlockInfo(
        groupName: g.name,
        nodeName: g.now,
      );
    }
  }
  return null;
});

/// Tests if AI services are accessible through the proxy.
/// Makes a lightweight request to chat.openai.com through mihomo's mixed-port.
/// Any successful response (even 403/401) means the endpoint is reachable.
final aiUnlockTestProvider = FutureProvider.autoDispose<AiUnlockInfo?>((ref) async {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return null;

  final aiInfo = ref.watch(aiGroupInfoProvider);
  if (aiInfo == null) return null;

  if (CoreManager.instance.isMockMode) {
    // Mock: simulate unlock
    return AiUnlockInfo(
      groupName: aiInfo.groupName,
      nodeName: aiInfo.nodeName,
      unlocked: true,
    );
  }

  final port = CoreManager.instance.mixedPort;
  try {
    final client = HttpClient();
    client.findProxy = (uri) => 'PROXY 127.0.0.1:$port';
    client.connectionTimeout = const Duration(seconds: 8);
    client.badCertificateCallback = (_, __, ___) => true;
    try {
      final req = await client.getUrl(
          Uri.parse('https://chat.openai.com/cdn-cgi/trace'));
      req.headers.set('User-Agent', 'YueLink/1.0');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      await resp.drain<void>();
      // Any HTTP response (200, 403, etc.) means the node can reach OpenAI
      final ok = resp.statusCode > 0 && resp.statusCode < 500;
      return AiUnlockInfo(
        groupName: aiInfo.groupName,
        nodeName: aiInfo.nodeName,
        unlocked: ok,
      );
    } finally {
      client.close(force: true);
    }
  } catch (e) {
    debugPrint('[AiUnlock] test failed: $e');
    return AiUnlockInfo(
      groupName: aiInfo.groupName,
      nodeName: aiInfo.nodeName,
      unlocked: false,
    );
  }
});

// ── DNS Leak Test ──────────────────────────────────────────────────────────

class DnsLeakResult {
  final bool leaked;
  final List<String> resolverIps;
  final String? error;
  const DnsLeakResult({
    required this.leaked,
    this.resolverIps = const [],
    this.error,
  });
}

/// Test for DNS leaks by resolving a unique domain through mihomo's DNS
/// and comparing with direct system DNS resolution.
/// If system DNS resolves differently from mihomo DNS, DNS is leaking.
final dnsLeakTestProvider =
    FutureProvider.autoDispose<DnsLeakResult>((ref) async {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) {
    return const DnsLeakResult(leaked: false, error: 'Core not running');
  }

  final manager = CoreManager.instance;
  if (manager.isMockMode) {
    return const DnsLeakResult(leaked: false);
  }

  try {
    // Query a well-known domain through mihomo's internal DNS
    final mihomoResult =
        await manager.api.queryDns('whoami.akamai.net', type: 'A');
    final mihomoAnswers = (mihomoResult['Answer'] as List?)
            ?.map((a) => (a as Map)['data'] as String? ?? '')
            .where((ip) => ip.isNotEmpty)
            .toList() ??
        [];

    // Query the same domain via system DNS (bypassing mihomo)
    final systemResult = await InternetAddress.lookup('whoami.akamai.net');
    final systemIps = systemResult.map((a) => a.address).toList();

    // If mihomo answers with fake-ip range (198.18.x.x), DNS is properly
    // intercepted — no leak. If system DNS returns real IPs that don't
    // match mihomo's answers, DNS is leaking.
    final hasFakeIp =
        mihomoAnswers.any((ip) => ip.startsWith('198.18.'));
    if (hasFakeIp) {
      return DnsLeakResult(leaked: false, resolverIps: mihomoAnswers);
    }

    // Compare: if system IPs differ from mihomo IPs, there's a leak
    final mihomoSet = mihomoAnswers.toSet();
    final systemSet = systemIps.toSet();
    final leaked = systemSet.difference(mihomoSet).isNotEmpty;

    return DnsLeakResult(
      leaked: leaked,
      resolverIps: [...mihomoAnswers, ...systemIps].toSet().toList(),
    );
  } catch (e) {
    debugPrint('[DnsLeak] test error: $e');
    return DnsLeakResult(leaked: false, error: e.toString().split('\n').first);
  }
});
