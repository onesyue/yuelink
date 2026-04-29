import 'package:flutter/material.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/widgets/yl_scaffold.dart';
import '../../../theme.dart';

class DnsQueryPage extends StatefulWidget {
  const DnsQueryPage({super.key});

  @override
  State<DnsQueryPage> createState() => _DnsQueryPageState();
}

class _DnsQueryPageState extends State<DnsQueryPage> {
  final _controller = TextEditingController();
  String _queryType = 'A';
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  static const _queryTypes = ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS', 'SOA'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _query() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await CoreManager.instance.api.queryDns(
        name,
        type: _queryType,
      );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldColor = isDark ? YLColors.zinc900 : Colors.white;
    final fieldBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return YLLargeTitleScaffold(
      title: s.dnsQuery,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            YLSpacing.lg,
            YLSpacing.sm,
            YLSpacing.lg,
            YLSpacing.lg,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: YLText.body.copyWith(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: s.domainHint,
                        hintStyle: YLText.body.copyWith(
                          color: YLColors.zinc500,
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: fieldColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(YLRadius.md),
                          borderSide: BorderSide(color: fieldBorder, width: 0.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(YLRadius.md),
                          borderSide: BorderSide(color: fieldBorder, width: 0.5),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: YLSpacing.md,
                          vertical: YLSpacing.md,
                        ),
                      ),
                      onSubmitted: (_) => _query(),
                    ),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: fieldColor,
                      borderRadius: BorderRadius.circular(YLRadius.md),
                      border: Border.all(color: fieldBorder, width: 0.5),
                    ),
                    child: DropdownButton<String>(
                      value: _queryType,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      borderRadius: BorderRadius.circular(YLRadius.md),
                      items: _queryTypes
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(
                                t,
                                style: YLText.body.copyWith(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _queryType = v);
                      },
                    ),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                  FilledButton(
                    onPressed: _loading ? null : _query,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YLRadius.md),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(s.query),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: YLSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(YLSpacing.md),
                  decoration: BoxDecoration(
                    color: YLColors.error.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(YLRadius.md),
                  ),
                  child: Text(
                    _error!,
                    style: YLText.body.copyWith(
                      color: YLColors.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: YLSpacing.lg),
                _ResultCard(result: _result!, queryType: _queryType, s: s),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> result;
  final String queryType;
  final S s;

  const _ResultCard({
    required this.result,
    required this.queryType,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = result['Status'] as int? ?? -1;
    final answers = result['Answer'] as List? ?? [];
    final ok = status == 0;
    final accent = ok ? YLColors.connected : YLColors.error;

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.error_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: YLSpacing.sm),
              Text(
                ok ? 'NOERROR' : 'Status: $status',
                style: YLText.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: YLSpacing.md),
          Container(
            height: 0.33,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
          const SizedBox(height: YLSpacing.md),
          if (answers.isEmpty)
            Text(
              s.noRecords,
              style: YLText.body.copyWith(color: YLColors.zinc500),
            )
          else
            ...answers.map(
              (a) => _AnswerRow(
                answer: a as Map<String, dynamic>,
                fallbackType: queryType,
              ),
            ),
        ],
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  final Map<String, dynamic> answer;
  final String fallbackType;

  const _AnswerRow({required this.answer, required this.fallbackType});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: YLColors.primary.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(YLRadius.sm),
            ),
            child: Text(
              '${answer['type'] ?? fallbackType}',
              style: YLText.caption.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: YLColors.primary,
              ),
            ),
          ),
          const SizedBox(width: YLSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  '${answer['data'] ?? ''}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: isDark ? YLColors.zinc200 : YLColors.zinc800,
                  ),
                ),
                if (answer['TTL'] != null)
                  Text(
                    'TTL: ${answer['TTL']}',
                    style: YLText.caption.copyWith(
                      fontSize: 11,
                      color: YLColors.zinc500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

