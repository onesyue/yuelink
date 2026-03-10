import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proxy.dart';
import '../providers/core_provider.dart';
import '../providers/proxy_provider.dart';

const _kPresetTestUrls = [
  'https://www.gstatic.com/generate_204',
  'https://cp.cloudflare.com/generate_204',
  'http://www.google.com/generate_204',
  'https://www.apple.com/library/test/success.html',
];

enum _SortMode { none, delay }

class ProxyPage extends ConsumerStatefulWidget {
  const ProxyPage({super.key});

  @override
  ConsumerState<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends ConsumerState<ProxyPage> {
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.none;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(proxyGroupsProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(proxyGroupsProvider);
    final status = ref.watch(coreStatusProvider);

    if (status != CoreStatus.running) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('请先连接以查看代理节点',
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    if (groups.isEmpty) {
      return Scaffold(
        body: const Center(child: CircularProgressIndicator()),
        floatingActionButton: FloatingActionButton.small(
          onPressed: () => ref.read(proxyGroupsProvider.notifier).refresh(),
          child: const Icon(Icons.refresh),
        ),
      );
    }

    final filteredGroups = _filterGroups(groups);

    return Scaffold(
      body: Column(
        children: [
          // Search bar + sort toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索节点...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _sortMode = _sortMode == _SortMode.none
                        ? _SortMode.delay
                        : _SortMode.none;
                  }),
                  icon: Icon(
                    Icons.sort,
                    size: 20,
                    color: _sortMode == _SortMode.delay
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: _sortMode == _SortMode.delay ? '取消排序' : '按延迟排序',
                ),
                IconButton(
                  onPressed: () => _showTestUrlDialog(context, ref),
                  icon: const Icon(Icons.tune, size: 20),
                  tooltip: '测速设置',
                ),
              ],
            ),
          ),

          // Group list
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.read(proxyGroupsProvider.notifier).refresh();
              },
              child: filteredGroups.isEmpty
                  ? Center(
                      child: Text('未找到匹配的节点',
                          style: Theme.of(context).textTheme.bodyMedium))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: filteredGroups.length,
                      itemBuilder: (context, index) {
                        return _ProxyGroupCard(
                          group: filteredGroups[index],
                          searchQuery: _searchQuery,
                          sortMode: _sortMode,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTestUrlDialog(BuildContext context, WidgetRef ref) {
    final currentUrl = ref.read(testUrlProvider);
    final ctrl = TextEditingController(text: currentUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('测速 URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: '自定义 URL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            ...(_kPresetTestUrls.map((url) => InkWell(
                  onTap: () => ctrl.text = url,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.link, size: 14,
                            color: Theme.of(ctx).colorScheme.primary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(url,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final url = ctrl.text.trim();
              if (url.isNotEmpty) {
                ref.read(testUrlProvider.notifier).state = url;
              }
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  List<ProxyGroup> _filterGroups(List<ProxyGroup> groups) {
    if (_searchQuery.isEmpty) return groups;
    final q = _searchQuery.toLowerCase();
    return groups
        .where((g) =>
            g.name.toLowerCase().contains(q) ||
            g.all.any((n) => n.toLowerCase().contains(q)))
        .toList();
  }
}

class _ProxyGroupCard extends ConsumerWidget {
  final ProxyGroup group;
  final String searchQuery;
  final _SortMode sortMode;

  const _ProxyGroupCard({
    required this.group,
    required this.searchQuery,
    required this.sortMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delays = ref.watch(delayResultsProvider);
    final testing = ref.watch(delayTestingProvider);

    // Filter nodes if searching
    var visibleNodes = searchQuery.isEmpty
        ? List<String>.from(group.all)
        : group.all
            .where(
                (n) => n.toLowerCase().contains(searchQuery.toLowerCase()))
            .toList();

    // Sort by delay if enabled
    if (sortMode == _SortMode.delay) {
      visibleNodes.sort((a, b) {
        final da = delays[a];
        final db = delays[b];
        // Untested nodes go to end
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        // Timeout (<=0) goes after valid delays
        if (da <= 0 && db <= 0) return 0;
        if (da <= 0) return 1;
        if (db <= 0) return -1;
        return da.compareTo(db);
      });
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: searchQuery.isNotEmpty,
        leading: Icon(_groupIcon(group.name),
            size: 20, color: Theme.of(context).colorScheme.primary),
        title: Text(group.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Row(
          children: [
            _TypeChip(type: group.type),
            const SizedBox(width: 8),
            Flexible(
              child: Text(group.now,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: visibleNodes.map((name) {
                final isSelected = name == group.now;
                final delay = delays[name];
                final isTesting = testing.contains(name);

                return GestureDetector(
                  onLongPress: isTesting
                      ? null
                      : () => ref.read(delayTestProvider).testDelay(name),
                  child: ChoiceChip(
                    label: SizedBox(
                      width: 100,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 2),
                          if (isTesting)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5),
                            )
                          else if (delay != null)
                            Text(
                              delay > 0 ? '${delay}ms' : 'timeout',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _delayColor(delay),
                              ),
                            )
                          else
                            Text('--',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                        ],
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      ref
                          .read(proxyGroupsProvider.notifier)
                          .changeProxy(group.name, name);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: testing.isEmpty
                      ? () => ref
                          .read(delayTestProvider)
                          .testGroup(group.name, visibleNodes)
                      : null,
                  icon: const Icon(Icons.speed, size: 16),
                  label: Text(testing.isEmpty
                      ? '测速全部'
                      : '测速中 (${testing.length})'),
                ),
                const Spacer(),
                Text('${visibleNodes.length}/${group.all.length} 节点',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _delayColor(int delay) {
    if (delay <= 0) return Colors.red;
    if (delay < 100) return Colors.green;
    if (delay < 300) return Colors.lightGreen;
    if (delay < 500) return Colors.orange;
    return Colors.red;
  }

  /// Map group names to recognizable icons.
  IconData _groupIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('youtube')) return Icons.play_circle_outline;
    if (n.contains('tiktok')) return Icons.music_note;
    if (n.contains('ai') || n.contains('openai') || n.contains('claude')) {
      return Icons.auto_awesome;
    }
    if (n.contains('google')) return Icons.search;
    if (n.contains('telegram')) return Icons.send;
    if (n.contains('github')) return Icons.code;
    if (n.contains('流媒体') || n.contains('netflix') || n.contains('disney')) {
      return Icons.movie_outlined;
    }
    if (n.contains('社交') || n.contains('twitter') || n.contains('facebook')) {
      return Icons.people_outline;
    }
    if (n.contains('游戏') || n.contains('game') || n.contains('steam')) {
      return Icons.sports_esports;
    }
    if (n.contains('兜底') || n.contains('fallback') || n.contains('漏网')) {
      return Icons.catching_pokemon;
    }
    if (n.contains('自动') || n.contains('url-test') || n.contains('auto')) {
      return Icons.speed;
    }
    if (n.contains('故障') || n.contains('转移')) return Icons.swap_horiz;
    if (n.contains('香港') || n.contains('🇭🇰')) return Icons.location_on;
    if (n.contains('聚合') || n.contains('balance')) return Icons.balance;
    if (n.contains('更多')) return Icons.language;
    return Icons.dns_outlined;
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _typeColor(type).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _typeLabel(type),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _typeColor(type),
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'Selector':
        return '手动选择';
      case 'URLTest':
        return '自动测速';
      case 'Fallback':
        return '故障转移';
      case 'LoadBalance':
        return '负载均衡';
      default:
        return type;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'Selector':
        return Colors.blue;
      case 'URLTest':
        return Colors.green;
      case 'Fallback':
        return Colors.orange;
      case 'LoadBalance':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
