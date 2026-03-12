import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme.dart';
import '../providers/dashboard_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Layer 3 — Exit IP Card
//
// Layout zones (spaceBetween):
//   TOP  — label row (icon + "出口 IP" + refresh hint when queried)
//   BOT  — main content group (spinner | IP value | tap hint)
//
// On wide layout (CrossAxisAlignment.stretch) the card is stretched to match
// ChartCard's height; spaceBetween fills the vertical space cleanly.
// On mobile (stacked, natural height) the two zones sit close together —
// minHeight: 100 prevents it from collapsing to just a few px.
// ═══════════════════════════════════════════════════════════════════════════════

class ExitIpCard extends ConsumerWidget {
  const ExitIpCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final exitIp = ref.watch(exitIpProvider);

    final ip = exitIp.ip;
    final country = exitIp.country;
    final isLoading = exitIp.isLoading;
    final isQueried = exitIp.isQueried;
    final hasIp = isQueried && ip != null;

    // Icon + color for header row
    final IconData headerIcon =
        hasIp ? Icons.shield_rounded : Icons.shield_outlined;
    final Color headerIconColor =
        hasIp ? YLColors.connected : (isQueried ? YLColors.error : YLColors.zinc400);

    return InkWell(
      onTap: isLoading ? null : () => ref.read(exitIpProvider.notifier).query(),
      borderRadius: BorderRadius.circular(YLRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        constraints: const BoxConstraints(minHeight: 100),
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
          mainAxisSize: MainAxisSize.max,
          // spaceBetween: label stays at top, IP content anchors at bottom.
          // On stretched desktop layout this fills the full ChartCard height.
          // On mobile natural height the two zones sit close with normal spacing.
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ── TOP: label row ───────────────────────────────────────────────
            Row(
              children: [
                Icon(headerIcon, size: 13, color: headerIconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.exitIpLabel,
                    style: YLText.caption.copyWith(color: YLColors.zinc500),
                  ),
                ),
                // Subtle refresh hint when a result is already showing
                if (hasIp && !isLoading)
                  Icon(Icons.refresh_rounded, size: 12, color: YLColors.zinc400),
              ],
            ),

            // ── BOTTOM: main content ─────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CupertinoActivityIndicator(radius: 8),
                  )
                else
                  Text(
                    hasIp ? ip : (isQueried ? s.exitIpFailed : s.exitIpTapToQuery),
                    // Actual IP gets full titleMedium weight (15 px w600).
                    // Hints / errors are muted body style so they don't compete.
                    style: hasIp
                        ? YLText.titleMedium
                        : YLText.body.copyWith(
                            fontSize: 13,
                            color: isQueried ? YLColors.error : YLColors.zinc400,
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if ((country ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    country!,
                    style: YLText.caption.copyWith(color: YLColors.zinc400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
