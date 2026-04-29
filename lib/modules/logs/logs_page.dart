import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_strings.dart';
import '../../shared/app_notifier.dart';
import '../../shared/log_export_service.dart';
import '../../shared/telemetry.dart';
import '../../shared/widgets/empty_state.dart';
import '../../domain/models/rule.dart';
import '../../core/providers/core_provider.dart';
import 'providers/logs_providers.dart';
import 'providers/rule_provider.dart';
import '../../domain/logs/log_entry.dart';
import 'widgets/log_tile.dart';
import 'widgets/rule_tile.dart';

class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Always show AppBar — this page is always entered via Navigator.push()
  // from Settings on all platforms.
  static const bool _isSubPage = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _exportLogs(BuildContext context, WidgetRef ref) async {
    final logs = ref.read(logEntriesProvider);
    if (logs.isEmpty) {
      AppNotifier.warning(S.current.exportLogsEmpty);
      return;
    }

    try {
      final buffer = StringBuffer();
      for (final entry in logs.reversed) {
        final ts = entry.timestamp;
        final time =
            '${ts.year}-${ts.month.toString().padLeft(2, '0')}-'
            '${ts.day.toString().padLeft(2, '0')} '
            '${ts.hour.toString().padLeft(2, '0')}:'
            '${ts.minute.toString().padLeft(2, '0')}:'
            '${ts.second.toString().padLeft(2, '0')}';
        buffer.writeln('[$time] [${entry.type.toUpperCase()}] ${entry.payload}');
      }

      final now = DateTime.now();
      final datePart =
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final fileName = 'yuelink-logs-$datePart.txt';

      final result = await LogExportService.saveText(
        fileName: fileName,
        content: buffer.toString(),
        dialogTitle: S.current.exportLogs,
      );
      if (result.cancelled) return;
      if (result.saved) {
        Telemetry.event(TelemetryEvents.logExport);
        AppNotifier.success(
          '${S.current.exportLogsSuccess}: ${result.path ?? fileName}',
        );
      } else {
        AppNotifier.error(
          '${S.current.exportLogsFailed}: ${result.error ?? ''}',
        );
      }
    } catch (e) {
      AppNotifier.error('${S.current.exportLogsFailed}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final status = ref.watch(coreStatusProvider);
    final isRunning = status == CoreStatus.running;

    if (!isRunning) {
      return Scaffold(
        appBar: _isSubPage
            ? AppBar(leading: const BackButton(), title: Text(s.tabLogs))
            : null,
        body: Center(
          child: YLEmptyState(
            icon: Icons.list_alt_rounded,
            title: s.notConnectedHintLog,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _isSubPage
            ? AppBar(
                leading: const BackButton(),
                title: Text(s.tabLogs),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.file_download_rounded, size: 20),
                    tooltip: s.exportLogs,
                    onPressed: () => _exportLogs(context, ref),
                  ),
                ],
              )
            : null,
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: s.tabLogs),
              Tab(text: s.tabRules),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _LogsTab(),
                _RulesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Logs tab
// ══════════════════════════════════════════════════════════════════════════════

class _LogsTab extends ConsumerStatefulWidget {
  const _LogsTab();

  @override
  ConsumerState<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<_LogsTab> {
  String _searchQuery = '';
  bool _regexMode = false;
  bool _regexError = false;
  RegExp? _cachedRegex;
  final _searchController = TextEditingController();

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final logs = ref.watch(logEntriesProvider);
    final level = ref.watch(logLevelProvider);
    final filtered = _filterLogs(logs);
    final isDesktop = _isDesktop;

    final theme = Theme.of(context);
    final controlsBg = theme.colorScheme.surfaceContainerLow;
    final searchFillColor = theme.colorScheme.surfaceContainerHighest;
    final statusBarBg = theme.colorScheme.surfaceContainerLow;

    return Column(
        children: [
          // Controls toolbar
          Container(
            color: controlsBg,
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 28,
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(
                          fontSize: 12,
                          fontFamily: isDesktop ? 'monospace' : null),
                      decoration: InputDecoration(
                        hintText: _regexMode
                            ? s.searchLogsRegexHint
                            : s.searchLogsHint,
                        hintStyle: const TextStyle(fontSize: 12),
                        prefixIcon: const Icon(Icons.search, size: 16),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _regexError = false;
                                  });
                                },
                                child: const Icon(Icons.clear, size: 14),
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: _regexError
                              ? const BorderSide(
                                  color: Colors.red, width: 1)
                              : BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: _regexError
                              ? const BorderSide(
                                  color: Colors.red, width: 1)
                              : BorderSide.none,
                        ),
                        filled: true,
                        fillColor: searchFillColor,
                      ),
                      onChanged: (v) {
                        final trimmed = v.trim();
                        bool hasError = false;
                        if (_regexMode && trimmed.isNotEmpty) {
                          try {
                            RegExp(trimmed);
                          } catch (_) {
                            hasError = true;
                          }
                        }
                        RegExp? compiled;
                        if (_regexMode && trimmed.isNotEmpty && !hasError) {
                          try {
                            compiled = RegExp(trimmed, caseSensitive: false);
                          } catch (_) {}
                        }
                        setState(() {
                          _searchQuery = trimmed;
                          _regexError = hasError;
                          _cachedRegex = compiled;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                // Regex toggle
                Tooltip(
                  message: s.regexSearch,
                  child: InkWell(
                    onTap: () => setState(() {
                      _regexMode = !_regexMode;
                      _regexError = false;
                    }),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _regexMode
                            ? theme.colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: Text('.*',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: _regexMode
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                          )),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                // Level filter
                PopupMenuButton<String>(
                  initialValue: level,
                  onSelected: (v) =>
                      ref.read(logLevelProvider.notifier).state = v,
                  tooltip: s.logLevelSetting,
                  icon: Icon(Icons.filter_list,
                      size: 16,
                      color: level != 'info'
                          ? theme.colorScheme.primary
                          : null),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'debug', child: Text('Debug')),
                    PopupMenuItem(value: 'info', child: Text('Info')),
                    PopupMenuItem(
                        value: 'warning', child: Text('Warning')),
                    PopupMenuItem(
                        value: 'error', child: Text('Error')),
                  ],
                ),
                IconButton(
                  onPressed: () =>
                      ref.read(logEntriesProvider.notifier).clear(),
                  icon: const Icon(Icons.delete_rounded, size: 16),
                  tooltip: s.clearLogs,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          // Log entries
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(s.noLogs,
                        style: theme.textTheme.bodyMedium))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    itemCount: filtered.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    itemBuilder: (context, index) {
                      return LogTile(
                          entry: filtered[index],
                          isDesktop: isDesktop);
                    },
                  ),
          ),

          // Status bar
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 3),
            color: statusBarBg,
            child: Row(
              children: [
                Text(s.logsCount(filtered.length),
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color)),
                const Spacer(),
                if (_regexMode)
                  Text('REGEX',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary)),
                if (_regexMode) const SizedBox(width: 8),
                Text(s.logLevelLabel(level.toUpperCase()),
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color)),
              ],
            ),
          ),
        ],
    );
  }

  static const _levelOrder = {
    'debug': 0,
    'info': 1,
    'warning': 2,
    'error': 3,
  };

  List<LogEntry> _filterLogs(List<LogEntry> logs) {
    final minLevel = _levelOrder[ref.read(logLevelProvider)] ?? 1;
    final hasSearch = _searchQuery.isNotEmpty;
    final noLevelFilter = minLevel == 0; // 'debug' lets everything through

    // Fast path — both filters no-op. Previously this still allocated a
    // fresh List on every build (widget rebuilds from tab switches,
    // scroll, keyboard events, log batch flushes). Returning `logs` keeps
    // identity stable and lets ListView.builder skip item diffs.
    if (!hasSearch && noLevelFilter) return logs;

    RegExp? regex;
    String? lowerQuery;
    if (hasSearch) {
      if (_regexMode) {
        regex = _cachedRegex;
        if (regex == null) return const []; // invalid regex — caller knows
      } else {
        lowerQuery = _searchQuery.toLowerCase();
      }
    }

    // Single-pass predicate so level + search share one allocation rather
    // than two consecutive `.where().toList()` chains.
    return logs.where((l) {
      if (!noLevelFilter &&
          (_levelOrder[l.type] ?? 1) < minLevel) {
        return false;
      }
      if (!hasSearch) return true;
      if (regex != null) return regex.hasMatch(l.payload);
      return l.payload.toLowerCase().contains(lowerQuery!);
    }).toList();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Rules tab
// ══════════════════════════════════════════════════════════════════════════════

class _RulesTab extends ConsumerStatefulWidget {
  const _RulesTab();

  @override
  ConsumerState<_RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends ConsumerState<_RulesTab> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(rulesProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rules = ref.watch(rulesProvider);
    final filtered = _filterRules(rules);

    return Column(
      children: [
        // Summary with type breakdown
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
          color:
              Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.rule_folder_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(s.rulesCount(rules.length),
                      style:
                          Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  if (_searchQuery.isNotEmpty)
                    Text(s.matchedRulesCount(filtered.length),
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              if (rules.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _buildTypeSummary(rules, context),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),

        // Search
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: s.searchRulesHint,
                      prefixIcon:
                          const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              child:
                                  const Icon(Icons.clear, size: 16),
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
                onPressed: () =>
                    ref.read(rulesProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: S.of(context).retry,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),

        // Rules list
        Expanded(
          child: rules.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text(s.noMatchingRules,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return RuleTile(rule: filtered[index]);
                      },
                    ),
        ),
      ],
    );
  }

  List<Widget> _buildTypeSummary(
      List<RuleInfo> rules, BuildContext context) {
    final counts = <String, int>{};
    for (final r in rules) {
      counts[r.type] = (counts[r.type] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) {
      return GestureDetector(
        onTap: () {
          _searchController.text = e.key;
          setState(() => _searchQuery = e.key);
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${e.key} (${e.value})',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }).toList();
  }

  List<RuleInfo> _filterRules(List<RuleInfo> rules) {
    if (_searchQuery.isEmpty) return rules;
    final q = _searchQuery.toLowerCase();
    return rules
        .where((r) =>
            r.type.toLowerCase().contains(q) ||
            r.payload.toLowerCase().contains(q) ||
            r.proxy.toLowerCase().contains(q))
        .toList();
  }
}

