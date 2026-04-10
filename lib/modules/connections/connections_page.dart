import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../domain/models/connection.dart';
import 'providers/connections_providers.dart';
import '../../providers/core_provider.dart';
import '../../theme.dart';

class ConnectionsPage extends ConsumerStatefulWidget {
  const ConnectionsPage({super.key});

  @override
  ConsumerState<ConnectionsPage> createState() =>
      _ConnectionsPageState();
}

enum _SortColumn { target, process, rule, download, upload, duration }

class _ConnectionsPageState extends ConsumerState<ConnectionsPage> {
  final _searchCtrl = TextEditingController();
  _SortColumn _sortCol = _SortColumn.duration;
  bool _sortAsc = false;

  // Always show AppBar — this page is always entered via Navigator.push()
  // from Settings on all platforms.
  static const bool _isSubPage = true;

  // Sort cache — avoids O(n log n) re-sort on every build when data hasn't changed
  List<ActiveConnection>? _sortedCache;
  List<ActiveConnection>? _sortedInput;
  _SortColumn? _sortedCol;
  bool? _sortedAsc;

  List<ActiveConnection> _sorted(List<ActiveConnection> list) {
    // Return cached result if inputs haven't changed (identity check is sufficient
    // because filteredConnectionsProvider returns a new list on every change)
    if (identical(list, _sortedInput) && _sortCol == _sortedCol && _sortAsc == _sortedAsc) {
      return _sortedCache!;
    }
    final copy = List<ActiveConnection>.from(list);
    copy.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case _SortColumn.target:   cmp = a.target.compareTo(b.target);
        case _SortColumn.process:  cmp = a.processName.compareTo(b.processName);
        case _SortColumn.rule:     cmp = a.rule.compareTo(b.rule);
        case _SortColumn.download: cmp = a.download.compareTo(b.download);
        case _SortColumn.upload:   cmp = a.upload.compareTo(b.upload);
        case _SortColumn.duration: cmp = a.start.compareTo(b.start);
      }
      return _sortAsc ? cmp : -cmp;
    });
    _sortedCache = copy;
    _sortedInput = list;
    _sortedCol = _sortCol;
    _sortedAsc = _sortAsc;
    return copy;
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      ref.read(connectionSearchProvider.notifier).state =
          _searchCtrl.text;
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final status = ref.watch(coreStatusProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (status != CoreStatus.running) {
      return Scaffold(
        appBar: _isSubPage
            ? AppBar(leading: const BackButton(), title: Text(s.navConnections))
            : null,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark ? YLColors.zinc900 : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: YLShadow.sm(context),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Icon(Icons.cable_rounded, size: 48,
                      color: isDark ? YLColors.zinc700 : YLColors.zinc300),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                s.notConnectedHintConnections,
                style: YLText.titleMedium.copyWith(
                  color: isDark ? YLColors.zinc500 : YLColors.zinc400,
                ),
              ),
            ],
          ),
        ),
      );
    }

    ref.watch(connectionsStreamProvider);

    final snapshot = ref.watch(connectionsSnapshotProvider);
    final filtered = ref.watch(filteredConnectionsProvider);
    final actions = ref.read(connectionActionsProvider);

    return Scaffold(
      appBar: _isSubPage
            ? AppBar(leading: const BackButton(), title: Text(s.navConnections))
            : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
            child: Text(
              s.navConnections,
              style: YLText.display.copyWith(
                color: isDark ? YLColors.zinc50 : YLColors.zinc900,
              ),
            ),
          ),

          // Summary bar (Glassmorphism)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SummaryBar(snapshot: snapshot),
          ),
          const SizedBox(height: 8),

          // Proxy stats (collapsible)
          if (snapshot.connections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Consumer(builder: (context, ref, _) {
                final stats = ref.watch(proxyStatsProvider);
                if (stats.isEmpty) return const SizedBox.shrink();
                return _ProxyStatsBar(stats: stats.take(5).toList());
              }),
            ),
          const SizedBox(height: 8),

          // Search + actions bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: YLShadow.card(context),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      style: YLText.body,
                      decoration: InputDecoration(
                        hintText: s.searchConnHint,
                        hintStyle: YLText.body.copyWith(color: YLColors.zinc500),
                        prefixIcon: Icon(Icons.search_rounded, size: 20, color: YLColors.zinc400),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.cancel_rounded, size: 18, color: YLColors.zinc400),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  ref.read(connectionSearchProvider.notifier).state = '';
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: snapshot.connections.isEmpty
                        ? Colors.transparent
                        : YLColors.errorLight.withValues(alpha:isDark ? 0.1 : 0.5),
                    borderRadius: BorderRadius.circular(YLRadius.lg),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.delete_sweep_rounded,
                        color: snapshot.connections.isEmpty ? YLColors.zinc500 : YLColors.error),
                    tooltip: s.closeAll,
                    onPressed: snapshot.connections.isEmpty
                        ? null
                        : () => _confirmCloseAll(context, actions),
                  ),
                ),
              ],
            ),
          ),

          // Count badge
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              filtered.length != snapshot.connections.length
                  ? s.connectionsCountFiltered(filtered.length)
                  : s.connectionsCount(filtered.length),
              style: YLText.caption.copyWith(color: YLColors.zinc500, fontWeight: FontWeight.w600),
            ),
          ),

          // Connections list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48,
                            color: isDark ? YLColors.zinc700 : YLColors.zinc300),
                        const SizedBox(height: 16),
                        Text(
                          snapshot.connections.isEmpty
                              ? s.noActiveConnections
                              : s.noMatchingConnections,
                          style: YLText.body.copyWith(color: YLColors.zinc500),
                        ),
                      ],
                    ),
                  )
                : (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                    ? _ConnectionsDataTable(
                        connections: _sorted(filtered),
                        sortColumn: _sortCol,
                        ascending: _sortAsc,
                        onSort: (col, asc) =>
                            setState(() { _sortCol = col; _sortAsc = asc; }),
                        onClose: (id) => actions.close(id),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 32),
                        physics: const BouncingScrollPhysics(),
                        itemCount: filtered.length,
                        addAutomaticKeepAlives: false,
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
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? YLColors.zinc900 : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YLRadius.xl)),
        title: Text(s.closeAllDialogTitle, style: YLText.titleLarge),
        content: Text(s.closeAllDialogMessage, style: YLText.body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.cancel, style: TextStyle(color: isDark ? YLColors.zinc400 : YLColors.zinc600))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              actions.closeAll();
            },
            style: FilledButton.styleFrom(
              backgroundColor: YLColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YLRadius.pill)),
            ),
            child: Text(s.closeAll),
          ),
        ],
      ),
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final ConnectionsSnapshot snapshot;
  const _SummaryBar({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha:0.08) : Colors.black.withValues(alpha:0.05),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StatItem(
            icon: Icons.cable_rounded,
            label: s.statConnections,
            value: '${snapshot.connections.length}',
            color: isDark ? Colors.white : YLColors.primary,
          ),
          Container(width: 1, height: 32, color: isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05)),
          _StatItem(
            icon: Icons.arrow_downward_rounded,
            label: s.statTotalDownload,
            value: _formatBytes(snapshot.downloadTotal),
            color: YLColors.connected,
          ),
          Container(width: 1, height: 32, color: isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05)),
          _StatItem(
            icon: Icons.arrow_upward_rounded,
            label: s.statTotalUpload,
            value: _formatBytes(snapshot.uploadTotal),
            color: Colors.blue.shade500,
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
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
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: YLText.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: color)),
            Text(label,
                style: YLText.caption.copyWith(
                    color: YLColors.zinc500, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

// ── Connection tile ───────────────────────────────────────────────────────────

class _ConnectionTile extends StatelessWidget {
  final ActiveConnection connection;
  final VoidCallback onClose;

  const _ConnectionTile({
    required this.connection,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSpeed = connection.curDownloadSpeed > 0 || connection.curUploadSpeed > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha:0.05) : Colors.black.withValues(alpha:0.03),
          width: 1,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(YLRadius.lg),
          onTap: () => _showDetail(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _NetworkBadge(network: connection.network),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.target,
                        style: YLText.titleMedium.copyWith(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : YLColors.primary).withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(YLRadius.sm),
                              ),
                              child: Text(
                                connection.chains.isNotEmpty
                                    ? connection.chains.join(' → ')
                                    : connection.rule,
                                style: YLText.caption.copyWith(color: isDark ? Colors.white : YLColors.primary, fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (connection.processName.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                connection.processName,
                                style: YLText.caption.copyWith(color: YLColors.zinc500, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (hasSpeed)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.south_rounded, size: 12, color: YLColors.connected),
                              const SizedBox(width: 2),
                              Text(
                                _formatSpeed(connection.curDownloadSpeed),
                                style: YLText.mono.copyWith(fontSize: 11, color: YLColors.connected),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.north_rounded, size: 12, color: Colors.blue.shade500),
                              const SizedBox(width: 2),
                              Text(
                                _formatSpeed(connection.curUploadSpeed),
                                style: YLText.mono.copyWith(fontSize: 11, color: Colors.blue.shade500),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      connection.durationText,
                      style: YLText.mono.copyWith(color: YLColors.zinc500, fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(YLRadius.pill),
                      onTap: onClose,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: YLColors.errorLight.withValues(alpha:isDark ? 0.1 : 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded, size: 14, color: YLColors.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ConnectionDetailSheet(connection: connection),
    );
  }

  String _formatSpeed(int bps) {
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) {
      return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

class _NetworkBadge extends StatelessWidget {
  final String network;
  const _NetworkBadge({required this.network});

  @override
  Widget build(BuildContext context) {
    final isUdp = network.toLowerCase() == 'udp';
    final color = isUdp ? YLColors.connecting : Colors.blue.shade500;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.15),
        borderRadius: BorderRadius.circular(YLRadius.md),
        border: Border.all(color: color.withValues(alpha:0.3), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        network.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

// ── Detail bottom sheet ───────────────────────────────────────────────────────

class _ConnectionDetailSheet extends StatelessWidget {
  final ActiveConnection connection;
  const _ConnectionDetailSheet({required this.connection});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc900 : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(YLRadius.xl)),
          boxShadow: YLShadow.overlay(context),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? YLColors.zinc700 : YLColors.zinc300,
                  borderRadius: BorderRadius.circular(YLRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(s.connectionDetailTitle, style: YLText.titleLarge),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? YLColors.zinc950 : YLColors.zinc50,
                borderRadius: BorderRadius.circular(YLRadius.lg),
                border: Border.all(color: isDark ? YLColors.zinc800 : YLColors.zinc200),
              ),
              child: Column(
                children: [
                  _DetailRow(s.detailTarget, connection.target),
                  const Divider(height: 24),
                  _DetailRow(s.detailProtocol, '${connection.network.toUpperCase()} / ${connection.type}'),
                  const Divider(height: 24),
                  _DetailRow(s.detailSource, '${connection.sourceIp}:${connection.sourcePort}'),
                  if (connection.destinationIp.isNotEmpty) ...[
                    const Divider(height: 24),
                    _DetailRow(s.detailTargetIp, '${connection.destinationIp}:${connection.destinationPort}'),
                  ],
                  const Divider(height: 24),
                  _DetailRow(s.detailProxyChain, connection.chains.join(' → ')),
                  const Divider(height: 24),
                  _DetailRow(
                    s.detailRule,
                    connection.rule + (connection.rulePayload.isNotEmpty ? ' (${connection.rulePayload})' : ''),
                  ),
                  if (connection.processName.isNotEmpty) ...[
                    const Divider(height: 24),
                    _DetailRow(s.detailProcess, connection.processName),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? YLColors.zinc950 : YLColors.zinc50,
                borderRadius: BorderRadius.circular(YLRadius.lg),
                border: Border.all(color: isDark ? YLColors.zinc800 : YLColors.zinc200),
              ),
              child: Column(
                children: [
                  _DetailRow(s.detailDuration, connection.durationText),
                  const Divider(height: 24),
                  _DetailRow(s.detailDownload, _fmtBytes(connection.download)),
                  const Divider(height: 24),
                  _DetailRow(s.detailUpload, _fmtBytes(connection.upload)),
                  const Divider(height: 24),
                  _DetailRow(s.detailConnectTime, _formatTime(connection.start)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: YLText.body.copyWith(color: YLColors.zinc500)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: YLText.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ── Desktop: Sortable DataTable ───────────────────────────────────────────────

class _ConnectionsDataTable extends StatelessWidget {
  final List<ActiveConnection> connections;
  final _SortColumn sortColumn;
  final bool ascending;
  final void Function(_SortColumn col, bool asc) onSort;
  final void Function(String id) onClose;

  const _ConnectionsDataTable({
    required this.connections,
    required this.sortColumn,
    required this.ascending,
    required this.onSort,
    required this.onClose,
  });

  DataColumn _col(String label, _SortColumn col) => DataColumn(
        label: Text(label, style: YLText.label.copyWith(fontWeight: FontWeight.w700)),
        numeric: col == _SortColumn.download || col == _SortColumn.upload,
        onSort: (_, asc) => onSort(col, asc),
      );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    int sortIndex = _SortColumn.values.indexOf(sortColumn);
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      physics: const BouncingScrollPhysics(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: DataTable(
          sortColumnIndex: sortIndex,
          sortAscending: ascending,
          columnSpacing: 24,
          headingRowHeight: 48,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 48,
          columns: [
            _col(s.detailTarget, _SortColumn.target),
            _col(s.detailProcess, _SortColumn.process),
            _col(s.detailRule, _SortColumn.rule),
            _col(s.detailDownload, _SortColumn.download),
            _col(s.detailUpload, _SortColumn.upload),
            _col(s.detailDuration, _SortColumn.duration),
            const DataColumn(label: Text('')), // close button
          ],
          rows: connections.map((c) => DataRow(cells: [
            DataCell(
              SizedBox(
                width: 220,
                child: Text(c.target,
                    overflow: TextOverflow.ellipsis,
                    style: YLText.mono.copyWith(fontSize: 13)),
              ),
            ),
            DataCell(Text(c.processName, style: YLText.body)),
            DataCell(Text(c.rule, style: YLText.body)),
            DataCell(Text(_fmt(c.download), style: YLText.mono.copyWith(fontSize: 13))),
            DataCell(Text(_fmt(c.upload), style: YLText.mono.copyWith(fontSize: 13))),
            DataCell(Text(c.durationText, style: YLText.mono.copyWith(fontSize: 13))),
            DataCell(IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: YLColors.error,
              padding: EdgeInsets.zero,
              onPressed: () => onClose(c.id),
            )),
          ])).toList(),
        ),
      ),
    );
  }

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ------------------------------------------------------------------
// Proxy stats bar — top 5 proxies by download
// ------------------------------------------------------------------

class _ProxyStatsBar extends StatelessWidget {
  final List<ProxyStats> stats;
  const _ProxyStatsBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: stats.map((ps) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${ps.proxyName}  ${ps.connectionCount}  ${_fmtBytes(ps.totalDownload)}',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: isDark ? YLColors.zinc400 : YLColors.zinc600,
            ),
          ),
        );
      }).toList(),
    );
  }

  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}K';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
  }
}
