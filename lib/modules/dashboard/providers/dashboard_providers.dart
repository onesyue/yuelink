import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../providers/proxy_provider.dart';

/// Derives the selected proxy node's server IP from the mihomo API.
/// Auto-updates whenever the selected proxy changes.
final proxyServerIpProvider = FutureProvider.autoDispose<String?>((ref) async {
  final groups = ref.watch(proxyGroupsProvider);
  if (groups.isEmpty) return null;
  try {
    final mainGroup = groups.firstWhere(
      (g) =>
          g.name == 'PROXIES' ||
          g.name == '节点选择' ||
          g.name == 'Proxy',
      orElse: () => groups.firstWhere(
        (g) => g.type == 'Selector',
        orElse: () => groups.first,
      ),
    );
    final nodeName = mainGroup.now;
    if (nodeName.isEmpty) return null;
    final api = CoreManager.instance.api;
    final info = await api.getProxy(nodeName);
    return info['server'] as String?;
  } catch (_) {
    return null;
  }
});
