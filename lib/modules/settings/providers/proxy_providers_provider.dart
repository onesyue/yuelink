import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/proxy_provider.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../infrastructure/repositories/proxy_repository.dart';

final proxyProvidersProvider =
    NotifierProvider<ProxyProvidersNotifier, List<ProxyProviderInfo>>(
  ProxyProvidersNotifier.new,
);

class ProxyProvidersNotifier extends Notifier<List<ProxyProviderInfo>> {
  @override
  List<ProxyProviderInfo> build() => [];

  ProxyRepository get _repo => ref.read(proxyRepositoryProvider);

  Future<void> refresh() async {
    if (CoreManager.instance.isMockMode) return;

    try {
      final data = await _repo.getProxyProviders();
      final providersMap =
          data['providers'] as Map<String, dynamic>? ?? {};
      final list = <ProxyProviderInfo>[];
      for (final entry in providersMap.entries) {
        final info = entry.value as Map<String, dynamic>;
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
      return await _repo.updateProxyProvider(name);
    } catch (_) {
      return false;
    }
  }

  Future<void> healthCheck(String name) async {
    try {
      await _repo.healthCheckProvider(name);
    } catch (_) {}
  }
}
