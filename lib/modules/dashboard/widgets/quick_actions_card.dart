import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../modules/announcements/presentation/announcements_page.dart';
import '../../../modules/emby/emby_providers.dart';
import '../../../modules/emby/emby_web_page.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';

class QuickActionsCard extends ConsumerStatefulWidget {
  const QuickActionsCard({super.key});

  @override
  ConsumerState<QuickActionsCard> createState() => _QuickActionsCardState();
}

class _QuickActionsCardState extends ConsumerState<QuickActionsCard> {
  bool _syncing = false;

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final s = S.of(context);
    try {
      await ref.read(authProvider.notifier).syncSubscription();
      if (mounted) AppNotifier.success(s.authSyncSuccess);
    } catch (_) {
      if (mounted) AppNotifier.error(s.authSyncFailed);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openEmby() async {
    final s = S.of(context);
    // Always fetch a fresh token — Emby AccessTokens should not be reused
    // across sessions to avoid stale/revoked token issues.
    ref.invalidate(embyProvider);
    AppNotifier.info(s.mineEmbyOpening);
    final emby = await ref.read(embyProvider.future);
    if (!mounted) return;
    if (emby == null || !emby.hasAccess) {
      AppNotifier.warning(s.mineEmbyNoAccess);
      return;
    }
    _launchUrl(emby.launchUrl!);
  }

  void _launchUrl(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EmbyWebPage(url: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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
          // ── Sync ──────────────────────────────────────────────
          Expanded(
            child: _ActionTile(
              icon: Icons.sync_rounded,
              label: _syncing ? s.authSyncingSubscription : s.dashSyncLabel,
              spinning: _syncing,
              isDark: isDark,
              onTap: _sync,
            ),
          ),
          _Divider(isDark: isDark),

          // ── Emby ──────────────────────────────────────────────
          Expanded(
            child: _ActionTile(
              icon: Icons.play_circle_outline_rounded,
              label: s.mineEmby,
              isDark: isDark,
              onTap: _openEmby,
            ),
          ),
          _Divider(isDark: isDark),

          // ── Announcements ─────────────────────────────────────
          Expanded(
            child: _ActionTile(
              icon: Icons.campaign_outlined,
              label: s.dashAnnouncementsLabel,
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AnnouncementsPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 52,
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.06),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool spinning;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.spinning = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(YLRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            spinning
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark ? Colors.white70 : YLColors.zinc600,
                    ),
                  )
                : Icon(icon,
                    size: 20,
                    color: isDark ? Colors.white70 : YLColors.zinc700),
            const SizedBox(height: 5),
            Text(
              label,
              style: YLText.caption.copyWith(
                color: isDark ? YLColors.zinc400 : YLColors.zinc600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
