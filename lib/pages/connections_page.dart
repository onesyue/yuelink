import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection.dart';
import '../providers/connection_provider.dart';
import '../providers/core_provider.dart';

class ConnectionsPage extends ConsumerStatefulWidget {
  const ConnectionsPage({super.key});

  @override
  ConsumerState<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends ConsumerState<ConnectionsPage> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      ref.read(connectionSearchProvider.notifier).state = _searchCtrl.text;
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(coreStatusProvider);

    if (status != CoreStatus.running) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cable_outlined,
                  size: 64,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text('请先连接以查看活跃连接',
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    // Keep connections stream alive
    ref.watch(connectionsStreamProvider);

    final snapshot = ref.watch(connectionsSnapshotProvider);
    final filtered = ref.watch(filteredConnectionsProvider);
    final actions = ref.read(connectionActionsProvider);

    return Scaffold(
      body: Column(
        children: [
          // Summary bar
          _SummaryBar(snapshot: snapshot),

          // Search + actions bar
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: '搜索目标、进程、规则...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                ref
                                    .read(connectionSearchProvider.notifier)
                                    .state = '';
                              },
                            )
                          : null,
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.close_outlined, size: 16),
                  label: const Text('断开全部'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: snapshot.connections.isEmpty
                      ? null
                      : () => _confirmCloseAll(context, actions),
                ),
              ],
            ),
          ),

          // Count badge
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filtered.length} 个连接'
                    '${filtered.length != snapshot.connections.length ? '（已过滤）' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),

          // Connections list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      snapshot.connections.isEmpty ? '暂无活跃连接' : '无匹配结果',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(
                        left: 8, right: 8, bottom: 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _ConnectionTile(
                      connection: filtered[i],
                      onClose: () => actions.close(filtered[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmCloseAll(BuildContext context, ConnectionActions actions) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('断开所有连接'),
        content: const Text('确定要断开所有活跃连接吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              actions.closeAll();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('断开全部'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// Summary bar
// ------------------------------------------------------------------

class _SummaryBar extends StatelessWidget {
  final ConnectionsSnapshot snapshot;
  const _SummaryBar({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          _StatItem(
            icon: Icons.cable_outlined,
            label: '连接数',
            value: '${snapshot.connections.length}',
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 24),
          _StatItem(
            icon: Icons.arrow_downward,
            label: '累计下载',
            value: _formatBytes(snapshot.downloadTotal),
            color: Colors.green,
          ),
          const SizedBox(width: 24),
          _StatItem(
            icon: Icons.arrow_upward,
            label: '累计上传',
            value: _formatBytes(snapshot.uploadTotal),
            color: Colors.blue,
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------
// Connection tile
// ------------------------------------------------------------------

class _ConnectionTile extends StatelessWidget {
  final ActiveConnection connection;
  final VoidCallback onClose;

  const _ConnectionTile({
    required this.connection,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final hasSpeed = connection.curDownloadSpeed > 0 ||
        connection.curUploadSpeed > 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Network type badge
              _NetworkBadge(network: connection.network),
              const SizedBox(width: 10),

              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Target host
                    Text(
                      connection.target,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // Chain / proxy used
                        Flexible(
                          child: Text(
                            connection.chains.isNotEmpty
                                ? connection.chains.join(' → ')
                                : connection.rule,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (connection.processName.isNotEmpty) ...[
                          Text(' · ',
                              style: Theme.of(context).textTheme.bodySmall),
                          Text(connection.processName,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                    if (hasSpeed)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.arrow_downward,
                                size: 10, color: Colors.green),
                            Text(
                              _formatSpeed(connection.curDownloadSpeed),
                              style: TextStyle(
                                  fontSize: 10, color: Colors.green),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.arrow_upward,
                                size: 10, color: Colors.blue),
                            Text(
                              _formatSpeed(connection.curUploadSpeed),
                              style:
                                  TextStyle(fontSize: 10, color: Colors.blue),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Duration + close
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(connection.durationText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
                  const SizedBox(height: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onClose,
                    child: const Icon(Icons.close, size: 16,
                        color: Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ConnectionDetailSheet(connection: connection),
    );
  }

  String _formatSpeed(int bps) {
    if (bps < 1024) return '${bps}B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(0)}K/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)}M/s';
  }
}

class _NetworkBadge extends StatelessWidget {
  final String network;
  const _NetworkBadge({required this.network});

  @override
  Widget build(BuildContext context) {
    final color = network.toLowerCase() == 'udp' ? Colors.orange : Colors.blue;
    return Container(
      width: 34,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        network.toUpperCase(),
        style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Detail bottom sheet
// ------------------------------------------------------------------

class _ConnectionDetailSheet extends StatelessWidget {
  final ActiveConnection connection;
  const _ConnectionDetailSheet({required this.connection});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(20),
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('连接详情',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _DetailRow('目标', connection.target),
          _DetailRow('协议', '${connection.network.toUpperCase()} / ${connection.type}'),
          _DetailRow('来源', '${connection.sourceIp}:${connection.sourcePort}'),
          if (connection.destinationIp.isNotEmpty)
            _DetailRow('目标 IP', '${connection.destinationIp}:${connection.destinationPort}'),
          _DetailRow('代理链', connection.chains.join(' → ')),
          _DetailRow('规则', connection.rule +
              (connection.rulePayload.isNotEmpty
                  ? ' (${connection.rulePayload})'
                  : '')),
          if (connection.processName.isNotEmpty)
            _DetailRow('进程', connection.processName),
          _DetailRow('持续时间', connection.durationText),
          _DetailRow('下载', _fmtBytes(connection.download)),
          _DetailRow('上传', _fmtBytes(connection.upload)),
          _DetailRow('连接时间', _formatTime(connection.start)),
        ],
      ),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
