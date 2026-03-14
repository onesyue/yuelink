import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../modules/announcements/presentation/announcements_page.dart';
import '../../../modules/announcements/providers/announcements_providers.dart';
import '../../../theme.dart';

/// Shows the latest announcement as a compact banner.
/// Tapping navigates to the full announcements list.
class AnnouncementBanner extends ConsumerWidget {
  const AnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final async = ref.watch(announcementsProvider);

    final readIds = ref.watch(readAnnouncementIdsProvider);

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();

        final latest = list.first;
        final unreadCount = list
            .where((a) => a.id != null && !readIds.contains(a.id))
            .length;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AnnouncementsPage()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                // Icon with unread badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.campaign_outlined,
                      size: 16,
                      color: YLColors.accent,
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.dashLatestAnnouncement,
                        style: YLText.caption.copyWith(
                          color: YLColors.zinc500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        latest.title,
                        style: YLText.label.copyWith(
                          color: isDark ? Colors.white : YLColors.zinc900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: YLColors.zinc400),
              ],
            ),
          ),
        );
      },
    );
  }
}
