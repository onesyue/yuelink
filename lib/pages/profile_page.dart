import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../services/profile_service.dart';
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
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('加载失败: $e',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => ref.read(profilesProvider.notifier).load(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
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
          // Sort: active profile first
          final sorted = List<Profile>.from(profiles)
            ..sort((a, b) {
              if (a.id == activeId && b.id != activeId) return -1;
              if (b.id == activeId && a.id != activeId) return 1;
              return 0;
            });
          return RefreshIndicator(
            onRefresh: () => ref.read(profilesProvider.notifier).load(),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final profile = sorted[index];
                final isActive = profile.id == activeId;
                return _ProfileCard(
                  profile: profile,
                  isActive: isActive,
                  onTap: () {
                    ref
                        .read(activeProfileIdProvider.notifier)
                        .select(profile.id);
                  },
                  onUpdate: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('正在更新订阅...')));
                    try {
                      await ref
                          .read(profilesProvider.notifier)
                          .update(profile);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('更新成功')));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('更新失败: $e')));
                      }
                    }
                  },
                  onEdit: () => _showEditDialog(context, ref, profile),
                  onViewConfig: () => _showConfigViewer(context, profile),
                  onDelete: () => _confirmDelete(context, ref, profile),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'paste',
            onPressed: () => _pasteFromClipboard(context, ref),
            tooltip: '从剪贴板粘贴',
            child: const Icon(Icons.content_paste),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () => _showAddDialog(context, ref),
            tooltip: '添加订阅',
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
              // Clear active if deleting the active profile
              final activeId = ref.read(activeProfileIdProvider);
              if (activeId == profile.id) {
                ref.read(activeProfileIdProvider.notifier).select(null);
              }
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
                textInputAction: TextInputAction.next,
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
                textInputAction: TextInputAction.done,
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
                        ref
                            .read(activeProfileIdProvider.notifier)
                            .select(profile.id);
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(
      BuildContext context, WidgetRef ref, Profile profile) {
    final nameCtrl = TextEditingController(text: profile.name);
    final urlCtrl = TextEditingController(text: profile.url);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑订阅'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称',
                prefixIcon: Icon(Icons.label_outline),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: '订阅链接',
                prefixIcon: Icon(Icons.link),
              ),
              maxLines: 2,
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isEmpty || url.isEmpty) return;

              profile.name = name;
              profile.url = url;
              ref.read(profilesProvider.notifier).update(profile);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('已保存')));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showConfigViewer(BuildContext context, Profile profile) async {
    final config = await ProfileService.loadConfig(profile.id);
    if (!context.mounted) return;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          title: Text(profile.name),
          actions: [
            if (config != null)
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: '复制配置',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: config));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('已复制配置内容')));
                },
              ),
          ],
        ),
        body: config == null
            ? const Center(child: Text('配置文件不存在'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  config,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
      ),
    ));
  }
}

class _ProfileCard extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onUpdate;
  final VoidCallback onEdit;
  final VoidCallback onViewConfig;
  final VoidCallback onDelete;

  const _ProfileCard({
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onUpdate,
    required this.onEdit,
    required this.onViewConfig,
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
                      switch (action) {
                        case 'update':
                          onUpdate();
                        case 'edit':
                          onEdit();
                        case 'config':
                          onViewConfig();
                        case 'copy':
                          Clipboard.setData(
                              ClipboardData(text: profile.url));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('已复制订阅链接')));
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'update', child: Text('更新订阅')),
                      const PopupMenuItem(
                          value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(
                          value: 'config', child: Text('查看配置')),
                      const PopupMenuItem(
                          value: 'copy', child: Text('复制链接')),
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

              // Last updated + staleness warning
              if (profile.lastUpdated != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '更新于 ${_formatTime(profile.lastUpdated!)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                    ),
                    if (_isStale(profile)) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.warning_amber_rounded,
                          size: 14, color: Colors.orange.shade700),
                      const SizedBox(width: 2),
                      Text('需要更新',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade700)),
                    ],
                  ],
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

  bool _isStale(Profile p) {
    if (p.lastUpdated == null) return false;
    return DateTime.now().difference(p.lastUpdated!) > p.updateInterval;
  }

  String _formatTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
