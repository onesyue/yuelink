import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/profile.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/formatters/subscription_parser.dart';
import '../../../theme.dart';
import '../providers/profiles_providers.dart';

/// List-item widgets and the swipe-to-delete confirmation sheet for the
/// Profiles page. Pulled out of profiles_page.dart (which was 1203 lines)
/// so the page itself focuses on routing + dialogs and the row UI lives
/// next to its swipe-delete partner. All three symbols are public
/// because the page is the only consumer today, but tests can also
/// reach them directly without the StatefulWidget host.

class ProfileCard extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onUpdate;
  final VoidCallback onEdit;
  final VoidCallback onViewConfig;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const ProfileCard({
    super.key,
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onUpdate,
    required this.onEdit,
    required this.onViewConfig,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = profile.subInfo;

    return Container(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      decoration: YLGlass.surfaceDecoration(context, strong: isActive).copyWith(
        border: Border.all(
          color: isActive
              ? (isDark
                    ? YLColors.primaryDark.withValues(alpha: 0.30)
                    : YLColors.primary.withValues(alpha: 0.20))
              : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.72)),
          width: 0.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(YLSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Icon(
                    isActive ? Icons.check_circle : Icons.circle_outlined,
                    color: isActive
                        ? (isDark ? YLColors.primaryDark : YLColors.primary)
                        : (isDark ? YLColors.zinc400 : YLColors.zinc500),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      profile.name,
                      style: YLText.rowTitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      switch (action) {
                        case 'update':
                          onUpdate();
                        case 'edit':
                          onEdit();
                        case 'config':
                          onViewConfig();
                        case 'export':
                          onExport();
                        case 'copy':
                          Clipboard.setData(ClipboardData(text: profile.url));
                          AppNotifier.success(s.copiedLink);
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'update',
                        child: Text(s.updateSubscription),
                      ),
                      PopupMenuItem(value: 'edit', child: Text(s.edit)),
                      PopupMenuItem(value: 'config', child: Text(s.viewConfig)),
                      PopupMenuItem(
                        value: 'export',
                        child: Text(s.exportProfile),
                      ),
                      PopupMenuItem(value: 'copy', child: Text(s.copyLink)),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          s.delete,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Subscription info
              if (profile.hasSubInfo && sub != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(YLRadius.sm),
                  child: LinearProgressIndicator(
                    value: sub.usagePercent ?? 0,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? YLColors.zinc700
                        : YLColors.zinc200,
                    color: _usageColor(sub.usagePercent ?? 0),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      s.usageLabel(
                        formatBytes((sub.upload ?? 0) + (sub.download ?? 0)),
                        formatBytes(sub.total ?? 0),
                      ),
                      style: YLText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    if (sub.expire != null)
                      Text(
                        sub.isExpired
                            ? s.expired
                            : s.daysRemaining(sub.daysRemaining ?? 0),
                        style: YLText.caption.copyWith(
                          color: sub.isExpired
                              ? YLColors.error
                              : (sub.daysRemaining != null &&
                                    sub.daysRemaining! < 7)
                              ? Colors.orange
                              : YLColors.zinc500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ],

              // Last updated + staleness warning
              if (profile.lastUpdated != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      s.updatedAt(_formatTime(profile.lastUpdated!)),
                      style: YLText.caption.copyWith(color: YLColors.zinc500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_isStale(profile)) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        s.needsUpdate,
                        style: YLText.caption.copyWith(
                          color: Colors.orange.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _usageColor(double percent) {
    if (percent < 0.5) return Colors.green;
    if (percent < 0.8) return Colors.orange;
    return Colors.red;
  }

  bool _isStale(Profile p) {
    if (p.lastUpdated == null) return false;
    return DateTime.now().difference(p.lastUpdated!) > p.updateInterval;
  }

  String _formatTime(DateTime dt) {
    return '${dt.month}/${dt.day} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Swipe-to-delete helpers ───────────────────────────────────────────────

/// Red background shown behind a profile row while the user is dragging
/// left to reveal the delete action. Used by Dismissible on mobile.
class ProfileSwipeDeleteBackground extends StatelessWidget {
  const ProfileSwipeDeleteBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(YLRadius.lg),
      ),
      alignment: Alignment.centerRight,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
          SizedBox(width: 6),
          Text(
            '删除',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet confirmation used by the swipe-to-delete gesture on mobile.
/// Returns true if the user confirmed (profile gets deleted), false or null
/// if they backed out (Dismissible rubber-bands the row back).
Future<bool> showProfileDeleteConfirmSheet(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) async {
  final s = S.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(YLRadius.xl)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.confirmDelete,
            style: Theme.of(
              ctx,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            s.confirmDeleteMessage(profile.name),
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx, true);
              await ref.read(profilesProvider.notifier).delete(profile.id);
              final activeId = ref.read(activeProfileIdProvider);
              if (activeId == profile.id) {
                ref.read(activeProfileIdProvider.notifier).select(null);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(s.delete),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(40)),
            child: Text(s.cancel),
          ),
        ],
      ),
    ),
  );
  return result == true;
}
