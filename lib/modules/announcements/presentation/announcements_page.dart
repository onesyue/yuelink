import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/announcements/announcement_entity.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/rich_content.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/yl_scaffold.dart';
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

    return YLLargeTitleScaffold(
      title: s.dashAnnouncementsLabel,
      onRefresh: () async {
        _markedRead = false;
        ref.invalidate(announcementsProvider);
      },
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, size: 22),
          onPressed: () {
            _markedRead = false;
            ref.invalidate(announcementsProvider);
          },
          tooltip: s.retry,
        ),
      ],
      slivers: [
        async.when(
          loading: () => const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(YLSpacing.xl),
                child: YLEmptyState(
                  icon: Icons.error_outline,
                  title: e.toString(),
                  action: FilledButton.icon(
                    onPressed: () {
                      _markedRead = false;
                      ref.invalidate(announcementsProvider);
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(s.retry),
                  ),
                ),
              ),
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: YLEmptyState(
                    icon: Icons.campaign_outlined,
                    title: s.dashNoAnnouncements,
                    action: TextButton(
                      onPressed: () {
                        _markedRead = false;
                        ref.invalidate(announcementsProvider);
                      },
                      child: Text(s.refresh),
                    ),
                  ),
                ),
              );
            }

            if (!_markedRead) {
              _markedRead = true;
              final ids = list
                  .where((a) => a.id != null)
                  .map((a) => a.id!)
                  .toList();
              if (ids.isNotEmpty) {
                ref.read(readAnnouncementIdsProvider.notifier).markAllRead(ids);
              }
            }

            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  YLSpacing.lg, 0, YLSpacing.lg, 0),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: YLSpacing.md),
                itemBuilder: (context, i) => _AnnouncementTile(
                  item: list[i],
                  isDark: isDark,
                ),
              ),
            );
          },
        ),
      ],
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

    return Material(
      color: isDark ? YLColors.zinc800 : Colors.white,
      borderRadius: BorderRadius.circular(YLRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(YLRadius.lg),
        onTap: () {
          setState(() => _expanded = !_expanded);
          if (item.id != null && !isRead) {
            ref.read(readAnnouncementIdsProvider.notifier).markRead(item.id!);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
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
              RichContent(content: item.content),
            ],
          ],
        ),
        ),
      ),
    );
  }
}
