import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_provider.dart';
import '../providers/profile_provider.dart';
import '../services/app_notifier.dart';
import '../services/profile_service.dart';
import '../theme.dart';

/// Modern Configuration Management Page (Vercel/Tailwind style)
/// Acts as the "Subscription Management Center".
class ConfigurationsPage extends ConsumerWidget {
  const ConfigurationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profilesAsync = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar.large(
            expandedHeight: 120.0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            title: Text(
              'Profiles',
              style: YLText.display.copyWith(
                color: isDark ? YLColors.zinc50 : YLColors.zinc900,
                fontSize: 28,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () {
                  // TODO: Show import options (URL, File, Clipboard)
                  AppNotifier.info('添加订阅功能即将上线');
                },
              ),
              const SizedBox(width: YLSpacing.sm),
            ],
          ),
          
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: YLSpacing.xl, vertical: YLSpacing.sm),
            sliver: profilesAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, stack) => SliverToBoxAdapter(
                child: Center(child: Text('加载失败: $err', style: YLText.body.copyWith(color: YLColors.error))),
              ),
              data: (profiles) {
                if (profiles.isEmpty) {
                  return SliverToBoxAdapter(child: _buildEmptyState(context));
                }

                final activeProfile = profiles.where((p) => p.id == activeId).firstOrNull;
                final otherProfiles = profiles.where((p) => p.id != activeId).toList();

                return SliverList(
                  delegate: SliverChildListDelegate([
                    
                    // Quick Import Input
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Paste subscription URL here...',
                        prefixIcon: const Icon(Icons.link_rounded, size: 20),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: FilledButton(
                            onPressed: () {
                              AppNotifier.info('导入功能即将上线');
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: YLSpacing.lg),
                              minimumSize: const Size(0, 32),
                            ),
                            child: const Text('Import'),
                          ),
                        ),
                      ),
                    ),
                    
                    if (activeProfile != null) ...[
                      const SizedBox(height: YLSpacing.xxl),
                      const YLSectionLabel('Active Profile'),
                      _ProfileCard(
                        id: activeProfile.id,
                        name: activeProfile.name,
                        url: activeProfile.url ?? 'Local File',
                        updatedAt: _formatDate(activeProfile.updatedAt),
                        isActive: true,
                        isExpired: activeProfile.subInfo?.isExpired ?? false,
                      ),
                    ],
                    
                    if (otherProfiles.isNotEmpty) ...[
                      const SizedBox(height: YLSpacing.xxl),
                      const YLSectionLabel('All Profiles'),
                      ...otherProfiles.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: YLSpacing.lg),
                        child: _ProfileCard(
                          id: p.id,
                          name: p.name,
                          url: p.url ?? 'Local File',
                          updatedAt: _formatDate(p.updatedAt),
                          isActive: false,
                          isExpired: p.subInfo?.isExpired ?? false,
                        ),
                      )),
                    ],
                    
                    const SizedBox(height: 100), 
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 60.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(YLSpacing.xl),
            decoration: BoxDecoration(
              color: isDark ? YLColors.zinc900 : YLColors.zinc100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.inbox_rounded, size: 48, color: YLColors.zinc400),
          ),
          const SizedBox(height: YLSpacing.xl),
          Text('No Profiles Found', style: YLText.titleLarge),
          const SizedBox(height: YLSpacing.sm),
          Text(
            'Add a subscription URL or import a local config\nto get started.',
            style: YLText.body.copyWith(color: YLColors.zinc500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: YLSpacing.xxl),
          FilledButton.icon(
            onPressed: () {
              AppNotifier.info('添加订阅功能即将上线');
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Profile'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  final String id;
  final String name;
  final String url;
  final String updatedAt;
  final bool isActive;
  final bool isExpired;

  const _ProfileCard({
    required this.id,
    required this.name,
    required this.url,
    required this.updatedAt,
    required this.isActive,
    required this.isExpired,
  });

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  bool _isApplying = false;

  void _handleUse() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);

    // 真实状态闭环：如果内核正在运行，需要重启内核并等待结果
    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.running) {
      AppNotifier.info('正在重启内核以应用新配置...');
      await ref.read(coreActionsProvider).stop();
      
      final config = await ref.read(profileServiceProvider).loadConfig(widget.id);
      if (config != null) {
        final ok = await ref.read(coreActionsProvider).start(config);
        if (ok) {
          ref.read(activeProfileIdProvider.notifier).select(widget.id);
          AppNotifier.success('已成功应用配置: ${widget.name}');
        }
        // 如果失败，coreActionsProvider.start 内部已经抛出了具体的错误提示，
        // 且内核会停留在 stopped 状态，不会出现假同步。
      } else {
        AppNotifier.error('无法读取配置文件');
      }
    } else {
      ref.read(activeProfileIdProvider.notifier).select(widget.id);
      AppNotifier.success('已切换至配置: ${widget.name}');
    }

    if (mounted) {
      setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return YLSurface(
      padding: const EdgeInsets.all(YLSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Indicator
              Padding(
                padding: const EdgeInsets.only(top: 6.0, right: 12.0),
                child: YLStatusDot(
                  color: widget.isActive 
                      ? YLColors.connected 
                      : (widget.isExpired ? YLColors.error : YLColors.zinc300),
                  glow: widget.isActive,
                ),
              ),
              
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: YLText.titleMedium.copyWith(
                        color: widget.isExpired ? YLColors.error : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.url,
                      style: YLText.caption.copyWith(color: YLColors.zinc500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Actions Menu
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                color: YLColors.zinc400,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  AppNotifier.info('配置菜单即将上线');
                },
              ),
            ],
          ),
          
          const SizedBox(height: YLSpacing.lg),
          const Divider(),
          const SizedBox(height: YLSpacing.lg),
          
          // Footer Stats & Actions
          Row(
            children: [
              Icon(
                widget.isExpired ? Icons.error_outline_rounded : Icons.cloud_sync_rounded, 
                size: 14, 
                color: widget.isExpired ? YLColors.error : YLColors.zinc400
              ),
              const SizedBox(width: 6),
              Text(
                widget.isExpired ? 'Subscription Expired' : 'Updated ${widget.updatedAt}',
                style: YLText.caption.copyWith(
                  color: widget.isExpired ? YLColors.error : YLColors.zinc500,
                ),
              ),
              const Spacer(),
              if (!widget.isActive) ...[
                OutlinedButton(
                  onPressed: _isApplying ? null : _handleUse,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: YLSpacing.md),
                  ),
                  child: _isApplying 
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Use'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
