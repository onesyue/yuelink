import 'package:flutter/material.dart';

import '../../i18n/app_strings.dart';
import '../../theme.dart';
import '../nps_service.dart';

/// Single-touch NPS bottom sheet: one 0-10 row + optional comment.
/// Dismisses with back-arrow tap; the score row submits immediately.
///
/// Show via [showNpsSheet] from the main tab frame after [NpsService.shouldShow]
/// returns true. Never blocks the user mid-action — only surface when the
/// user is idle on a top-level screen.
class NpsSheet extends StatefulWidget {
  const NpsSheet({super.key});

  @override
  State<NpsSheet> createState() => _NpsSheetState();
}

class _NpsSheetState extends State<NpsSheet> {
  int? _score;
  final _commentCtrl = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_score == null) return;
    setState(() => _submitted = true);
    await NpsService.submit(
      score: _score!,
      comment: _commentCtrl.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? YLColors.zinc800 : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(YLRadius.xl)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: YLColors.zinc300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _score == null
                ? '你向朋友推荐 YueLink 的可能性有多大？'
                : '想补充一句吗？',
            style: YLText.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            _score == null ? '0 完全不会 → 10 非常可能' : '（可选，最多 500 字）',
            style: YLText.caption.copyWith(color: YLColors.zinc500),
          ),
          const SizedBox(height: 16),
          if (_score == null)
            _ScoreRow(
              onPick: (v) {
                setState(() => _score = v);
              },
            )
          else ...[
            Text('评分：$_score',
                style: YLText.caption.copyWith(color: YLColors.zinc500)),
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: '什么地方可以做得更好？（可留空）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitted ? null : _submit,
                child: Text(S.current.confirm),
              ),
            ),
          ],
          if (_score == null) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () {
                  NpsService.recordDismiss();
                  Navigator.of(context).pop();
                },
                child: const Text('稍后再说'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 0-10 horizontal score picker — tap immediately registers.
class _ScoreRow extends StatelessWidget {
  final ValueChanged<int> onPick;
  const _ScoreRow({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, cons) {
        final w = (cons.maxWidth - 10) / 11;
        return Row(
          children: List.generate(11, (i) {
            final color = i <= 6
                ? const Color(0xFFEF4444)
                : i <= 8
                    ? const Color(0xFFF59E0B)
                    : YLColors.connected;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: InkWell(
                onTap: () => onPick(i),
                borderRadius: BorderRadius.circular(YLRadius.sm),
                child: Container(
                  width: w,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(YLRadius.sm),
                  ),
                  child: Text(
                    '$i',
                    style: YLText.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Show the sheet and register `nps_shown` telemetry.
/// Fire-and-forget — caller doesn't await.
Future<void> showNpsSheet(BuildContext context) {
  // Intentionally do not await the recordShown disk write before showing;
  // showing within the same frame avoids a use_build_context_synchronously
  // lint and the telemetry is non-critical.
  // ignore: unawaited_futures
  NpsService.recordShown();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const NpsSheet(),
  );
}
