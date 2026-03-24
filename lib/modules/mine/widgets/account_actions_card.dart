import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../infrastructure/datasources/xboard_api.dart';
import '../../../l10n/app_strings.dart';
import '../../../modules/store/order_history_page.dart';
import '../../../modules/profiles/profiles_page.dart';
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

      // ── Subscription management ─────────────────────────────
      _ActionRow(
        icon: Icons.cloud_sync_outlined,
        label: s.mineSubscriptionManage,
        isDark: isDark,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        ),
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
        onTap: () => _showChangePasswordDialog(context, s),
      ),

      // ── TG group ──────────────────────────────────────────
      _ActionRow(
        icon: Icons.telegram,
        label: s.mineTelegramGroup,
        isDark: isDark,
        onTap: () => _launchTelegram(),
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

  Future<void> _launchTelegram() async {
    final tgUri = Uri.parse('tg://resolve?domain=yue_to');
    try {
      if (await canLaunchUrl(tgUri)) {
        await launchUrl(tgUri);
        return;
      }
    } catch (_) {}
    // Fallback to web URL
    try {
      await launchUrl(
        Uri.parse('https://t.me/yue_to'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      AppNotifier.error(S.current.operationFailed);
    }
  }

  void _showChangePasswordDialog(BuildContext context, S s) {
    final oldPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.mineChangePassword),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPwCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: s.oldPassword),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPwCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: s.newPassword),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final oldPw = oldPwCtrl.text.trim();
              final newPw = newPwCtrl.text.trim();
              if (oldPw.isEmpty || newPw.isEmpty) return;
              Navigator.pop(ctx);
              await _doChangePassword(oldPw, newPw);
            },
            child: Text(s.confirm),
          ),
        ],
      ),
    ).whenComplete(() {
      oldPwCtrl.dispose();
      newPwCtrl.dispose();
    });
  }

  Future<void> _doChangePassword(
      String oldPassword, String newPassword) async {
    final s = S.current;
    final token = ref.read(authProvider).token;
    if (token == null) return;
    try {
      final api = ref.read(xboardApiProvider);
      await api.changePassword(
        token: token,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      AppNotifier.success(s.passwordChangedSuccess);
    } on XBoardApiException catch (e) {
      final msg = e.message;
      AppNotifier.error(
        msg.isNotEmpty && msg.length < 80 && !msg.startsWith('{')
            ? msg
            : s.passwordChangeFailed,
      );
    } catch (_) {
      AppNotifier.error(s.passwordChangeFailed);
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
