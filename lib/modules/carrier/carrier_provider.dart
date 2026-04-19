import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/settings_service.dart';
import '../../infrastructure/datasources/yueops_api.dart';
import '../nodes/providers/nodes_providers.dart';
import '../../shared/event_log.dart';
import '../yue_auth/providers/yue_auth_providers.dart';

// ── YueOps API provider ─────────────────────────────────────────────────────

import '../../constants.dart';

final yueOpsApiProvider = Provider<YueOpsApi>((ref) {
  return YueOpsApi(baseUrl: AppConstants.yueOpsBaseUrl);
});

// ── Carrier state ───────────────────────────────────────────────────────────

class CarrierState {
  final String? carrier; // ct, cu, cm, or null
  final String carrierName;
  final String? recommendedNodeId;
  final String sniDomain;
  final String sniStatus;
  final DateTime? lastChecked;

  const CarrierState({
    this.carrier,
    this.carrierName = '',
    this.recommendedNodeId,
    this.sniDomain = '',
    this.sniStatus = 'unknown',
    this.lastChecked,
  });

  CarrierState copyWith({
    Object? carrier = _sentinel,
    String? carrierName,
    Object? recommendedNodeId = _sentinel,
    String? sniDomain,
    String? sniStatus,
    Object? lastChecked = _sentinel,
  }) {
    return CarrierState(
      carrier: carrier == _sentinel ? this.carrier : carrier as String?,
      carrierName: carrierName ?? this.carrierName,
      recommendedNodeId: recommendedNodeId == _sentinel
          ? this.recommendedNodeId
          : recommendedNodeId as String?,
      sniDomain: sniDomain ?? this.sniDomain,
      sniStatus: sniStatus ?? this.sniStatus,
      lastChecked: lastChecked == _sentinel
          ? this.lastChecked
          : lastChecked as DateTime?,
    );
  }

  static const _sentinel = Object();

  bool get isDetected => carrier != null && carrier!.isNotEmpty;
  bool get isSniHealthy => sniStatus == 'healthy';
}

// ── Carrier notifier ────────────────────────────────────────────────────────

final carrierProvider =
    NotifierProvider<CarrierNotifier, CarrierState>(
  CarrierNotifier.new,
);

class CarrierNotifier extends Notifier<CarrierState> {
  Timer? _pollingTimer;
  bool _detecting = false;
  bool _disposed = false;
  final Completer<void> _cacheLoaded = Completer<void>();

  @override
  CarrierState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _pollingTimer?.cancel();
    });
    _loadCached();
    return const CarrierState();
  }

  /// Polling interval for SNI status checks.
  static const _pollInterval = Duration(minutes: 30);

  /// Load cached carrier info from settings.
  Future<void> _loadCached() async {
    try {
      final carrier = await SettingsService.get<String>('detectedCarrier');
      final carrierName =
          await SettingsService.get<String>('detectedCarrierName') ?? '';
      final sniDomain =
          await SettingsService.get<String>('cachedSniDomain') ?? '';
      if (carrier != null) {
        if (_disposed) return;
        state = CarrierState(
          carrier: carrier,
          carrierName: carrierName,
          sniDomain: sniDomain,
        );
      }
    } finally {
      _cacheLoaded.complete();
    }
  }

  /// Detect carrier by fetching the user's real (direct) public IP,
  /// then querying YueOps for ASN-based carrier identification.
  ///
  /// Uses a direct HTTP request (no proxy) to get the real ISP IP.
  Future<void> detectCarrier() async {
    await _cacheLoaded.future;
    if (_detecting) return;
    _detecting = true;
    try {
      final oldCarrier = state.carrier;
      final api = ref.read(yueOpsApiProvider);
      // Step 1: Get user's real IP (direct, bypassing proxy)
      final realIp = await _fetchRealIp();
      if (realIp == null) {
        debugPrint('[Carrier] Could not fetch real IP');
        return;
      }

      // Step 2: Parallel — detect carrier + fetch config
      final results = await Future.wait([
        api.detectCarrier(realIp),
        api.getConfig(),
      ]);
      final carrierInfo = results[0] as CarrierInfo;
      final config = results[1] as ClientConfig;

      if (_disposed) return;
      state = CarrierState(
        carrier: carrierInfo.carrier,
        carrierName: carrierInfo.carrierName,
        recommendedNodeId: carrierInfo.recommendedNodeId,
        sniDomain: config.sniDomain,
        sniStatus: config.sniStatus,
        lastChecked: DateTime.now(),
      );

      // Cache to settings
      await SettingsService.set('detectedCarrier', carrierInfo.carrier ?? '');
      await SettingsService.set(
          'detectedCarrierName', carrierInfo.carrierName);
      await SettingsService.set('cachedSniDomain', config.sniDomain);

      EventLog.write(
          '[Carrier] ip=$realIp detected=${carrierInfo.carrier} sni=${config.sniDomain} status=${config.sniStatus}');

      // Auto-select carrier-optimized proxy node only on first detection
      // (not when carrier is already known). This prevents overriding the
      // user's manual proxy choice on every connect.
      final isFirstDetection = oldCarrier == null || oldCarrier.isEmpty;
      if (carrierInfo.isDetected && isFirstDetection) {
        _autoSelectCarrierNode(carrierInfo.carrier!);
      }
    } catch (e) {
      debugPrint('[Carrier] Detection failed: $e');
    } finally {
      _detecting = false;
    }
  }

  // ── Carrier keyword mapping for proxy node name matching ──────────────────

  static const _carrierKeywords = <String, List<String>>{
    'ct': ['电信', 'CT', 'Telecom', 'telecom'],
    'cu': ['联通', 'CU', 'Unicom', 'unicom'],
    'cm': ['移动', 'CM', 'CMCC', 'Mobile', 'mobile'],
  };

  /// Auto-select the best proxy node for the detected carrier.
  ///
  /// Searches all Selector-type proxy groups for nodes whose names
  /// contain carrier keywords (e.g., "电信", "CT", "联通").
  /// Only switches if the group has a carrier-specific node and it's
  /// not already selected.
  Future<void> _autoSelectCarrierNode(String carrier) async {
    final keywords = _carrierKeywords[carrier];
    if (keywords == null) return;

    final groups = ref.read(proxyGroupsProvider);
    final notifier = ref.read(proxyGroupsProvider.notifier);

    for (final group in groups) {
      // Only auto-select in Selector groups (user-switchable)
      if (group.type != 'Selector') continue;

      // Find a carrier-matching node in this group
      String? matchingNode;
      for (final nodeName in group.all) {
        for (final keyword in keywords) {
          if (nodeName.contains(keyword)) {
            matchingNode = nodeName;
            break;
          }
        }
        if (matchingNode != null) break;
      }

      // Skip if no match or already selected
      if (matchingNode == null || group.now == matchingNode) continue;

      final ok = await notifier.changeProxy(group.name, matchingNode);
      if (ok) {
        EventLog.write(
            '[Carrier] Auto-selected "$matchingNode" in group "${group.name}" for $carrier');
      }
    }
  }

  /// Fetch the user's real public IP directly (no proxy).
  /// This returns the ISP-assigned IP, which is what we need for
  /// carrier detection (CT/CU/CM).
  static Future<String?> _fetchRealIp() async {
    final client = HttpClient();
    client.findProxy = (uri) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse('https://api.ip.sb/ip'));
      req.headers.set('User-Agent', 'YueLink/1.0');
      final resp = await req.close().timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      return body.trim();
    } catch (e) {
      debugPrint('[Carrier] Real IP fetch failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Start periodic SNI polling.
  ///
  /// Checks YueOps every 30 minutes for SNI domain changes.
  /// If domain changed, returns true (caller should trigger subscription refresh).
  ///
  /// Pass [immediate]: true to also trigger a poll right now. Default is
  /// false because callers that start polling at app boot usually have
  /// already called [detectCarrier], which fetches the same `/config`
  /// endpoint; running an eager poll duplicated that in-flight request.
  void startPolling({bool immediate = false}) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollInterval, (_) => _pollAndRefresh());
    if (immediate) _pollAndRefresh();
  }

  /// Poll SNI and auto-refresh subscription if domain changed.
  Future<void> _pollAndRefresh() async {
    final changed = await _pollSni();
    if (changed) {
      // SNI domain rotated — trigger subscription re-download silently
      try {
        await ref.read(authProvider.notifier).syncSubscription();
      } catch (e) {
        debugPrint('[Carrier] Subscription refresh after SNI change failed: $e');
      }
    }
  }

  /// Stop polling (e.g., on logout).
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Single SNI poll. Returns true if SNI domain changed.
  Future<bool> _pollSni() async {
    final api = ref.read(yueOpsApiProvider);
    try {
      final config = await api.getConfig();
      // Guard BEFORE touching state — Notifier.state getter throws on a
      // disposed notifier, so the previous `if (_disposed) return` that
      // sat between state reads and writes was already too late.
      if (_disposed) return false;
      final oldDomain = state.sniDomain;
      final newDomain = config.sniDomain;

      state = state.copyWith(
        sniDomain: newDomain,
        sniStatus: config.sniStatus,
        lastChecked: DateTime.now(),
      );
      await SettingsService.set('cachedSniDomain', newDomain);

      if (oldDomain.isNotEmpty &&
          newDomain.isNotEmpty &&
          oldDomain != newDomain) {
        EventLog.write(
            '[Carrier] SNI changed: $oldDomain → $newDomain, triggering refresh');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Carrier] SNI poll failed: $e');
      return false;
    }
  }

  /// Force check SNI and return whether it changed.
  Future<bool> checkSni() => _pollSni();

}
