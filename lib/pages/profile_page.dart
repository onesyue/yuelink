import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../services/subscription_parser.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);

    return Scaffold(
      body: profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (profiles) {
          if (profiles.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('暂无订阅',
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Text('点击下方按钮添加机场订阅',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: profiles.length,
            itemBuilder: (context, index) {
              final profile = profiles[index];
              final isActive = profile.id == activeId;
              return _ProfileCard(
                profile: profile,
                isActive: isActive,
                onTap: () {
                  ref.read(activeProfileIdProvider.notifier).select(
                      profile.id);
                },
                onUpdate: () {
                  ref.read(profilesProvider.notifier).update(profile);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('正在更新...')));
                },
                onDelete: () => _confirmDelete(context, ref, profile),
              );
            },
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'paste',
            onPressed: () => _pasteFromClipboard(context, ref),
            child: const Icon(Icons.content_paste),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () => _showAddDialog(context, ref),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Future<void> _pasteFromClipboard(
      BuildContext context, WidgetRef ref) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !text.startsWith('http')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('剪贴板中没有有效的订阅链接')));
      }
      return;
    }
    if (context.mounted) {
      _showAddDialog(context, ref, prefilledUrl: text);
    }
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Profile profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除「${profile.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(profilesProvider.notifier).delete(profile.id);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref,
      {String? prefilledUrl}) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: prefilledUrl);
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('添加订阅'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '我的机场',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: '订阅链接',
                  hintText: 'https://...',
                  prefixIcon: Icon(Icons.link),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final url = urlCtrl.text.trim();
                      if (name.isEmpty || url.isEmpty) return;

                      setState(() => isLoading = true);
                      try {
                        final profile = await ref
                            .read(profilesProvider.notifier)
                            .add(name: name, url: url);
                        // Auto-select the new profile
                        ref.read(activeProfileIdProvider.notifier).select(
                            profile.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('添加成功')));
                        }
                      } catch (e) {
                        setState(() => isLoading = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('添加失败: $e')));
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

}

class _ProfileCard extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  const _ProfileCard({
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final sub = profile.subInfo;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color:
          isActive ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Icon(
                    isActive
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(profile.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'update') onUpdate();
                      if (action == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'update', child: Text('更新订阅')),
                      const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ],
              ),

              // Subscription info
              if (profile.hasSubInfo && sub != null) ...[
                const SizedBox(height: 8),
                // Traffic usage bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: sub.usagePercent ?? 0,
                    minHeight: 6,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    color: _usageColor(sub.usagePercent ?? 0),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '已用 ${formatBytes((sub.upload ?? 0) + (sub.download ?? 0))} / ${formatBytes(sub.total ?? 0)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    if (sub.expire != null)
                      Text(
                        sub.isExpired
                            ? '已过期'
                            : '剩余 ${sub.daysRemaining} 天',
                        style: TextStyle(
                          fontSize: 11,
                          color: sub.isExpired
                              ? Colors.red
                              : (sub.daysRemaining != null &&
                                      sub.daysRemaining! < 7)
                                  ? Colors.orange
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],

              // Last updated
              if (profile.lastUpdated != null) ...[
                const SizedBox(height: 4),
                Text(
                  '更新于 ${_formatTime(profile.lastUpdated!)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _usageColor(double percent) {
    if (percent < 0.5) return Colors.green;
    if (percent < 0.8) return Colors.orange;
    return Colors.red;
  }

  String _formatTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
