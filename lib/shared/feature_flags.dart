import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/settings_service.dart';
import 'telemetry.dart';

/// Server-controlled feature flags with safe local defaults.
///
/// Flags let us ship code dark. A risky change lives behind
/// `FeatureFlags.I.boolFlag('risky_x')` and is enabled remotely for a
/// percentage of clients (server hashes anonymous `client_id` to a
/// stable 0-100 bucket). If telemetry shows startup_fail spike we
/// disable the flag and roll back in seconds — no redeploy.
class FeatureFlags {
  FeatureFlags._();
  static final FeatureFlags I = FeatureFlags._();

  static const _endpoint =
      'https://yue.yuebao.website/api/client/telemetry/flags';
  static const _refreshInterval = Duration(hours: 1);
  static const _httpTimeout = Duration(seconds: 5);
  static const _cacheKey = 'featureFlagsJson';

  // Canonical flag list — also serves as the offline default.
  static const Map<String, dynamic> _defaults = {
    'smart_node_recommend': false,
    'scene_presets': false,
    'onboarding_split': false,
    'auto_fallback': false,
    'nps_enabled': true,
    'telemetry_enabled_kill': false,
  };

  final Map<String, dynamic> _cache = Map.of(_defaults);
  Timer? _refreshTimer;
  DateTime? _lastRefresh;

  Future<void> init() async {
    final cached = await SettingsService.get<String>(_cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        _cache.addAll(decoded);
      } catch (e) {
        debugPrint('[FeatureFlags] cache decode failed: $e');
      }
    }
    unawaited(refresh());
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => refresh());
  }

  bool boolFlag(String key) {
    final v = _cache[key];
    return v is bool ? v : false;
  }

  String stringFlag(String key, {String fallback = ''}) {
    final v = _cache[key];
    return v is String ? v : fallback;
  }

  num numFlag(String key, {num fallback = 0}) {
    final v = _cache[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? fallback;
    return fallback;
  }

  DateTime? get lastRefresh => _lastRefresh;

  Future<void> refresh() async {
    final clientId = Telemetry.clientId;
    if (clientId.isEmpty) {
      debugPrint('[FeatureFlags] skip refresh: telemetry client_id not ready');
      return;
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = flagsUriForClientId(clientId);
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(_httpTimeout);
      if (resp.statusCode != 200) return;
      final body = await resp.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return;
      final flags = decoded['flags'];
      if (flags is! Map) return;
      _cache.addAll(Map<String, dynamic>.from(flags));
      await SettingsService.set(_cacheKey, jsonEncode(_cache));
      _lastRefresh = DateTime.now();
    } catch (e) {
      debugPrint('[FeatureFlags] refresh failed: $e');
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> snapshot() => Map<String, dynamic>.unmodifiable(_cache);

  @visibleForTesting
  static Uri flagsUriForClientId(String clientId) {
    return Uri.parse(
      _endpoint,
    ).replace(queryParameters: {'client_id': clientId});
  }
}

final featureFlagsProvider = Provider<FeatureFlags>((ref) => FeatureFlags.I);
