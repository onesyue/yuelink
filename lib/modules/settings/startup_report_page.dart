import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/kernel/core_manager.dart';
import '../../domain/models/startup_report.dart';
import '../../i18n/app_strings.dart';
import '../../shared/app_notifier.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/setting_icon.dart';
import '../../shared/widgets/yl_list.dart';
import '../../shared/widgets/yl_scaffold.dart';
import '../../theme.dart';

class StartupReportPage extends StatefulWidget {
  const StartupReportPage({super.key});

  @override
  State<StartupReportPage> createState() => _StartupReportPageState();
}

class _StartupReportPageState extends State<StartupReportPage> {
  StartupReport? _report;
  bool _loading = true;
  bool _logsExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Prefer in-memory report (set by CoreManager after startup)
    final inMemory = CoreManager.instance.lastReport;
    if (inMemory != null) {
      if (mounted) {
        setState(() {
          _report = inMemory;
          _loading = false;
        });
      }
      return;
    }
    final report = await StartupReport.load();
    if (mounted) {
      setState(() {
        _report = report;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return YLLargeTitleScaffold(
      title: s.diagnostics,
      actions: [
        if (_report != null)
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: s.copiedToClipboard,
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: _report!.toDebugString()),
              );
              AppNotifier.success(s.copiedToClipboard);
            },
          ),
      ],
      slivers: _loading
          ? const [
              SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
            ]
          : _report == null
          ? [
              SliverFillRemaining(
                child: Center(
                  child: YLEmptyState(
                    icon: Icons.assignment_rounded,
                    title: s.noData,
                  ),
                ),
              ),
            ]
          : _buildSlivers(context, isDark, _report!),
    );
  }

  List<Widget> _buildSlivers(
    BuildContext context,
    bool isDark,
    StartupReport report,
  ) {
    return [
      SliverToBoxAdapter(
        child: YLSection(
          header: 'OVERVIEW',
          children: [
            YLListTile(
              leading: const YLSettingIcon(
                icon: Icons.schedule_rounded,
                color: Color(0xFF6B7280),
              ),
              title: 'Timestamp',
              trailing: YLListTrailing.label(_fmtDate(report.timestamp)),
            ),
            YLListTile(
              leading: const YLSettingIcon(
                icon: Icons.devices_other_rounded,
                color: Color(0xFF3B82F6),
              ),
              title: 'Platform',
              trailing: YLListTrailing.label(report.platform),
            ),
            YLListTile(
              leading: YLSettingIcon(
                icon: report.overallSuccess
                    ? Icons.check_circle_rounded
                    : Icons.error_rounded,
                color: report.overallSuccess
                    ? YLColors.connected
                    : YLColors.error,
              ),
              title: 'Result',
              trailing: YLListTrailing.badge(
                text: report.overallSuccess ? 'SUCCESS' : 'FAILED',
                color: report.overallSuccess
                    ? YLColors.connected
                    : YLColors.error,
              ),
            ),
            if (!report.overallSuccess && report.failureSummary != null)
              YLListTile(
                leading: const YLSettingIcon(
                  icon: Icons.report_problem_rounded,
                  color: YLColors.error,
                ),
                title: 'Error',
                subtitle: report.failureSummary!,
              ),
          ],
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: YLSpacing.lg)),

      // ── Steps ───────────────────────────────────────────────────
      SliverToBoxAdapter(
        child: YLSection(
          header: 'STARTUP STEPS',
          children: [
            for (final step in report.steps) _StepRow(step: step, isDark: isDark),
          ],
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: YLSpacing.lg)),

      // ── Core logs (expandable) ──────────────────────────────────
      if (report.coreLogs.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: YLSection(
            header: 'GO CORE LOGS (${report.coreLogs.length} LINES)',
            children: [
              YLListTile(
                leading: const YLSettingIcon(
                  icon: Icons.terminal_rounded,
                  color: Color(0xFF6B7280),
                ),
                title: _logsExpanded ? 'Hide logs' : 'Show logs',
                trailing: Icon(
                  _logsExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                  color: isDark ? YLColors.zinc600 : YLColors.zinc400,
                ),
                onTap: () => setState(() => _logsExpanded = !_logsExpanded),
              ),
            ],
          ),
        ),
        if (_logsExpanded)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              YLSpacing.lg,
              YLSpacing.sm,
              YLSpacing.lg,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Container(
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
                  report.coreLogs.join('\n'),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                  ),
                ),
              ),
            ),
          ),
      ],
    ];
  }

  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}:'
        '${d.second.toString().padLeft(2, '0')}';
  }
}

// ── Helper widgets ───────────────────────────────────────────────────────────

/// One row per startup step. Uses [YLListTile] anatomy: icon (status),
/// title (step name), subtitle (error if any), trailing (duration label).
class _StepRow extends StatelessWidget {
  final StartupStep step;
  final bool isDark;
  const _StepRow({required this.step, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return YLListTile(
      leading: YLSettingIcon(
        icon: step.success
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
        color: step.success ? YLColors.connected : YLColors.error,
      ),
      title: step.name,
      subtitle: !step.success && step.error != null ? step.error! : null,
      trailing: YLListTrailing.label('${step.durationMs}ms'),
    );
  }
}
