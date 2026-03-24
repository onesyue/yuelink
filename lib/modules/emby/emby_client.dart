import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/kernel/core_manager.dart';

/// Shared Emby HTTP client — reuses TCP connections (keep-alive) to avoid
/// repeated TLS handshakes through the mihomo proxy chain.
///
/// One instance per page (create in initState, close in dispose).
class EmbyClient {
  final String serverUrl;
  final String accessToken;
  final String userId;
  late final http.Client _inner;

  EmbyClient({
    required this.serverUrl,
    required this.accessToken,
    required this.userId,
  }) {
    final mixedPort = CoreManager.instance.mixedPort;
    final hc = HttpClient();
    hc.badCertificateCallback = (cert, host, port) => true;
    if (mixedPort > 0) {
      hc.findProxy = (uri) => 'PROXY 127.0.0.1:$mixedPort';
    }
    _inner = IOClient(hc);
  }

  Map<String, String> get _headers => {
        'X-Emby-Authorization': 'MediaBrowser Client="YueLink", Device="Flutter", '
            'DeviceId="yuelink-flutter", Version="1.0", Token="$accessToken"',
        'Accept': 'application/json',
      };

  /// GET JSON from Emby REST API. Throws on error.
  Future<Map<String, dynamic>> get(String path,
      [Map<String, String>? params]) async {
    final uri = Uri.parse('$serverUrl$path').replace(queryParameters: {
      if (params != null) ...params,
    });
    final resp = await _inner
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Direct-play stream URL (Static=true — Infuse / Glacier pattern).
  String streamUrl(String itemId) =>
      '$serverUrl/Videos/$itemId/stream?Static=true&api_key=$accessToken';

  /// Poster / thumbnail image URL.
  String imageUrl(String itemId, {int width = 300}) =>
      '$serverUrl/emby/Items/$itemId/Images/Primary'
      '?fillWidth=$width&quality=90&api_key=$accessToken';

  /// External subtitle stream URL from Emby.
  String subtitleUrl(String itemId, int streamIndex, {String format = 'srt'}) =>
      '$serverUrl/Videos/$itemId/Subtitles/$streamIndex/Stream.$format'
      '?api_key=$accessToken';

  /// 16:9 backdrop image URL.
  String backdropUrl(String itemId, {int width = 800}) =>
      '$serverUrl/emby/Items/$itemId/Images/Backdrop'
      '?maxWidth=$width&quality=90&api_key=$accessToken';

  void close() => _inner.close();

  // ── Proxy-aware image cache (shared across all pages) ─────────────────

  static CacheManager? _cacheManager;
  static int _cachedPort = 0;

  /// Disk + memory cache that routes image downloads through mihomo proxy.
  /// Rebuilds automatically when the proxy port changes.
  static CacheManager get imageCacheManager {
    final mixedPort = CoreManager.instance.mixedPort;
    if (_cacheManager != null && _cachedPort == mixedPort) return _cacheManager!;
    _cachedPort = mixedPort;
    final hc = HttpClient();
    hc.badCertificateCallback = (cert, host, port) => true;
    if (mixedPort > 0) {
      hc.findProxy = (uri) => 'PROXY 127.0.0.1:$mixedPort';
    }
    _cacheManager = CacheManager(Config(
      'emby_images',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 500,
      fileService: HttpFileService(httpClient: IOClient(hc)),
    ));
    return _cacheManager!;
  }
}

// ── Proxy-aware image widget ─────────────────────────────────────────────────

/// Emby image that loads through the proxied [CacheManager].
/// Disk-cached + memory-cached + fade-in animation.
class EmbyImage extends StatelessWidget {
  final EmbyClient api;
  final String itemId;
  final BoxFit fit;
  final Widget placeholder;
  final int width;

  /// [url] overrides the default imageUrl (e.g. for backdrops).
  final String? url;

  const EmbyImage({
    super.key,
    required this.api,
    required this.itemId,
    this.fit = BoxFit.cover,
    this.placeholder = const SizedBox.shrink(),
    this.width = 200,
    this.url,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url ?? api.imageUrl(itemId, width: width),
      cacheManager: EmbyClient.imageCacheManager,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      memCacheHeight: width ~/ 2 * 3, // ~aspect ratio 2:3
      placeholder: (_, __) => Container(color: const Color(0xFF1C1C1E)),
      errorWidget: (_, __, ___) => placeholder,
    );
  }
}
