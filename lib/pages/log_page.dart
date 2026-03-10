import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/rule.dart';
import '../providers/core_provider.dart';
import '../providers/log_provider.dart';
import '../providers/rule_provider.dart';
import '../services/mihomo_stream.dart';

class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final status = ref.watch(coreStatusProvider);
    final isRunning = status == CoreStatus.running;

    if (!isRunning) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.list_alt_outlined,
                  size: 64,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant),
              const SizedBox(height: 16),
              Text(s.notConnectedHintLog,
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    return Scaffold(
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

    // Terminal dark theme for desktop
    final bgColor = isDesktop ? const Color(0xFF1E1E1E) : null;
    final controlsBg = isDesktop
        ? const Color(0xFF2D2D2D)
        : Theme.of(context).colorScheme.surfaceContainerLow;
    final searchFillColor = isDesktop
        ? const Color(0xFF3C3C3C)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final searchTextColor =
        isDesktop ? const Color(0xFFD4D4D4) : null;
    final statusBarBg = isDesktop
        ? const Color(0xFF007ACC)
        : Theme.of(context).colorScheme.surfaceContainerLow;
    final statusBarTextColor =
        isDesktop ? Colors.white : null;

    return Container(
      color: bgColor,
      child: Column(
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
                          color: searchTextColor,
                          fontFamily: isDesktop ? 'monospace' : null),
                      decoration: InputDecoration(
                        hintText: _regexMode
                            ? s.searchLogsRegexHint
                            : s.searchLogsHint,
                        hintStyle: TextStyle(
                            fontSize: 12,
                            color: isDesktop
                                ? const Color(0xFF6A6A6A)
                                : null),
                        prefixIcon: Icon(Icons.search,
                            size: 16,
                            color: isDesktop
                                ? const Color(0xFF6A6A6A)
                                : null),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _regexError = false;
                                  });
                                },
                                child: Icon(Icons.clear,
                                    size: 14,
                                    color: isDesktop
                                        ? const Color(0xFF6A6A6A)
                                        : null),
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
                        setState(() {
                          _searchQuery = trimmed;
                          _regexError = hasError;
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
                            ? (isDesktop
                                ? const Color(0xFF0E639C)
                                : Theme.of(context)
                                    .colorScheme
                                    .primaryContainer)
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
                                ? (isDesktop
                                    ? Colors.white
                                    : Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer)
                                : (isDesktop
                                    ? const Color(0xFF6A6A6A)
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
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
                          ? (isDesktop
                              ? const Color(0xFF4EC9B0)
                              : Theme.of(context).colorScheme.primary)
                          : (isDesktop
                              ? const Color(0xFF6A6A6A)
                              : null)),
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
                  icon: Icon(Icons.delete_outline,
                      size: 16,
                      color: isDesktop
                          ? const Color(0xFF6A6A6A)
                          : null),
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
                        style: TextStyle(
                          color: isDesktop
                              ? const Color(0xFF6A6A6A)
                              : Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color,
                        )))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return _LogTile(
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
                        color: statusBarTextColor ??
                            Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color)),
                const Spacer(),
                if (_regexMode)
                  Text('REGEX',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isDesktop
                              ? const Color(0xFFFFC83D)
                              : Theme.of(context)
                                  .colorScheme
                                  .primary)),
                if (_regexMode) const SizedBox(width: 8),
                Text(s.logLevelLabel(level.toUpperCase()),
                    style: TextStyle(
                        fontSize: 11,
                        color: statusBarTextColor ??
                            Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<LogEntry> _filterLogs(List<LogEntry> logs) {
    final level = ref.read(logLevelProvider);
    final levelOrder = {
      'debug': 0,
      'info': 1,
      'warning': 2,
      'error': 3
    };
    final minLevel = levelOrder[level] ?? 1;

    var filtered = logs
        .where((l) => (levelOrder[l.type] ?? 1) >= minLevel)
        .toList();

    if (_searchQuery.isNotEmpty) {
      if (_regexMode) {
        try {
          final regex =
              RegExp(_searchQuery, caseSensitive: false);
          filtered =
              filtered.where((l) => regex.hasMatch(l.payload)).toList();
        } catch (_) {
          // Invalid regex — show nothing to indicate error
          return [];
        }
      } else {
        final q = _searchQuery.toLowerCase();
        filtered = filtered
            .where((l) => l.payload.toLowerCase().contains(q))
            .toList();
      }
    }

    return filtered;
  }
}

class _LogTile extends StatelessWidget {
  final LogEntry entry;
  final bool isDesktop;
  const _LogTile({required this.entry, this.isDesktop = false});

  @override
  Widget build(BuildContext context) {
    final timeColor = isDesktop
        ? const Color(0xFF569CD6) // VS Code blue for timestamps
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final payloadColor = isDesktop
        ? _desktopPayloadColor(entry.type)
        : _mobilePayloadColor(entry.type, context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
            '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
            '${entry.timestamp.second.toString().padLeft(2, '0')} ',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: timeColor,
            ),
          ),
          // Level indicator dot (mobile) or bracket tag (desktop)
          if (isDesktop)
            Text(
              '[${entry.type.toUpperCase().padRight(7)}] ',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: _levelTagColor(entry.type),
                fontWeight: FontWeight.bold,
              ),
            )
          else
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 3, right: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _levelDotColor(entry.type),
              ),
            ),
          // Payload
          Expanded(
            child: SelectableText(
              entry.payload,
              style: TextStyle(
                fontSize: isDesktop ? 12 : 12,
                fontFamily: 'monospace',
                height: 1.5,
                color: payloadColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _levelTagColor(String type) {
    switch (type) {
      case 'error':
        return const Color(0xFFF44747); // VS Code red
      case 'warning':
        return const Color(0xFFFFCC00); // yellow
      case 'debug':
        return const Color(0xFF6A9955); // VS Code green comment
      default:
        return const Color(0xFF4EC9B0); // VS Code teal (info)
    }
  }

  Color _desktopPayloadColor(String type) {
    switch (type) {
      case 'error':
        return const Color(0xFFF44747);
      case 'warning':
        return const Color(0xFFCE9178); // VS Code string orange
      case 'debug':
        return const Color(0xFF6A9955);
      default:
        return const Color(0xFFD4D4D4); // VS Code default text
    }
  }

  Color _mobilePayloadColor(String type, BuildContext context) {
    switch (type) {
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      default:
        return Theme.of(context).colorScheme.onSurface;
    }
  }

  Color _levelDotColor(String type) {
    switch (type) {
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'debug':
        return Colors.grey;
      default:
        return Colors.green;
    }
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
        // Summary
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
          color:
              Theme.of(context).colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Icon(Icons.rule_folder_outlined,
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
                        return _RuleTile(rule: filtered[index]);
                      },
                    ),
        ),
      ],
    );
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

class _RuleTile extends StatelessWidget {
  final RuleInfo rule;
  const _RuleTile({required this.rule});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 96,
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _typeColor(context).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              rule.type,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _typeColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.payload.isEmpty ? '*' : rule.payload,
                  style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
                if (rule.size > 0)
                  Text('${rule.size} 条',
                      style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              rule.proxy,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context)
                    .colorScheme
                    .onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(BuildContext context) {
    switch (rule.type) {
      case 'DOMAIN-SUFFIX':
      case 'DOMAIN':
        return Colors.blue;
      case 'DOMAIN-KEYWORD':
        return Colors.teal;
      case 'GEOIP':
        return Colors.orange;
      case 'RULE-SET':
        return Colors.purple;
      case 'MATCH':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
