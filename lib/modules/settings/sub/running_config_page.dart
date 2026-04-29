import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/widgets/yl_loading.dart';
import '../../../shared/widgets/yl_scaffold.dart';
import '../../../theme.dart';

class RunningConfigPage extends StatefulWidget {
  const RunningConfigPage({super.key});

  @override
  State<RunningConfigPage> createState() => _RunningConfigPageState();
}

class _RunningConfigPageState extends State<RunningConfigPage> {
  Map<String, dynamic>? _config;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await CoreManager.instance.api.getConfig();
      if (mounted) setState(() => _config = config);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return YLLargeTitleScaffold(
      title: s.runningConfig,
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: s.refresh,
        ),
      ],
      slivers: [
        if (_loading)
          const SliverFillRemaining(child: Center(child: YLLoading()))
        else if (_error != null)
          SliverFillRemaining(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(YLSpacing.xl),
                child: Text(
                  _error!,
                  style: YLText.body.copyWith(color: YLColors.error),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else if (_config == null)
          SliverFillRemaining(
            child: Center(
              child: Text(
                s.noData,
                style: YLText.body.copyWith(color: YLColors.zinc500),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              YLSpacing.lg,
              0,
              YLSpacing.lg,
              YLSpacing.xl,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _ConfigEntry(entry: _config!.entries.elementAt(index)),
                childCount: _config!.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _ConfigEntry extends StatelessWidget {
  final MapEntry<String, dynamic> entry;
  const _ConfigEntry({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final value = entry.value;
    final display = value is Map || value is List
        ? const JsonEncoder.withIndent('  ').convert(value)
        : '$value';
    return Padding(
      padding: const EdgeInsets.only(bottom: YLSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.key,
            style: YLText.label.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : YLColors.zinc900,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(YLSpacing.md),
            decoration: BoxDecoration(
              color: isDark ? YLColors.zinc900 : Colors.white,
              borderRadius: BorderRadius.circular(YLRadius.md),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
            child: SelectableText(
              display,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: isDark ? YLColors.zinc300 : YLColors.zinc700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
