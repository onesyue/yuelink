import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../modules/emby/emby_providers.dart';
import '../../../modules/emby/emby_media_page.dart';
import '../../../modules/emby/emby_web_page.dart';
import '../../../providers/core_provider.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';

/// Dashboard shortcut card for 悦视频.
/// Only visible when the current user has confirmed Emby access.
class EmbyBannerCard extends ConsumerWidget {
  const EmbyBannerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAccess = ref.watch(embyProvider).valueOrNull?.hasAccess == true;
    if (!hasAccess) return const SizedBox.shrink();

    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _open(context, ref, s),
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
        child: Row(
          children: [
            // Icon area
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.play_circle_filled_rounded,
                size: 24,
                color: isDark ? YLColors.zinc300 : YLColors.zinc600,
              ),
            ),
            const SizedBox(width: 14),
            // Text area
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.mineEmby,
                    style: YLText.body.copyWith(
                      color: isDark ? YLColors.zinc200 : YLColors.zinc800,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '电影 · 电视剧 · 动漫',
                    style: TextStyle(
                      color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? YLColors.zinc500 : YLColors.zinc400,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, S s) async {
    if (ref.read(coreStatusProvider) != CoreStatus.running) {
      AppNotifier.warning(s.mineEmbyNeedsVpn);
      return;
    }

    // Use cached data for instant navigation. Only await if no cache.
    var emby = ref.read(embyProvider).valueOrNull;
    if (emby == null || !emby.hasAccess) {
      AppNotifier.info(s.mineEmbyOpening);
      ref.invalidate(embyProvider);
      emby = await ref.read(embyProvider.future);
      if (!context.mounted) return;
      if (emby == null || !emby.hasAccess) {
        AppNotifier.warning(s.mineEmbyNoAccess);
        return;
      }
    }

    if (emby.hasNativeAccess) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EmbyMediaPage(
            serverUrl: emby!.serverBaseUrl!,
            userId: emby.parsedUserId!,
            accessToken: emby.parsedAccessToken!,
            serverId: emby.parsedServerId ?? '',
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EmbyWebPage(url: emby!.launchUrl!)),
      );
    }
  }
}
