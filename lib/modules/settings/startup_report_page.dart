import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/kernel/core_manager.dart';
import '../../domain/models/startup_report.dart';
import '../../l10n/app_strings.dart';
import '../../shared/app_notifier.dart';
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
      if (mounted) setState(() { _report = inMemory; _loading = false; });
      return;
    }
    final report = await StartupReport.load();
    if (mounted) setState(() { _report = report; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(s.diagnostics),
        actions: [
          if (_report != null)
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: s.copiedToClipboard,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _report!.toDebugString()));
                AppNotifier.success(s.copiedToClipboard);
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _report == null
              ? Center(child: Text(s.noData))
              : _buildBody(context, isDark, _report!),
    );
  }

  Widget _buildBody(BuildContext context, bool isDark, StartupReport report) {
    final divColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header ──────────────────────────────────────────────────
        _InfoCard(isDark: isDark, children: [
          _InfoRow(
            label: 'Timestamp',
            value: _fmtDate(report.timestamp),
            isDark: isDark,
          ),
          Divider(height: 1, color: divColor),
          _InfoRow(
            label: 'Platform',
            value: report.platform,
            isDark: isDark,
          ),
          Divider(height: 1, color: divColor),
          _InfoRow(
            label: 'Result',
            value: report.overallSuccess ? 'SUCCESS' : 'FAILED',
            valueColor: report.overallSuccess ? YLColors.connected : Colors.red,
            isDark: isDark,
          ),
          if (!report.overallSuccess && report.failureSummary != null) ...[
            Divider(height: 1, color: divColor),
            _InfoRow(
              label: 'Error',
              value: report.failureSummary!,
              valueColor: Colors.red,
              isDark: isDark,
            ),
          ],
        ]),
        const SizedBox(height: 16),

        // ── Steps ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'STARTUP STEPS',
            style: YLText.caption.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: YLColors.zinc400,
            ),
          ),
        ),
        _InfoCard(
          isDark: isDark,
          children: [
            for (var i = 0; i < report.steps.length; i++) ...[
              if (i > 0) Divider(height: 1, color: divColor),
              _StepRow(step: report.steps[i], isDark: isDark),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // ── Core logs (expandable) ──────────────────────────────────
        if (report.coreLogs.isNotEmpty) ...[
          InkWell(
            onTap: () => setState(() => _logsExpanded = !_logsExpanded),
            borderRadius: BorderRadius.circular(YLRadius.sm),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Row(
                children: [
                  Text(
                    'GO CORE LOGS (${report.coreLogs.length} lines)',
                    style: YLText.caption.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: YLColors.zinc400,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _logsExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: YLColors.zinc400,
                  ),
                ],
              ),
            ),
          ),
          if (_logsExpanded)
            _InfoCard(isDark: isDark, children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  report.coreLogs.join('\n'),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                  ),
                ),
              ),
            ]),
        ],
        const SizedBox(height: 32),
      ],
    );
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

class _InfoCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _InfoCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isDark;
  const _InfoRow(
      {required this.label,
      required this.value,
      this.valueColor,
      required this.isDark});

  @override
  Widget build(BuildContext context) {
    final vc = valueColor ?? (isDark ? YLColors.zinc200 : YLColors.zinc700);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(label,
              style: YLText.body
                  .copyWith(color: isDark ? YLColors.zinc400 : YLColors.zinc500)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: YLText.body.copyWith(
                  color: vc, fontFamily: 'monospace', fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final StartupStep step;
  final bool isDark;
  const _StepRow({required this.step, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            step.success
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 16,
            color: step.success ? YLColors.connected : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.name,
                    style: YLText.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: isDark ? YLColors.zinc200 : YLColors.zinc700)),
                if (!step.success && step.error != null)
                  Text(step.error!,
                      style: YLText.caption.copyWith(color: Colors.red)),
              ],
            ),
          ),
          Text(
            '${step.durationMs}ms',
            style: YLText.caption.copyWith(color: YLColors.zinc400),
          ),
        ],
      ),
    );
  }
}
