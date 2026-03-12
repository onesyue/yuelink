import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/connection_provider.dart';
import '../../../providers/core_provider.dart';
import '../../../shared/traffic_formatter.dart';
import '../../../theme.dart';
import '../providers/traffic_providers.dart';

// ── Today stats card ──────────────────────────────────────────────────────────

class StatsCard extends ConsumerWidget {
  const StatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final daily = ref.watch(dailyTrafficProvider);
    final connCount = ref.watch(connectionCountProvider);
    final mem = ref.watch(memoryUsageProvider);

    final items = [
      (s.trafficDownload, TrafficFormatter.bytes(daily.$2), Icons.arrow_downward_rounded, YLColors.accent),
      (s.trafficUpload,   TrafficFormatter.bytes(daily.$1), Icons.arrow_upward_rounded,   YLColors.connected),
      (s.activeConns,     '$connCount',                     Icons.swap_horiz_rounded,     YLColors.zinc500),
      (s.trafficMemory,   TrafficFormatter.bytes(mem),      Icons.memory_rounded,         YLColors.zinc500),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Row(
        children: items.map((item) {
          final (label, value, icon, color) = item;
          return Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: YLText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: YLText.caption
                      .copyWith(fontSize: 10, color: YLColors.zinc500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
