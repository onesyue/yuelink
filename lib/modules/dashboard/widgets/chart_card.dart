import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/traffic_history.dart';
import '../../../l10n/app_strings.dart';
import '../../../providers/core_provider.dart';
import '../../../theme.dart';
import '../providers/traffic_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Layer 3 — Chart Card
// ═══════════════════════════════════════════════════════════════════════════════

class ChartCard extends ConsumerStatefulWidget {
  const ChartCard({super.key});

  @override
  ConsumerState<ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends ConsumerState<ChartCard> {
  TrafficHistory? _frozenHistory;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final liveHistory = ref.watch(trafficHistoryProvider);
    final range = ref.watch(trafficChartRangeProvider);
    final locked = ref.watch(trafficChartLockedProvider);

    // When lock toggles on, capture snapshot; when off, clear it
    if (locked && _frozenHistory == null) {
      _frozenHistory = liveHistory.copy();
    } else if (!locked && _frozenHistory != null) {
      _frozenHistory = null;
    }

    final history = locked && _frozenHistory != null ? _frozenHistory! : liveHistory;
    final downHistory = history.downSampled(seconds: range);
    final upHistory = history.upSampled(seconds: range);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: title + range selector + lock + legend
          Row(
            children: [
              Expanded(
                child: Text(s.trafficActivity,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YLText.caption.copyWith(color: YLColors.zinc500)),
              ),
              // Time range buttons
              _RangeButton(label: '1m', value: 60, range: range, ref: ref),
              const SizedBox(width: 4),
              _RangeButton(label: '5m', value: 300, range: range, ref: ref),
              const SizedBox(width: 4),
              _RangeButton(label: '30m', value: 1800, range: range, ref: ref),
              const SizedBox(width: 4),
              // Lock button
              GestureDetector(
                onTap: () {
                  final nowLocked = ref.read(trafficChartLockedProvider);
                  if (!nowLocked) {
                    // Capture snapshot before locking
                    _frozenHistory = ref.read(trafficHistoryProvider).copy();
                  } else {
                    _frozenHistory = null;
                  }
                  ref.read(trafficChartLockedProvider.notifier).state = !nowLocked;
                },
                child: Tooltip(
                  message: locked ? s.chartUnlock : s.chartLock,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(
                      locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      size: 13,
                      color: locked ? YLColors.zinc400 : YLColors.zinc500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _LegendDot(color: YLColors.accent, label: '↓'),
              const SizedBox(width: 10),
              _LegendDot(color: YLColors.connected, label: '↑'),
            ],
          ),
          const SizedBox(height: 12),
          // Chart
          SizedBox(
            height: 120,
            child: downHistory.isEmpty
                ? Center(
                    child: Text('—',
                        style: YLText.body.copyWith(color: YLColors.zinc400)),
                  )
                : _buildChart(context, downHistory, upHistory, 0),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<double> down,
      List<double> up, double p90) {
    // Use actual max of displayed data + 15% headroom so every spike is
    // fully visible. p90 was used before but caused peaks to be clipped.
    final maxVal = [...down, ...up].fold(0.0, (a, b) => b > a ? b : a);
    final maxY = maxVal > 0 ? maxVal * 1.15 : 1024 * 1024.0;

    List<FlSpot> toSpots(List<double> data) => data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 3,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: maxY / 3,
              getTitlesWidget: (value, meta) {
                // Hide the 0 baseline label.
                if (value <= 0) return const SizedBox.shrink();
                // Top label (maxY): anchor to topRight so the text sits
                // entirely inside the chart and never bleeds above it.
                final isTop = value >= meta.max * 0.99;
                return Align(
                  alignment:
                      isTop ? Alignment.topRight : Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      _fmtSpeed(value),
                      style: YLText.caption
                          .copyWith(fontSize: 9, color: YLColors.zinc400),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        clipData: const FlClipData.all(),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          _line(toSpots(down), YLColors.accent),
          _line(toSpots(up), YLColors.connected),
        ],
      ),
      duration: const Duration(milliseconds: 100),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.25,
      color: color,
      barWidth: 1.5,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  static String _fmtSpeed(double bps) {
    if (bps >= 1024 * 1024 * 1024) {
      return '${(bps / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
    }
    return '${(bps / (1024 * 1024)).toStringAsFixed(2)}MB';
  }
}

class _RangeButton extends StatelessWidget {
  final String label;
  final int value;
  final int range;
  final WidgetRef ref;
  const _RangeButton(
      {required this.label,
      required this.value,
      required this.range,
      required this.ref});

  @override
  Widget build(BuildContext context) {
    final selected = value == range;
    return GestureDetector(
      onTap: () => ref.read(trafficChartRangeProvider.notifier).state = value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: selected
              ? YLColors.zinc500.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: YLText.caption.copyWith(
            fontSize: 10,
            color: selected ? YLColors.zinc400 : YLColors.zinc500,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(label, style: YLText.caption.copyWith(color: YLColors.zinc400)),
      ],
    );
  }
}
