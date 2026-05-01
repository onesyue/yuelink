import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_strings.dart';
import '../../domain/models/connection.dart';
import 'providers/connections_providers.dart';
import '../../core/providers/core_provider.dart';
import '../../shared/widgets/empty_state.dart';
import '../../theme.dart';
import 'widgets/connection_tile.dart';
import 'widgets/proxy_stats_bar.dart';
import 'widgets/summary_bar.dart';

class ConnectionsPage extends ConsumerStatefulWidget {
  const ConnectionsPage({super.key});

  @override
  ConsumerState<ConnectionsPage> createState() => _ConnectionsPageState();
}

enum _SortColumn { target, process, rule, download, upload, duration }

class _ConnectionsPageState extends ConsumerState<ConnectionsPage> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
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
    if (identical(list, _sortedInput) &&
        _sortCol == _sortedCol &&
        _sortAsc == _sortedAsc) {
      return _sortedCache!;
    }
    final copy = List<ActiveConnection>.from(list);
    copy.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case _SortColumn.target:
          cmp = a.target.compareTo(b.target);
        case _SortColumn.process:
          cmp = a.processName.compareTo(b.processName);
        case _SortColumn.rule:
          cmp = a.rule.compareTo(b.rule);
        case _SortColumn.download:
          cmp = a.download.compareTo(b.download);
        case _SortColumn.upload:
          cmp = a.upload.compareTo(b.upload);
        case _SortColumn.duration:
          cmp = a.start.compareTo(b.start);
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
    // Debounce search input — typing fires onChanged on every keystroke,
    // and pushing each one straight into connectionSearchProvider would
    // re-run filteredConnectionsProvider on every character. 200 ms is
    // below human-perceptible delay but enough to coalesce 5–6 keystrokes
    // of a fast typist into one filter pass.
    _searchCtrl.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 200), () {
        if (mounted) {
          ref.read(connectionSearchProvider.notifier).state = _searchCtrl.text;
        }
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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
                  child: Icon(
                    Icons.cable_rounded,
                    size: 48,
                    color: isDark ? YLColors.zinc700 : YLColors.zinc300,
                  ),
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

    // Don't watch the whole snapshot at the top level — it changes every
    // 500 ms (per ConnectionRepository throttle) and would rebuild the
    // entire page including the table. Instead use thin derived providers
    // that only fire when the specific value the page header cares about
    // actually flips. `filteredConnectionsProvider` is intentionally NOT
    // watched here — it produces a fresh List every tick; watching it at
    // the parent level would rebuild the whole scaffold every 500 ms.
    // The Count Consumer and the list Consumer below each watch their
    // narrowest slice of it locally.
    final isEmpty = ref.watch(connectionsEmptyProvider);
    final actions = ref.read(connectionActionsProvider);

    return Scaffold(
      appBar: _isSubPage
          ? AppBar(leading: const BackButton(), title: Text(s.navConnections))
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The AppBar already carries this secondary page's title.
          // Keep a small top gutter before the summary bar instead of
          // rendering a second large in-body title.
          const SizedBox(height: 12),

          // Summary bar — isolated Consumer so the bar rebuilds on totals
          // change without rebuilding the rest of the page.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Consumer(
              builder: (context, ref, _) {
                final totals = ref.watch(connectionsTotalsProvider);
                return SummaryBar(
                  downloadTotal: totals.down,
                  uploadTotal: totals.up,
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Proxy stats (collapsible) — already in its own Consumer.
          if (!isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Consumer(
                builder: (context, ref, _) {
                  final stats = ref.watch(proxyStatsProvider);
                  if (stats.isEmpty) return const SizedBox.shrink();
                  // Provider already caps at the top 5 — no client-side
                  // trim or copy needed here.
                  return ProxyStatsBar(stats: stats);
                },
              ),
            ),
          const SizedBox(height: 12),

          // Search + actions bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ConnectionsSearchField(
                    controller: _searchCtrl,
                    hintText: s.searchConnHint,
                    onClear: () {
                      _searchDebounce?.cancel();
                      ref.read(connectionSearchProvider.notifier).state = '';
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: isEmpty
                        ? Colors.transparent
                        : YLColors.errorLight.withValues(
                            alpha: isDark ? 0.1 : 0.5,
                          ),
                    borderRadius: BorderRadius.circular(YLRadius.lg),
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.delete_sweep_rounded,
                      color: isEmpty ? YLColors.zinc500 : YLColors.error,
                    ),
                    tooltip: s.closeAll,
                    onPressed: isEmpty
                        ? null
                        : () => _confirmCloseAll(context, actions),
                  ),
                ),
              ],
            ),
          ),

          // Count badge — only rebuilds when the filtered-list *length*
          // flips (cheap int identity), not on every 500 ms tick. The
          // total count already uses a .select internally.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Consumer(
              builder: (context, ref, _) {
                final filteredCount = ref.watch(
                  filteredConnectionsProvider.select((l) => l.length),
                );
                final totalCount = ref.watch(connectionCountProvider);
                return Text(
                  filteredCount != totalCount
                      ? s.connectionsCountFiltered(filteredCount)
                      : s.connectionsCount(filteredCount),
                  style: YLText.caption.copyWith(
                    color: YLColors.zinc500,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),

          // Connections list — own Consumer so the 500 ms rebuild is
          // scoped to this subtree. The parent Scaffold / AppBar /
          // summary / search row sit outside this rebuild path.
          Expanded(
            child: Consumer(
              builder: (context, ref, _) {
                final filtered = ref.watch(filteredConnectionsProvider);
                if (filtered.isEmpty) {
                  return Center(
                    child: YLEmptyState(
                      icon: isEmpty
                          ? Icons.cable_rounded
                          : Icons.search_off_rounded,
                      title: isEmpty
                          ? s.noActiveConnections
                          : s.noMatchingConnections,
                    ),
                  );
                }
                if (Platform.isMacOS ||
                    Platform.isWindows ||
                    Platform.isLinux) {
                  return _ConnectionsDataTable(
                    connections: _sorted(filtered),
                    sortColumn: _sortCol,
                    ascending: _sortAsc,
                    onSort: (col, asc) => setState(() {
                      _sortCol = col;
                      _sortAsc = asc;
                    }),
                    onClose: (id) => actions.close(id),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 32,
                  ),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  addAutomaticKeepAlives: false,
                  itemBuilder: (context, i) => ConnectionTile(
                    connection: filtered[i],
                    onClose: () => actions.close(filtered[i].id),
                  ),
                );
              },
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YLRadius.xl),
        ),
        title: Text(s.closeAllDialogTitle, style: YLText.titleLarge),
        content: Text(s.closeAllDialogMessage, style: YLText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              s.cancel,
              style: TextStyle(
                color: isDark ? YLColors.zinc400 : YLColors.zinc600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              actions.closeAll();
            },
            style: FilledButton.styleFrom(
              backgroundColor: YLColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YLRadius.pill),
              ),
            ),
            child: Text(s.closeAll),
          ),
        ],
      ),
    );
  }
}

// ── Desktop: Sortable DataTable ───────────────────────────────────────────────

// Column definitions for the virtualized table. Fixed widths so the body
// rows can be laid out without measuring siblings, and so we can use
// `itemExtent` on ListView.builder for max scroll perf.
class _Col {
  final String label;
  final _SortColumn? sortBy;
  final double width;
  final TextAlign align;
  const _Col(
    this.label,
    this.sortBy,
    this.width, [
    this.align = TextAlign.left,
  ]);
}

/// Desktop connections table — replaces the previous Material `DataTable`
/// which built every row up-front (`connections.map(...).toList()`). With
/// 500+ connections that was 500+ widgets created on every 500ms tick.
///
/// This implementation:
/// - Uses `ListView.builder` so only visible rows are realised.
/// - Uses `itemExtent` so the list can short-circuit layout — every row is
///   exactly 44px tall, no measurement pass needed.
/// - Sticky header row outside the ListView.
/// - Independent vertical / horizontal scrolling via a single horizontal
///   `SingleChildScrollView` wrapping the whole table (~1000px wide).
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

  static const double _rowHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cols = <_Col>[
      _Col(s.detailTarget, _SortColumn.target, 240),
      _Col(s.detailProcess, _SortColumn.process, 160),
      _Col(s.detailRule, _SortColumn.rule, 140),
      _Col(s.detailDownload, _SortColumn.download, 100, TextAlign.right),
      _Col(s.detailUpload, _SortColumn.upload, 100, TextAlign.right),
      _Col(s.detailDuration, _SortColumn.duration, 100, TextAlign.right),
      const _Col('', null, 48),
    ];
    final tableWidth =
        cols.fold<double>(0, (sum, c) => sum + c.width) + cols.length * 16;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: SizedBox(
        width: tableWidth,
        child: Column(
          children: [
            _HeaderRow(
              cols: cols,
              sortColumn: sortColumn,
              ascending: ascending,
              onSort: onSort,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: connections.length,
                itemExtent: _rowHeight,
                // Cache 10 viewports above/below for smoother fast scroll
                cacheExtent: _rowHeight * 30,
                itemBuilder: (ctx, i) => _ConnectionRow(
                  conn: connections[i],
                  cols: cols,
                  onClose: onClose,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final List<_Col> cols;
  final _SortColumn sortColumn;
  final bool ascending;
  final void Function(_SortColumn col, bool asc) onSort;
  const _HeaderRow({
    required this.cols,
    required this.sortColumn,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: cols.map((c) {
          final headerStyle = YLText.label.copyWith(
            fontWeight: FontWeight.w700,
          );
          final isSorted = c.sortBy != null && c.sortBy == sortColumn;
          final cell = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: c.align == TextAlign.right
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Text(c.label, style: headerStyle),
                if (isSorted)
                  Icon(
                    ascending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                    color: YLColors.zinc500,
                  ),
              ],
            ),
          );
          final boxed = SizedBox(width: c.width, child: cell);
          if (c.sortBy == null) return boxed;
          return InkWell(
            onTap: () => onSort(c.sortBy!, isSorted ? !ascending : true),
            child: boxed,
          );
        }).toList(),
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  final ActiveConnection conn;
  final List<_Col> cols;
  final void Function(String id) onClose;
  const _ConnectionRow({
    required this.conn,
    required this.cols,
    required this.onClose,
  });

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _textCell(
    String text,
    double width,
    TextAlign align, {
    TextStyle? style,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: style ?? YLText.body,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mono = YLText.mono.copyWith(fontSize: 13);
    return Row(
      children: [
        _textCell(conn.target, cols[0].width, TextAlign.left, style: mono),
        _textCell(conn.processName, cols[1].width, TextAlign.left),
        _textCell(conn.rule, cols[2].width, TextAlign.left),
        _textCell(
          _fmt(conn.download),
          cols[3].width,
          TextAlign.right,
          style: mono,
        ),
        _textCell(
          _fmt(conn.upload),
          cols[4].width,
          TextAlign.right,
          style: mono,
        ),
        _textCell(
          conn.durationText,
          cols[5].width,
          TextAlign.right,
          style: mono,
        ),
        SizedBox(
          width: cols[6].width,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: YLColors.error,
            padding: EdgeInsets.zero,
            onPressed: () => onClose(conn.id),
          ),
        ),
      ],
    );
  }
}

/// Search input for the connections page.
///
/// Extracted so the suffix clear-button visibility can be driven by a
/// `ListenableBuilder` that listens to [controller] directly, rather than
/// relying on the parent page rebuilding. The parent used to rebuild
/// implicitly every 500 ms when it watched `filteredConnectionsProvider`;
/// after P4-B scoped that watch into a local Consumer, the clear button
/// would get stuck in its previous state until some other rebuild trigger
/// happened. Listening to the controller inside this widget keeps the
/// refresh range limited to this subtree.
///
/// [onClear] runs AFTER `controller.clear()` has already been called —
/// it's the place for parent-side side-effects (cancelling debounce,
/// resetting provider state).
@visibleForTesting
class ConnectionsSearchField extends StatelessWidget {
  const ConnectionsSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(boxShadow: YLShadow.card(context)),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final hasText = controller.text.isNotEmpty;
          return TextField(
            controller: controller,
            style: YLText.body,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: YLText.body.copyWith(color: YLColors.zinc500),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 20,
                color: YLColors.zinc400,
              ),
              suffixIcon: hasText
                  ? IconButton(
                      icon: const Icon(
                        Icons.cancel_rounded,
                        size: 18,
                        color: YLColors.zinc400,
                      ),
                      onPressed: () {
                        controller.clear();
                        onClear();
                      },
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}
