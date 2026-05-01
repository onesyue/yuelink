import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../providers/connections_providers.dart';

class ProxyStatsBar extends StatelessWidget {
  final List<ProxyStats> stats;
  const ProxyStatsBar({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: stats.map((ps) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(YLRadius.sm),
          ),
          child: Text(
            '${ps.proxyName}  ${ps.connectionCount}  ${_fmtBytes(ps.totalDownload)}',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: isDark ? YLColors.zinc400 : YLColors.zinc600,
            ),
          ),
        );
      }).toList(),
    );
  }

  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}K';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
  }
}
