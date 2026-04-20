import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/account/notice.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/rich_content.dart';
import '../../../theme.dart';
import '../../announcements/presentation/announcements_page.dart';
import '../providers/account_providers.dart';

/// 最新通知卡片 — 展示 1~3 条最新公告，点击进入公告列表。
class NoticesCard extends ConsumerWidget {
  const NoticesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noticesAsync = ref.watch(dashboardNoticesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return noticesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (notices) {
        if (notices.isEmpty) return const SizedBox.shrink();
        final display = notices.take(3).toList();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    size: 16,
                    color: isDark ? YLColors.zinc300 : YLColors.zinc600,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      S.current.latestAnnouncements,
                      style: YLText.caption.copyWith(
                        color: YLColors.zinc500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(YLRadius.sm),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AnnouncementsPage()),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Text(
                          S.current.viewAll,
                          style: YLText.caption.copyWith(
                            color: YLColors.currentAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...display.map((n) => _NoticeTile(notice: n, isDark: isDark)),
            ],
          ),
        );
      },
    );
  }
}

class _NoticeTile extends StatelessWidget {
  final AccountNotice notice;
  final bool isDark;
  const _NoticeTile({required this.notice, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showDetail(context),
      borderRadius: BorderRadius.circular(YLRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(top: 6, right: 8),
              decoration: BoxDecoration(
                color: YLColors.currentAccent,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.title,
                    style: YLText.label.copyWith(
                      color: isDark ? Colors.white : YLColors.zinc900,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (notice.content.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _stripHtml(notice.content),
                      style: YLText.caption.copyWith(color: YLColors.zinc500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: YLColors.zinc400),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? YLColors.zinc800 : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            // 拖拽条
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: YLColors.zinc400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                notice.title,
                style: YLText.titleMedium.copyWith(
                  color: isDark ? Colors.white : YLColors.zinc900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (notice.createdAt != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _formatDate(notice.createdAt!),
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
              ),
            const SizedBox(height: 12),
            Divider(
                height: 1, color: isDark ? YLColors.zinc700 : YLColors.zinc200),
            // 内容
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(20),
                child: RichContent(content: notice.content),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.tryParse(raw);
      if (dt == null) return raw;
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
