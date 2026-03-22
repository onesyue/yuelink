import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/announcements/announcement_entity.dart';
import '../../../l10n/app_strings.dart';
import '../../../theme.dart';
import '../providers/announcements_providers.dart';

class AnnouncementsPage extends ConsumerStatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  ConsumerState<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends ConsumerState<AnnouncementsPage> {
  bool _markedRead = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final async = ref.watch(announcementsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.dashAnnouncementsLabel),
        centerTitle: false,
        actions: [
          // Manual refresh button
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () {
              _markedRead = false;
              ref.invalidate(announcementsProvider);
            },
            tooltip: s.retry,
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 36, color: YLColors.zinc400),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  style: YLText.body.copyWith(color: YLColors.zinc500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    _markedRead = false;
                    ref.invalidate(announcementsProvider);
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(s.retry),
                ),
              ],
            ),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.campaign_outlined,
                      size: 48, color: YLColors.zinc300),
                  const SizedBox(height: 10),
                  Text(s.dashNoAnnouncements,
                      style: YLText.body.copyWith(color: YLColors.zinc400)),
                ],
              ),
            );
          }

          // Mark all as read once when data arrives — guarded to prevent rebuild cascade
          if (!_markedRead) {
            _markedRead = true;
            final ids = list
                .where((a) => a.id != null)
                .map((a) => a.id!)
                .toList();
            if (ids.isNotEmpty) {
              // Fire-and-forget, no setState needed
              ref.read(readAnnouncementIdsProvider.notifier).markAllRead(ids);
            }
          }

          return RefreshIndicator(
            onRefresh: () async {
              _markedRead = false;
              ref.invalidate(announcementsProvider);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _AnnouncementTile(
                item: list[i],
                isDark: isDark,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _AnnouncementTile extends ConsumerStatefulWidget {
  final Announcement item;
  final bool isDark;

  const _AnnouncementTile({required this.item, required this.isDark});

  @override
  ConsumerState<_AnnouncementTile> createState() => _AnnouncementTileState();
}

class _AnnouncementTileState extends ConsumerState<_AnnouncementTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDark = widget.isDark;
    final readIds = ref.watch(readAnnouncementIdsProvider);
    final isRead = item.id == null || readIds.contains(item.id);

    String? dateStr;
    if (item.createdDate != null) {
      final d = item.createdDate!;
      dateStr =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    return GestureDetector(
      onTap: () {
        setState(() => _expanded = !_expanded);
        if (item.id != null && !isRead) {
          ref.read(readAnnouncementIdsProvider.notifier).markRead(item.id!);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc800 : Colors.white,
          borderRadius: BorderRadius.circular(YLRadius.lg),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Unread dot
                if (!isRead) ...[
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 7),
                    decoration: const BoxDecoration(
                      color: YLColors.connected,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                Expanded(
                  child: Text(
                    item.title,
                    style: YLText.titleMedium.copyWith(
                      fontWeight:
                          isRead ? FontWeight.w500 : FontWeight.w700,
                    ),
                    maxLines: _expanded ? null : 1,
                    overflow:
                        _expanded ? null : TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: YLColors.zinc400,
                ),
              ],
            ),
            if (dateStr != null) ...[
              const SizedBox(height: 3),
              Text(dateStr,
                  style:
                      YLText.caption.copyWith(color: YLColors.zinc400)),
            ],
            if (_expanded && item.content.isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              const SizedBox(height: 10),
              Text(
                item.content,
                style: YLText.body.copyWith(
                  color: isDark ? YLColors.zinc300 : YLColors.zinc600,
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
