import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../i18n/app_strings.dart';
import '../../../theme.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/widgets/yl_scaffold.dart';

/// 原生意见反馈页 — 替代外跳 Telegram。
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _ctrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      AppNotifier.error(S.current.feedbackEmpty);
      return;
    }

    setState(() => _submitting = true);
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      try {
        final uri = Uri.parse('https://yue.yuebao.website/api/client/feedback');
        final request = await client.postUrl(uri);
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('Accept', 'application/json');
        request.write(jsonEncode({
          'content': text,
          'contact': _contactCtrl.text.trim(),
        }));
        final response = await request.close();
        await response.drain();
        if (!mounted) return;

        if (response.statusCode >= 200 && response.statusCode < 300) {
          AppNotifier.success(S.current.feedbackSuccess);
          Navigator.of(context).pop();
        } else {
          AppNotifier.error(S.current.feedbackFailed);
        }
      } finally {
        client.close();
      }
    } catch (_) {
      if (mounted) AppNotifier.error(S.current.feedbackNetError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.current;
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    return YLLargeTitleScaffold(
      title: s.feedbackTitle,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              YLSpacing.lg, 0, YLSpacing.lg, YLSpacing.xl),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _SectionLabel(
                  isEn ? 'Describe your issue or suggestion' : '描述你遇到的问题或建议',
                  isDark: isDark),
              const SizedBox(height: YLSpacing.sm),
              _FieldShell(
                isDark: isDark,
                child: TextField(
                  controller: _ctrl,
                  maxLines: 6,
                  maxLength: 500,
                  style: YLText.body.copyWith(
                    fontSize: 15,
                    color: isDark ? Colors.white : YLColors.zinc900,
                  ),
                  decoration: InputDecoration(
                    hintText: s.feedbackHint,
                    hintStyle: YLText.body
                        .copyWith(color: YLColors.zinc400, fontSize: 15),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(YLSpacing.md),
                    counterStyle:
                        YLText.caption.copyWith(color: YLColors.zinc500),
                  ),
                ),
              ),
              const SizedBox(height: YLSpacing.lg),
              _SectionLabel(
                  isEn ? 'Contact info (optional)' : '联系方式（选填）',
                  isDark: isDark),
              const SizedBox(height: YLSpacing.sm),
              _FieldShell(
                isDark: isDark,
                child: TextField(
                  controller: _contactCtrl,
                  style: YLText.body.copyWith(
                    fontSize: 15,
                    color: isDark ? Colors.white : YLColors.zinc900,
                  ),
                  decoration: InputDecoration(
                    hintText: s.feedbackContactHint,
                    hintStyle: YLText.body
                        .copyWith(color: YLColors.zinc400, fontSize: 15),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(YLSpacing.md),
                  ),
                ),
              ),
              const SizedBox(height: YLSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isDark ? Colors.white : YLColors.zinc900,
                    foregroundColor:
                        isDark ? YLColors.zinc900 : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YLRadius.lg),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(s.feedbackSubmit),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionLabel(this.text, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: YLSpacing.xs),
      child: Text(
        text,
        style: YLText.caption.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: isDark ? YLColors.zinc400 : YLColors.zinc500,
          letterSpacing: -0.05,
        ),
      ),
    );
  }
}

class _FieldShell extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _FieldShell({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(YLRadius.lg),
      child: Container(
        color: isDark ? YLColors.zinc900 : Colors.white,
        child: child,
      ),
    );
  }
}
