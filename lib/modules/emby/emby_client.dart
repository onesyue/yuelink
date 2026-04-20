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
    final hc = HttpClient();
    hc.badCertificateCallback = (cert, host, port) => true;
    // Emby 流量始终走代理（需要通过代理节点访问 Emby 服务器）
    final mixedPort = CoreManager.instance.mixedPort;
    if (mixedPort > 0) {
      hc.findProxy = (uri) => 'PROXY 127.0.0.1:$mixedPort';
    }
    hc.connectionTimeout = const Duration(seconds: 8);
    _inner = IOClient(hc);
  }

  Map<String, String> get _headers => {
        'X-Emby-Authorization': 'MediaBrowser Client="YueLink", Device="Flutter", '
            'DeviceId="yuelink-flutter", Version="1.0", Token="$accessToken"',
        'Accept': 'application/json',
      };

  /// GET JSON from Emby REST API. Retries up to 2 times on failure.
  Future<Map<String, dynamic>> get(String path,
      [Map<String, String>? params]) async {
    final uri = Uri.parse('$serverUrl$path').replace(queryParameters: {
      if (params != null) ...params,
    });
    Exception? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final resp = await _inner
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          return jsonDecode(resp.body) as Map<String, dynamic>;
        }
        lastErr = Exception('HTTP ${resp.statusCode}');
      } catch (e) {
        lastErr = e is Exception ? e : Exception('$e');
        if (attempt < 2) await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    throw lastErr!;
  }

  /// Direct-play stream URL (Static=true — Infuse / Glacier pattern).
  String streamUrl(String itemId) =>
      '$serverUrl/Videos/$itemId/stream?Static=true&api_key=$accessToken';

  /// Poster / thumbnail image URL.
  String imageUrl(String itemId, {int width = 480}) =>
      '$serverUrl/emby/Items/$itemId/Images/Primary'
      '?fillWidth=$width&quality=90&api_key=$accessToken';

  /// External subtitle stream URL from Emby.
  String subtitleUrl(String itemId, int streamIndex, {String format = 'srt'}) =>
      '$serverUrl/Videos/$itemId/Subtitles/$streamIndex/Stream.$format'
      '?api_key=$accessToken';

  /// 16:9 backdrop image URL.
  String backdropUrl(String itemId, {int width = 1920}) =>
      '$serverUrl/emby/Items/$itemId/Images/Backdrop'
      '?maxWidth=$width&quality=90&api_key=$accessToken';

  /// POST to Emby REST API. Errors are silently ignored (fire-and-forget for
  /// progress reporting).
  Future<void> post(String path, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$serverUrl$path');
      await _inner
          .post(uri,
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

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
      stalePeriod: const Duration(days: 3),
      maxNrOfCacheObjects: 150,
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

  /// Set true for landscape backdrops (16:9) — controls memCache aspect ratio.
  /// Posters default to portrait (2:3).
  final bool isBackdrop;

  const EmbyImage({
    super.key,
    required this.api,
    required this.itemId,
    this.fit = BoxFit.cover,
    this.placeholder = const SizedBox.shrink(),
    this.width = 200,
    this.url,
    this.isBackdrop = false,
  });

  // ── Decoded bitmap memory caps ────────────────────────────────────
  // Limits the Flutter image cache footprint per image.
  // physicalWidth is clamped so a single full-screen backdrop doesn't
  // consume 30+ MB as a decoded bitmap (2400×3600 @3× DPI, RGBA8888).
  //
  //   Poster  (2:3 portrait): max 720 × 1080 × 4 = ~2.9 MB each
  //   Backdrop (16:9 landscape): max 1280 × 720 × 4 = ~3.5 MB each
  static const _kMaxPosterWidth   = 720;
  static const _kMaxBackdropWidth = 1280;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
    final physicalWidth = (width * dpr).toInt();

    // Cap the decoded-bitmap size written into Flutter's image cache.
    final int memW;
    final int memH;
    if (isBackdrop) {
      memW = physicalWidth.clamp(0, _kMaxBackdropWidth);
      memH = memW * 9 ~/ 16; // 16:9 landscape
    } else {
      memW = physicalWidth.clamp(0, _kMaxPosterWidth);
      memH = memW * 3 ~/ 2;  // 2:3 portrait poster
    }

    return CachedNetworkImage(
      imageUrl: url ?? api.imageUrl(itemId, width: physicalWidth),
      cacheManager: EmbyClient.imageCacheManager,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      memCacheWidth: memW,
      memCacheHeight: memH,
      placeholder: (_, _) => Container(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1C1C1E)
            : const Color(0xFFE4E4E7), // YLColors.zinc200
      ),
      errorWidget: (_, _, _) => placeholder,
    );
  }
}
