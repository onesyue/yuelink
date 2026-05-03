import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../i18n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/telemetry.dart';
import '../../../shared/widgets/setting_icon.dart';
import '../../../shared/widgets/yl_list.dart';
import '../../../shared/widgets/yl_scaffold.dart';
import '../../../theme.dart';

/// Read-only view of the last ~50 events recorded by [Telemetry]. Used as a
/// privacy-transparency surface: the user can always see exactly what we
/// intend to send before it leaves the device.
class TelemetryPreviewPage extends StatelessWidget {
  const TelemetryPreviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final events = Telemetry.recentEvents().reversed.toList();
    final clientId = Telemetry.clientId;
    final sessionId = Telemetry.sessionId;

    return YLLargeTitleScaffold(
      title: s.telemetryViewEvents,
      maxContentWidth: kYLSecondaryContentWidth,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: YLSpacing.sm),
            child: YLSection(
              children: [
                YLListTile(
                  leading: const YLSettingIcon(
                    icon: Icons.fingerprint_rounded,
                    color: Color(0xFF6366F1),
                  ),
                  title: s.telemetryClientId,
                  subtitle: clientId,
                  trailing: const Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: YLColors.zinc400,
                  ),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: clientId));
                    AppNotifier.success(S.current.copiedToClipboard);
                  },
                ),
                YLListTile(
                  leading: const YLSettingIcon(
                    icon: Icons.schedule_rounded,
                    color: Color(0xFF3B82F6),
                  ),
                  title: s.telemetrySessionId,
                  subtitle: sessionId,
                  trailing: const Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: YLColors.zinc400,
                  ),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: sessionId));
                    AppNotifier.success(S.current.copiedToClipboard);
                  },
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              YLSpacing.lg + YLSpacing.md,
              YLSpacing.lg,
              YLSpacing.lg + YLSpacing.md,
              YLSpacing.sm,
            ),
            child: Text(
              s.telemetryEventCount(events.length).toUpperCase(),
              style: YLText.caption.copyWith(
                color: isDark ? YLColors.zinc500 : YLColors.zinc500,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
        if (events.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(YLSpacing.xl),
                child: Text(
                  s.telemetryEmpty,
                  style: YLText.body.copyWith(
                    color: isDark ? YLColors.zinc500 : YLColors.zinc400,
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              YLSpacing.lg,
              0,
              YLSpacing.lg,
              YLSpacing.lg,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: YLSpacing.sm),
                  child: _EventTile(event: events[i]),
                ),
                childCount: events.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? YLColors.zinc900 : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final name = event['event'] as String? ?? '?';
    final tsMs = event['ts'] as int?;
    final time = tsMs != null
        ? DateTime.fromMillisecondsSinceEpoch(tsMs).toLocal()
        : null;
    final extra = Map<String, dynamic>.from(event)
      ..remove('event')
      ..remove('ts')
      ..remove('session_id')
      ..remove('seq')
      ..remove('platform')
      ..remove('version');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: YLSpacing.md,
        vertical: YLSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(YLRadius.md),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: YLText.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: isDark ? Colors.white : YLColors.zinc900,
                  ),
                ),
              ),
              if (time != null)
                Text(
                  _fmt(time),
                  style: YLText.caption.copyWith(
                    color: isDark ? YLColors.zinc500 : YLColors.zinc400,
                  ),
                ),
            ],
          ),
          if (extra.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              const JsonEncoder().convert(extra),
              style: YLText.caption.copyWith(
                fontFamily: 'monospace',
                color: isDark ? YLColors.zinc400 : YLColors.zinc600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime t) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }
}
