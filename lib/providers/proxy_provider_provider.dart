import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proxy_provider.dart';
import '../services/core_manager.dart';

final proxyProvidersProvider =
    StateNotifierProvider<ProxyProvidersNotifier, List<ProxyProviderInfo>>(
  (ref) => ProxyProvidersNotifier(),
);

class ProxyProvidersNotifier
    extends StateNotifier<List<ProxyProviderInfo>> {
  ProxyProvidersNotifier() : super([]);

  Future<void> refresh() async {
    final manager = CoreManager.instance;
    if (manager.isMockMode) return;

    try {
      final data = await manager.api.getProxyProviders();
      final providersMap =
          data['providers'] as Map<String, dynamic>? ?? {};
      final list = <ProxyProviderInfo>[];
      for (final entry in providersMap.entries) {
        final info = entry.value as Map<String, dynamic>;
        // Skip default provider
        if (info['vehicleType'] == 'Compatible') continue;
        list.add(ProxyProviderInfo.fromJson(entry.key, info));
      }
      state = list;
    } catch (_) {
      return;
    }
  }

  Future<bool> update(String name) async {
    try {
      return await CoreManager.instance.api.updateProxyProvider(name);
    } catch (_) {
      return false;
    }
  }

  Future<void> healthCheck(String name) async {
    try {
      await CoreManager.instance.api.healthCheckProvider(name);
    } catch (_) {}
  }
}
