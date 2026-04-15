import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../i18n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/telemetry.dart';
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

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(s.telemetryViewEvents),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IdRow(
            label: s.telemetryClientId,
            value: clientId,
          ),
          Divider(
            height: 1,
            color: isDark ? YLColors.zinc700 : YLColors.zinc200,
          ),
          _IdRow(
            label: s.telemetrySessionId,
            value: sessionId,
          ),
          Divider(
            height: 1,
            color: isDark ? YLColors.zinc700 : YLColors.zinc200,
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              s.telemetryEventCount(events.length),
              style: YLText.caption.copyWith(
                color: isDark ? YLColors.zinc400 : YLColors.zinc500,
              ),
            ),
          ),
          Expanded(
            child: events.isEmpty
                ? Center(
                    child: Text(
                      s.telemetryEmpty,
                      style: YLText.body.copyWith(color: YLColors.zinc400),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _EventTile(event: events[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _IdRow extends StatelessWidget {
  final String label;
  final String value;
  const _IdRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        AppNotifier.success(S.current.copiedToClipboard);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: Text(label, style: YLText.body),
            ),
            Expanded(
              flex: 2,
              child: Text(
                value,
                style: YLText.caption.copyWith(
                  fontFamily: 'monospace',
                  color: YLColors.zinc500,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.copy_outlined, size: 14, color: YLColors.zinc400),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? YLColors.zinc800 : YLColors.zinc100;
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(YLRadius.md),
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
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (time != null)
                Text(
                  _fmt(time),
                  style: YLText.caption.copyWith(color: YLColors.zinc400),
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
