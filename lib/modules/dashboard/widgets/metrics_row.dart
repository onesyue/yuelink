import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/core_provider.dart';
import '../../../shared/traffic_formatter.dart';
import '../../../theme.dart';
import '../../connections/providers/connections_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// MetricsRow — compact 2-tile row: connections + memory only
//
// Traffic usage is intentionally excluded — SubscriptionCard is the
// single source of truth for cumulative traffic display.
// ══════════════════════════════════════════════════════════════════════════════

class MetricsRow extends ConsumerWidget {
  const MetricsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connCount = ref.watch(connectionCountProvider);
    final mem = ref.watch(memoryUsageProvider);

    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            icon: Icons.swap_horiz_rounded,
            value: '$connCount',
            label: s.activeConns,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricTile(
            icon: Icons.memory_rounded,
            value: TrafficFormatter.bytes(mem),
            label: s.trafficMemory,
            isDark: isDark,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool isDark;

  const _MetricTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        children: [
          Icon(icon, size: 16, color: YLColors.zinc400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: YLText.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : YLColors.zinc900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  style:
                      YLText.caption.copyWith(fontSize: 10, color: YLColors.zinc500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
