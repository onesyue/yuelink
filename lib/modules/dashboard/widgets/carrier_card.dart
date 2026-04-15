import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../theme.dart';
import '../../carrier/carrier_provider.dart';

/// Compact card showing detected carrier and SNI health status.
/// Only visible when VPN is running and carrier is detected.
class CarrierCard extends ConsumerWidget {
  const CarrierCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.of(context);
    final carrier = ref.watch(carrierProvider);

    // Only show when there's an issue (degraded/blocked) — seamless when healthy
    if (!carrier.isDetected || carrier.isSniHealthy) {
      return const SizedBox.shrink();
    }

    final isDegraded = carrier.sniStatus == 'degraded';
    final statusColor = isDegraded
        ? const Color(0xFFF59E0B) // Amber-500
        : YLColors.error;

    final statusText = isDegraded
        ? (s.isEn ? 'Degraded' : '降级')
        : (s.isEn ? 'Blocked' : '受阻');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
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
          // Carrier icon + name
          Icon(
            Icons.cell_tower_rounded,
            size: 16,
            color: isDark ? Colors.white70 : YLColors.zinc600,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                carrier.carrierName,
                style: YLText.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : YLColors.zinc900,
                ),
              ),
              if (carrier.sniDomain.isNotEmpty)
                Text(
                  carrier.sniDomain,
                  style: YLText.caption.copyWith(
                    color: YLColors.zinc400,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
          const Spacer(),
          // SNI health indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(YLRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  statusText,
                  style: YLText.caption.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
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
