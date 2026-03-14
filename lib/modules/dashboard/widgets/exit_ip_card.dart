import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme.dart';
import '../providers/dashboard_providers.dart';

class ExitIpCard extends ConsumerWidget {
  const ExitIpCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final serverIp = ref.watch(proxyServerIpProvider);

    final isLoading = serverIp.isLoading;
    final ip = serverIp.valueOrNull;
    final hasIp = ip != null && ip.isNotEmpty;

    final IconData headerIcon =
        hasIp ? Icons.shield_rounded : Icons.shield_outlined;
    final Color headerIconColor = hasIp
        ? YLColors.connected
        : (serverIp.hasError ? YLColors.error : YLColors.zinc400);

    return Container(
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── TOP: label row ─────────────────────────────────────────
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
            ],
          ),

          // ── BOTTOM: IP value ────────────────────────────────────────
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
                  hasIp ? ip : s.exitIpTapToQuery,
                  style: hasIp
                      ? YLText.titleMedium
                      : YLText.body.copyWith(
                          fontSize: 13,
                          color: YLColors.zinc400,
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
