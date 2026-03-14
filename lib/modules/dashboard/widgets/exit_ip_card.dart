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
    final async = ref.watch(exitIpInfoProvider);

    final isLoading = async.isLoading;
    final info = async.valueOrNull;
    final hasInfo = info != null;
    final hasGeo = hasInfo && info.country.isNotEmpty;

    final Color headerIconColor = hasInfo
        ? YLColors.connected
        : (async.hasError ? YLColors.error : YLColors.zinc400);

    return GestureDetector(
      onTap: () => ref.invalidate(exitIpInfoProvider),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                Icon(
                  hasInfo ? Icons.shield_rounded : Icons.shield_outlined,
                  size: 13,
                  color: headerIconColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.exitIpLabel,
                    style: YLText.caption.copyWith(color: YLColors.zinc500),
                  ),
                ),
              ],
            ),

            // ── BOTTOM: info block ──────────────────────────────────────
            if (isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CupertinoActivityIndicator(radius: 8),
              )
            else if (!hasInfo)
              Text(
                s.exitIpTapToQuery,
                style: YLText.body.copyWith(
                  fontSize: 13,
                  color: YLColors.zinc400,
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Flag + location
                  if (hasGeo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${info.flagEmoji}  ${info.locationLine}'.trim(),
                        style: YLText.caption.copyWith(
                          color: isDark ? YLColors.zinc300 : YLColors.zinc600,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // IP address
                  Text(
                    info.ip,
                    style: YLText.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // ISP
                  if (hasGeo && info.isp.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        info.isp,
                        style: YLText.caption.copyWith(
                          color: YLColors.zinc400,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
