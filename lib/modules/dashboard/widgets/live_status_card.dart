import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/traffic_history.dart';
import '../../../l10n/app_strings.dart';
import '../../../providers/core_provider.dart';
import '../../../shared/traffic_formatter.dart';
import '../../../theme.dart';
import '../providers/dashboard_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// LiveStatusCard — merges ExitIpCard + ChartCard
//
// Layout:
//   ┌──────────────────────────────────────────────────┐
//   │ 🇭🇰 香港 · 上海  ·  1.2.3.4          [AI✓] [↻] │  ← IP header
//   │ Cloudflare Inc.                                  │  ← ISP row
//   │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
//   │ ● ↓ 12.3 MB/s   ● ↑ 0.8 MB/s   [1m][5m][30m][🔒]│  ← speed row
//   │ [chart]                                          │
//   └──────────────────────────────────────────────────┘
// ══════════════════════════════════════════════════════════════════════════════

class LiveStatusCard extends ConsumerStatefulWidget {
  const LiveStatusCard({super.key});

  @override
  ConsumerState<LiveStatusCard> createState() => _LiveStatusCardState();
}

class _LiveStatusCardState extends ConsumerState<LiveStatusCard> {
  TrafficHistory? _frozenHistory;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.listenManual(trafficChartLockedProvider, (prev, next) {
        if (next && _frozenHistory == null) {
          _frozenHistory = ref.read(trafficHistoryProvider).copy();
        } else if (!next && _frozenHistory != null) {
          _frozenHistory = null;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── ExitIP data ─────────────────────────────────────────────────────────
    final ipAsync = ref.watch(exitIpInfoProvider);
    final aiAsync = ref.watch(aiUnlockTestProvider);
    final info = ipAsync.valueOrNull;
    final isIpLoading = ipAsync.isLoading;
    final aiInfo = aiAsync.valueOrNull;

    // ── Traffic chart data ───────────────────────────────────────────────────
    ref.watch(trafficHistoryVersionProvider);
    final liveHistory = ref.read(trafficHistoryProvider);
    final range = ref.watch(trafficChartRangeProvider);
    final locked = ref.watch(trafficChartLockedProvider);
    final traffic = ref.watch(trafficProvider);

    final history =
        locked && _frozenHistory != null ? _frozenHistory! : liveHistory;
    final downHistory = history.downSampled(seconds: range);

    return GestureDetector(
      onTap: () {
        ref.invalidate(exitIpInfoProvider);
        ref.invalidate(aiUnlockTestProvider);
      },
      child: Container(
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
            // ── IP header ─────────────────────────────────────────────────
            _IpHeader(
              s: s,
              isDark: isDark,
              info: info,
              isLoading: isIpLoading,
              hasError: ipAsync.hasError,
              aiInfo: aiInfo,
            ),

            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 0.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            const SizedBox(height: 10),

            // ── Speed row + range controls ────────────────────────────────
            Row(
              children: [
                _SpeedChip(
                  arrow: '↓',
                  bps: traffic.down,
                  color: YLColors.accent,
                ),
                const SizedBox(width: 12),
                _SpeedChip(
                  arrow: '↑',
                  bps: traffic.up,
                  color: YLColors.connected,
                ),
                const Spacer(),
                _RangeButton(
                    label: '1m',
                    value: 60,
                    range: range,
                    onTap: () => ref
                        .read(trafficChartRangeProvider.notifier)
                        .state = 60),
                const SizedBox(width: 4),
                _RangeButton(
                    label: '5m',
                    value: 300,
                    range: range,
                    onTap: () => ref
                        .read(trafficChartRangeProvider.notifier)
                        .state = 300),
                const SizedBox(width: 4),
                _RangeButton(
                    label: '30m',
                    value: 1800,
                    range: range,
                    onTap: () => ref
                        .read(trafficChartRangeProvider.notifier)
                        .state = 1800),
                const SizedBox(width: 6),
                _LockButton(
                  locked: locked,
                  tooltip: locked ? s.chartUnlock : s.chartLock,
                  onTap: () {
                    final nowLocked = ref.read(trafficChartLockedProvider);
                    if (!nowLocked) {
                      _frozenHistory =
                          ref.read(trafficHistoryProvider).copy();
                    } else {
                      _frozenHistory = null;
                    }
                    ref
                        .read(trafficChartLockedProvider.notifier)
                        .state = !nowLocked;
                  },
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ── Traffic chart ─────────────────────────────────────────────
            SizedBox(
              height: 100,
              child: _TrafficChart(
                downHistory: downHistory.isEmpty
                    ? List.filled(60, 0.0)
                    : downHistory,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── IP Header ────────────────────────────────────────────────────────────────

class _IpHeader extends StatelessWidget {
  final S s;
  final bool isDark;
  final ExitIpInfo? info;
  final bool isLoading;
  final bool hasError;
  final AiUnlockInfo? aiInfo;

  const _IpHeader({
    required this.s,
    required this.isDark,
    required this.info,
    required this.isLoading,
    required this.hasError,
    required this.aiInfo,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Row(
        children: [
          Icon(Icons.shield_outlined, size: 13, color: YLColors.zinc400),
          const SizedBox(width: 6),
          Text(s.exitIpLabel,
              style: YLText.caption.copyWith(color: YLColors.zinc500)),
          const SizedBox(width: 8),
          const SizedBox(
            width: 12,
            height: 12,
            child: CupertinoActivityIndicator(radius: 6),
          ),
        ],
      );
    }

    if (info == null) {
      return Row(
        children: [
          Icon(
            hasError ? Icons.shield_outlined : Icons.shield_outlined,
            size: 13,
            color: hasError ? YLColors.error : YLColors.zinc400,
          ),
          const SizedBox(width: 6),
          Text(
            s.exitIpTapToQuery,
            style: YLText.caption.copyWith(color: YLColors.zinc400),
          ),
        ],
      );
    }

    final hasGeo = info!.country.isNotEmpty;
    final locationStr = info!.locationLine;
    final flag = info!.flagEmoji;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main line: flag + location + IP + AI badge
        Row(
          children: [
            // Shield icon
            Icon(Icons.shield_rounded, size: 13, color: YLColors.connected),
            const SizedBox(width: 6),

            // Flag + location (shrinks if needed)
            if (hasGeo && flag.isNotEmpty) ...[
              Text(flag,
                  style: const TextStyle(fontSize: 13, height: 1.2)),
              const SizedBox(width: 4),
              Flexible(
                flex: 2,
                child: Text(
                  locationStr,
                  style: YLText.caption.copyWith(
                    color: isDark ? YLColors.zinc300 : YLColors.zinc600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('·',
                    style: YLText.caption
                        .copyWith(color: YLColors.zinc400)),
              ),
            ],

            // IP address — monospace, prominent
            Flexible(
              flex: 3,
              child: Text(
                info!.ip,
                style: YLText.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: isDark ? Colors.white : YLColors.zinc900,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const Spacer(),

            // AI badge
            if (aiInfo != null) ...[
              const SizedBox(width: 6),
              _AiBadge(aiInfo: aiInfo!, isDark: isDark),
            ],
          ],
        ),

        // ISP row + AI node name (secondary line)
        if (info!.isp.isNotEmpty || (aiInfo != null && aiInfo!.nodeName.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 19),
            child: Row(
              children: [
                if (info!.isp.isNotEmpty)
                  Flexible(
                    child: Text(
                      info!.isp,
                      style: YLText.caption
                          .copyWith(fontSize: 10, color: YLColors.zinc400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (aiInfo != null &&
                    aiInfo!.nodeName.isNotEmpty &&
                    info!.isp.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text('·',
                        style: YLText.caption
                            .copyWith(fontSize: 10, color: YLColors.zinc500)),
                  ),
                if (aiInfo != null && aiInfo!.nodeName.isNotEmpty)
                  Flexible(
                    child: Text(
                      'AI: ${aiInfo!.nodeName}',
                      style: YLText.caption.copyWith(
                        fontSize: 10,
                        color: aiInfo!.unlocked == true
                            ? YLColors.connected
                            : YLColors.zinc400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Speed chip ───────────────────────────────────────────────────────────────

class _SpeedChip extends StatelessWidget {
  final String arrow;
  final int bps;
  final Color color;
  const _SpeedChip(
      {required this.arrow, required this.bps, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          '$arrow ${TrafficFormatter.speed(bps)}/s',
          style: YLText.caption.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: YLColors.zinc400,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ── Range button ─────────────────────────────────────────────────────────────

class _RangeButton extends StatelessWidget {
  final String label;
  final int value;
  final int range;
  final VoidCallback onTap;
  const _RangeButton(
      {required this.label,
      required this.value,
      required this.range,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = value == range;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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

// ── Lock button ───────────────────────────────────────────────────────────────

class _LockButton extends StatelessWidget {
  final bool locked;
  final String tooltip;
  final VoidCallback onTap;
  const _LockButton(
      {required this.locked, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Icon(
            locked ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: 13,
            color: locked ? YLColors.zinc400 : YLColors.zinc500,
          ),
        ),
      ),
    );
  }
}

// ── Traffic chart ─────────────────────────────────────────────────────────────

class _TrafficChart extends StatelessWidget {
  final List<double> downHistory;
  const _TrafficChart({required this.downHistory});

  @override
  Widget build(BuildContext context) {
    final maxVal = downHistory.fold(0.0, (a, b) => b > a ? b : a);
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
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: maxY / 3,
              getTitlesWidget: (value, meta) {
                if (value <= 0) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text('0',
                          style: YLText.caption.copyWith(
                              fontSize: 9, color: YLColors.zinc400)),
                    ),
                  );
                }
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
        clipData: const FlClipData.none(),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: toSpots(downHistory),
            isCurved: true,
            curveSmoothness: 0.25,
            color: YLColors.accent,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: YLColors.accent.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  static String _fmtSpeed(double bps) {
    if (bps >= 1024 * 1024 * 1024) {
      return '${(bps / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
    }
    return '${(bps / (1024 * 1024)).toStringAsFixed(2)}MB';
  }
}

// ── AI badge (reused from exit_ip_card logic) ─────────────────────────────────

class _AiBadge extends StatelessWidget {
  final AiUnlockInfo aiInfo;
  final bool isDark;
  const _AiBadge({required this.aiInfo, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final unlocked = aiInfo.unlocked;
    final Color bg;
    final Color fg;

    if (unlocked == null) {
      bg = YLColors.zinc500.withValues(alpha: 0.12);
      fg = YLColors.zinc400;
    } else if (unlocked) {
      bg = YLColors.connected.withValues(alpha: isDark ? 0.15 : 0.10);
      fg = YLColors.connected;
    } else {
      bg = YLColors.error.withValues(alpha: isDark ? 0.15 : 0.10);
      fg = YLColors.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unlocked != null) ...[
            Icon(
              unlocked ? Icons.check_rounded : Icons.close_rounded,
              size: 10,
              color: fg,
            ),
            const SizedBox(width: 2),
          ],
          if (unlocked == null)
            const SizedBox(
              width: 8,
              height: 8,
              child: CupertinoActivityIndicator(radius: 4),
            ),
          if (unlocked == null) const SizedBox(width: 2),
          Text(
            'AI',
            style: YLText.caption.copyWith(
              fontSize: 9,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
