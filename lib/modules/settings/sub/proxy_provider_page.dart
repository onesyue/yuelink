import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../i18n/app_strings.dart';
import '../../../domain/models/proxy_provider.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/widgets/yl_scaffold.dart';
import '../../../theme.dart';
import '../providers/proxy_providers_provider.dart';

class ProxyProviderPage extends ConsumerStatefulWidget {
  const ProxyProviderPage({super.key});

  @override
  ConsumerState<ProxyProviderPage> createState() => _ProxyProviderPageState();
}

class _ProxyProviderPageState extends ConsumerState<ProxyProviderPage> {
  final _updatingSet = <String>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(proxyProvidersProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final providers = ref.watch(proxyProvidersProvider);

    return YLLargeTitleScaffold(
      title: s.proxyProviderTitle,
      maxContentWidth: kYLSecondaryContentWidth,
      actions: [
        IconButton(
          icon: const Icon(Icons.rule_folder_rounded),
          tooltip: '刷新所有规则集',
          onPressed: _refreshAllRuleProviders,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: s.retry,
          onPressed: () => ref.read(proxyProvidersProvider.notifier).refresh(),
        ),
      ],
      onRefresh: () async {
        await ref.read(proxyProvidersProvider.notifier).refresh();
      },
      slivers: [
        if (providers.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(YLSpacing.xl),
                child: Text(
                  s.proxyProviderEmpty,
                  style: YLText.body.copyWith(
                    color: isDark ? YLColors.zinc500 : YLColors.zinc500,
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              YLSpacing.lg,
              YLSpacing.sm,
              YLSpacing.lg,
              YLSpacing.lg,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final p = providers[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: YLSpacing.sm),
                  child: _ProviderCard(
                    provider: p,
                    isUpdating: _updatingSet.contains(p.name),
                    onUpdate: () => _updateProvider(p.name),
                    onHealthCheck: () => _healthCheck(p.name),
                  ),
                );
              }, childCount: providers.length),
            ),
          ),
      ],
    );
  }

  Future<void> _updateProvider(String name) async {
    final s = S.of(context);
    setState(() => _updatingSet.add(name));
    try {
      final ok = await ref.read(proxyProvidersProvider.notifier).update(name);
      if (ok) {
        AppNotifier.success(s.providerUpdateSuccess);
        await ref.read(proxyProvidersProvider.notifier).refresh();
      } else {
        AppNotifier.error(s.providerUpdateFailed);
      }
    } finally {
      if (mounted) setState(() => _updatingSet.remove(name));
    }
  }

  /// Refresh every rule-provider in parallel via mihomo's
  /// `PUT /providers/rules/{name}`. Rule sets (geosite, ad-block lists,
  /// custom domain groups) tend to drift faster than proxy providers —
  /// CVR exposes this; YueLink previously required a full core restart.
  Future<void> _refreshAllRuleProviders() async {
    try {
      final api = CoreManager.instance.api;
      if (!await api.isAvailable()) {
        AppNotifier.error('核心未运行，无法刷新规则集');
        return;
      }
      final result = await api.refreshAllRuleProviders();
      if (result.ok == 0 && result.failed == 0) {
        AppNotifier.warning('未找到任何规则集');
      } else if (result.failed == 0) {
        AppNotifier.success('已刷新 ${result.ok} 个规则集');
      } else {
        AppNotifier.warning('刷新完成：成功 ${result.ok}，失败 ${result.failed}');
      }
    } catch (e) {
      AppNotifier.error('刷新规则集失败：$e');
    }
  }

  Future<void> _healthCheck(String name) async {
    final s = S.of(context);
    setState(() => _updatingSet.add(name));
    try {
      await ref.read(proxyProvidersProvider.notifier).healthCheck(name);
      AppNotifier.success(s.providerHealthCheckDone);
      await ref.read(proxyProvidersProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _updatingSet.remove(name));
    }
  }
}

class _ProviderCard extends StatelessWidget {
  final ProxyProviderInfo provider;
  final bool isUpdating;
  final VoidCallback onUpdate;
  final VoidCallback onHealthCheck;

  const _ProviderCard({
    required this.provider,
    required this.isUpdating,
    required this.onUpdate,
    required this.onHealthCheck,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? YLColors.zinc900 : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final iconColor = provider.vehicleType == 'HTTP'
        ? const Color(0xFF3B82F6)
        : const Color(0xFF14B8A6);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(color: border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Strip the divider lines that ExpansionTile draws by default —
        // we render our own via the surrounding container.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: YLSpacing.lg,
            vertical: 0,
          ),
          childrenPadding: EdgeInsets.zero,
          leading: Icon(
            provider.vehicleType == 'HTTP'
                ? Icons.cloud_rounded
                : Icons.folder_rounded,
            size: 20,
            color: iconColor,
          ),
          title: Text(
            provider.name,
            style: YLText.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : YLColors.zinc900,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                _VehicleChip(type: provider.vehicleType),
                const SizedBox(width: YLSpacing.sm),
                Text(
                  s.providerNodeCount(provider.count),
                  style: YLText.caption.copyWith(
                    color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                  ),
                ),
              ],
            ),
          ),
          trailing: isUpdating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.expand_more,
                  size: 20,
                  color: isDark ? YLColors.zinc500 : YLColors.zinc400,
                ),
          children: [
            if (provider.updatedAt != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  YLSpacing.lg,
                  0,
                  YLSpacing.lg,
                  YLSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: isDark ? YLColors.zinc500 : YLColors.zinc400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatTime(provider.updatedAt!),
                      style: YLText.caption.copyWith(
                        color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                YLSpacing.md,
                YLSpacing.xs,
                YLSpacing.md,
                YLSpacing.md,
              ),
              child: Wrap(
                spacing: YLSpacing.sm,
                runSpacing: YLSpacing.xs,
                children: [
                  OutlinedButton.icon(
                    onPressed: isUpdating ? null : onUpdate,
                    icon: const Icon(Icons.sync, size: 16),
                    label: Text(s.providerUpdate),
                  ),
                  OutlinedButton.icon(
                    onPressed: isUpdating ? null : onHealthCheck,
                    icon: const Icon(Icons.favorite_border, size: 16),
                    label: Text(s.providerHealthCheck),
                  ),
                ],
              ),
            ),
            if (provider.proxies.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  YLSpacing.md,
                  0,
                  YLSpacing.md,
                  YLSpacing.md,
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: provider.proxies.map((name) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(YLRadius.sm),
                      ),
                      child: Text(
                        name,
                        style: YLText.caption.copyWith(
                          fontSize: 11,
                          color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _VehicleChip extends StatelessWidget {
  final String type;
  const _VehicleChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final color = type == 'HTTP'
        ? const Color(0xFF3B82F6)
        : const Color(0xFF14B8A6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
