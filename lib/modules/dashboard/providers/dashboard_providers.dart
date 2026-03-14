import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../providers/core_provider.dart';

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

/// Fetches the exit IP of the currently selected node in the FIRST proxy group.
///
/// Flow:
///   1. GET /proxies → find first real user group (ordered by GLOBAL.all)
///   2. Follow .now chain recursively to reach a leaf proxy with a `server` field
///   3. DNS-resolve the server hostname → IPv4 address
///   4. Call api.ip.sb/geoip/{ip} (direct, no proxy) for country/city/ISP
final exitIpInfoProvider = FutureProvider.autoDispose<ExitIpInfo?>((ref) async {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return null;

  try {
    // ── Step 1: get proxy data from mihomo ─────────────────────────
    final api = CoreManager.instance.api;
    final Map<String, dynamic> proxiesData;
    try {
      proxiesData = await api.getProxies().timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
    final proxiesMap =
        proxiesData['proxies'] as Map<String, dynamic>? ?? {};

    // ── Step 2: find the first real user group ─────────────────────
    // Groups are ordered by GLOBAL's `all` list.
    final globalAll =
        (proxiesMap['GLOBAL']?['all'] as List?)?.cast<String>() ?? [];

    const builtins = {'GLOBAL', 'DIRECT', 'REJECT', 'PASS'};

    String? firstGroupName;
    for (final name in globalAll) {
      if (builtins.contains(name)) continue;
      final info = proxiesMap[name];
      if (info is Map && info.containsKey('all')) {
        firstGroupName = name;
        break;
      }
    }
    if (firstGroupName == null) return null;

    // ── Step 3: resolve selected node → leaf proxy server ──────────
    String? serverHost;
    String? currentName = firstGroupName;

    for (int depth = 0; depth < 6; depth++) {
      if (currentName == null) break;
      final info = proxiesMap[currentName];
      if (info is! Map<String, dynamic>) break;

      final server = info['server'] as String?;
      if (server != null && server.isNotEmpty) {
        // Leaf proxy node — has a server address
        serverHost = server;
        break;
      }

      // It's a group: follow `now` → selected node
      final now = info['now'] as String?;
      if (now != null && now.isNotEmpty && !builtins.contains(now)) {
        currentName = now;
        continue;
      }

      // `now` is missing/empty/built-in: fall back to first item in `all`
      final all = (info['all'] as List?)?.cast<String>();
      if (all != null && all.isNotEmpty) {
        final candidate = all.firstWhere(
          (n) => !builtins.contains(n),
          orElse: () => '',
        );
        if (candidate.isNotEmpty) {
          currentName = candidate;
          continue;
        }
      }
      break;
    }

    if (serverHost == null) return null;

    // ── Step 4: resolve hostname → IP ─────────────────────────────
    String ipString;
    if (_isIpAddress(serverHost)) {
      ipString = serverHost;
    } else {
      try {
        final addresses = await InternetAddress.lookup(serverHost)
            .timeout(const Duration(seconds: 5));
        // Prefer IPv4
        final ipv4 = addresses
            .where((a) => a.type == InternetAddressType.IPv4)
            .toList();
        ipString = ipv4.isNotEmpty
            ? ipv4.first.address
            : (addresses.isNotEmpty ? addresses.first.address : serverHost);
      } catch (_) {
        ipString = serverHost; // DNS failed — use hostname as fallback label
      }
    }

    // ── Step 5: geoip lookup (direct, not through proxy) ──────────
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    client.badCertificateCallback = (_, __, ___) => true;

    try {
      final req =
          await client.getUrl(Uri.parse('https://api.ip.sb/geoip/$ipString'));
      req.headers.set('User-Agent', 'YueLink/1.0');
      req.headers.set('Accept', 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final body = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final ip = data['ip'] as String? ?? ipString;
      client.close(force: false);
      return ExitIpInfo(
        ip: ip,
        countryCode: (data['country_code'] as String? ?? '').toUpperCase(),
        country: data['country'] as String? ?? '',
        city: data['city'] as String? ?? '',
        isp: data['isp'] as String? ?? '',
      );
    } catch (_) {
      client.close(force: false);
      return ExitIpInfo(ip: ipString);
    }
  } catch (_) {
    return null;
  }
});

bool _isIpAddress(String s) {
  // IPv4
  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(s)) return true;
  // IPv6 (simplified)
  if (s.contains(':')) return true;
  return false;
}

// Keep legacy alias so any remaining references compile
final proxyServerIpProvider = exitIpInfoProvider;
