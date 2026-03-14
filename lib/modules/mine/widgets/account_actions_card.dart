import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_strings.dart';
import '../../../modules/emby/emby_providers.dart';
import '../../../modules/store/order_history_page.dart';
import '../../../modules/store/store_page.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';

/// Quick-action rows for the account center (我的 page).
class AccountActionsCard extends ConsumerStatefulWidget {
  const AccountActionsCard({super.key});

  @override
  ConsumerState<AccountActionsCard> createState() =>
      _AccountActionsCardState();
}

class _AccountActionsCardState extends ConsumerState<AccountActionsCard> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Emby row only when user has confirmed access
    final hasEmby =
        ref.watch(embyProvider).valueOrNull?.hasAccess == true;

    final divider = Divider(
      height: 1,
      thickness: 0.5,
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.06),
    );

    // Build rows dynamically so Emby can be conditional without breaking dividers
    final rows = <Widget>[
      // ── Subscribe / Store ──────────────────────────────────
      _ActionRow(
        icon: Icons.storefront_outlined,
        label: s.mineRenew,
        isDark: isDark,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StorePage()),
        ),
      ),

      // ── Sync lines ─────────────────────────────────────────
      _ActionRow(
        icon: Icons.sync_rounded,
        label: _syncing ? s.mineSyncing : s.mineSyncLine,
        isDark: isDark,
        trailing: _syncing
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right,
                size: 18, color: YLColors.zinc400),
        onTap: _syncing ? null : () => _syncSubscription(s),
      ),

      // ── Emby (only when user has confirmed access) ─────────
      if (hasEmby)
        _ActionRow(
          icon: Icons.play_circle_outline_rounded,
          label: s.mineEmby,
          isDark: isDark,
          onTap: () => _openEmby(s),
        ),

      // ── Order history ──────────────────────────────────────
      _ActionRow(
        icon: Icons.receipt_long_outlined,
        label: s.storeOrderHistory,
        isDark: isDark,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OrderHistoryPage()),
        ),
      ),

      // ── Change password ────────────────────────────────────
      _ActionRow(
        icon: Icons.lock_outline_rounded,
        label: s.mineChangePassword,
        isDark: isDark,
        onTap: () => _launch('https://yue.to/#/profile'),
      ),

      // ── TG group ──────────────────────────────────────────
      _ActionRow(
        icon: Icons.telegram,
        label: s.mineTelegramGroup,
        isDark: isDark,
        onTap: () => _launch('https://t.me/yue_to'),
      ),

      // ── Logout ────────────────────────────────────────────
      _ActionRow(
        icon: Icons.logout_rounded,
        label: s.authLogout,
        iconColor: YLColors.error,
        labelColor: YLColors.error,
        isDark: isDark,
        showChevron: false,
        onTap: () => _confirmLogout(context, s),
      ),
    ];

    return Container(
      width: double.infinity,
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
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1) divider,
          ],
        ],
      ),
    );
  }

  Future<void> _openEmby(S s) async {
    final emby = ref.read(embyProvider).valueOrNull;
    if (emby == null || !emby.hasAccess) {
      ref.invalidate(embyProvider);
      AppNotifier.info(s.mineEmbyOpening);
      final fresh = await ref.read(embyProvider.future);
      if (!mounted) return;
      if (fresh == null || !fresh.hasAccess) {
        AppNotifier.warning(s.mineEmbyNoAccess);
        return;
      }
      await _launch(fresh.launchUrl!);
      return;
    }
    await _launch(emby.launchUrl!);
  }

  Future<void> _syncSubscription(S s) async {
    setState(() => _syncing = true);
    try {
      await ref.read(authProvider.notifier).syncSubscription();
      if (mounted) AppNotifier.success(s.mineSyncDone);
    } catch (e) {
      if (mounted) AppNotifier.error(s.mineSyncFailed);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      AppNotifier.error(S.current.mineEmbyOpenFailed);
    }
  }

  void _confirmLogout(BuildContext context, S s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.authLogout),
        content: Text(s.authLogoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            style: FilledButton.styleFrom(
                backgroundColor: YLColors.error),
            child: Text(s.authLogout),
          ),
        ],
      ),
    );
  }
}

// ── Action row ────────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final Color? iconColor;
  final Color? labelColor;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.isDark,
    this.iconColor,
    this.labelColor,
    this.trailing,
    this.showChevron = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIcon = iconColor ?? YLColors.zinc400;
    final effectiveLabel =
        labelColor ?? (isDark ? YLColors.zinc200 : YLColors.zinc800);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(YLRadius.xl),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: effectiveIcon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: YLText.body.copyWith(color: effectiveLabel)),
            ),
            trailing ??
                (showChevron
                    ? const Icon(Icons.chevron_right,
                        size: 18, color: YLColors.zinc400)
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
