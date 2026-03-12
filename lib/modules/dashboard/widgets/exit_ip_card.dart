import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme.dart';
import '../providers/dashboard_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Layer 3 — Exit IP Card
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

    // Determine display state
    String displayValue;
    String displayMeta = '';
    IconData icon = Icons.shield_outlined;
    Color iconColor = YLColors.zinc400;

    if (isLoading) {
      displayValue = s.exitIpQuerying;
    } else if (isQueried && ip != null) {
      displayValue = ip;
      displayMeta = country ?? '';
      icon = Icons.shield_rounded;
      iconColor = YLColors.connected;
    } else if (isQueried) {
      displayValue = s.exitIpFailed;
      icon = Icons.shield_outlined;
      iconColor = YLColors.error;
    } else {
      displayValue = s.exitIpTapToQuery;
    }

    return InkWell(
      onTap: isLoading ? null : () => ref.read(exitIpProvider.notifier).query(),
      borderRadius: BorderRadius.circular(YLRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(16),
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
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 6),
                Text(s.exitIpLabel,
                    style: YLText.caption.copyWith(color: YLColors.zinc500)),
              ],
            ),
            const SizedBox(height: 8),
            if (isLoading)
              const SizedBox(
                width: 14, height: 14,
                child: CupertinoActivityIndicator(radius: 7),
              )
            else
              Text(
                displayValue,
                style: YLText.titleMedium.copyWith(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (displayMeta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                displayMeta,
                style: YLText.caption.copyWith(color: YLColors.zinc400),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
