import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/core_controller.dart';
import '../models/traffic.dart';
import '../providers/core_provider.dart';
import '../services/core_manager.dart';
import '../services/subscription_parser.dart';

class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  List<ConnectionInfo> _connections = [];
  int _uploadTotal = 0;
  int _downloadTotal = 0;
  Timer? _refreshTimer;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _refresh();
    });
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _refresh() async {
    final manager = CoreManager.instance;
    Map<String, dynamic> data;

    if (manager.isMockMode) {
      data = CoreController.instance.getConnections();
    } else {
      try {
        data = await manager.api.getConnections();
      } catch (_) {
        return;
      }
    }

    final conns = (data['connections'] as List?)
            ?.map((e) => ConnectionInfo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    if (mounted) {
      setState(() {
        _connections = conns;
        _uploadTotal = (data['uploadTotal'] as num?)?.toInt() ?? 0;
        _downloadTotal = (data['downloadTotal'] as num?)?.toInt() ?? 0;
      });
    }
  }

  Future<void> _closeConnection(String id) async {
    final manager = CoreManager.instance;
    if (manager.isMockMode) {
      CoreController.instance.closeConnection(id);
    } else {
      await manager.api.closeConnection(id);
    }
  }

  Future<void> _closeAllConnections() async {
    final manager = CoreManager.instance;
    if (manager.isMockMode) {
      CoreController.instance.closeAllConnections();
    } else {
      await manager.api.closeAllConnections();
    }
  }

  List<ConnectionInfo> get _filteredConnections {
    if (_searchQuery.isEmpty) return _connections;
    final q = _searchQuery.toLowerCase();
    return _connections
        .where((c) =>
            c.host.toLowerCase().contains(q) ||
            c.rule.toLowerCase().contains(q) ||
            c.chains.toLowerCase().contains(q) ||
            c.network.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(coreStatusProvider);
    final isRunning = status == CoreStatus.running;

    // Auto-refresh when running
    if (isRunning && _refreshTimer == null) {
      _startAutoRefresh();
    } else if (!isRunning && _refreshTimer != null) {
      _stopAutoRefresh();
    }

    if (!isRunning) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.list_alt_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('请先连接以查看连接日志',
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredConnections;

    return Scaffold(
      body: Column(
        children: [
          // Summary bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatChip(
                  icon: Icons.arrow_upward,
                  iconColor: Colors.blue,
                  label: '总上传',
                  value: formatBytes(_uploadTotal),
                ),
                _StatChip(
                  icon: Icons.arrow_downward,
                  iconColor: Colors.green,
                  label: '总下载',
                  value: formatBytes(_downloadTotal),
                ),
                _StatChip(
                  icon: Icons.link,
                  iconColor: Theme.of(context).colorScheme.primary,
                  label: '连接数',
                  value: '${_connections.length}',
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Search + action bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索连接...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: const Icon(Icons.clear, size: 16),
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (v) =>
                          setState(() => _searchQuery = v.trim()),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: '刷新',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: _connections.isEmpty
                      ? null
                      : () async {
                          await _closeAllConnections();
                          _refresh();
                        },
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: '关闭全部',
                  visualDensity: VisualDensity.compact,
                  color: Colors.red.shade300,
                ),
              ],
            ),
          ),

          // Connection list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                        _searchQuery.isEmpty ? '暂无活动连接' : '未找到匹配的连接',
                        style: Theme.of(context).textTheme.bodyMedium))
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final conn = filtered[index];
                      return _ConnectionTile(
                        conn: conn,
                        onTap: () => _showConnectionDetail(context, conn),
                        onClose: () async {
                          await _closeConnection(conn.id);
                          _refresh();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showConnectionDetail(BuildContext context, ConnectionInfo conn) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    conn.network == 'udp' ? Icons.swap_horiz : Icons.link,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(conn.host,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const Divider(height: 24),
              _DetailRow(label: '协议', value: conn.network.toUpperCase()),
              _DetailRow(label: '规则', value: conn.rule),
              _DetailRow(label: '代理链', value: conn.chains),
              _DetailRow(
                  label: '上传', value: formatBytes(conn.upload)),
              _DetailRow(
                  label: '下载', value: formatBytes(conn.download)),
              _DetailRow(
                  label: '开始时间',
                  value:
                      '${conn.start.hour.toString().padLeft(2, '0')}:${conn.start.minute.toString().padLeft(2, '0')}:${conn.start.second.toString().padLeft(2, '0')}'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _closeConnection(conn.id);
                    _refresh();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('关闭连接'),
                  style:
                      OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  final ConnectionInfo conn;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _ConnectionTile({
    required this.conn,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(
        conn.network == 'udp' ? Icons.swap_horiz : Icons.link,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(conn.host, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        '${conn.network.toUpperCase()} · ${conn.rule} · ${conn.chains}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16),
        onPressed: onClose,
        visualDensity: VisualDensity.compact,
        color: Colors.red.shade300,
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
