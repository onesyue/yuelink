import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/auth_token_service.dart';
import '../../../infrastructure/datasources/xboard_api.dart';
import '../../../l10n/app_strings.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/formatters/subscription_parser.dart' show formatBytes;
import '../../../theme.dart';

/// Full-featured account card shown at the top of the "我的" page.
/// Shows plan info, traffic progress bar, expiry, and a renewal warning.
/// Includes change-password and logout icon buttons in the header.
class AccountCard extends ConsumerWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authProvider);
    final profile = authState.userProfile;

    return Column(
      children: [
        // ── Main card ─────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
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
          child: profile == null
              ? _EmptyProfile(s: s, isDark: isDark)
              : _ProfileContent(profile: profile, s: s, isDark: isDark),
        ),
      ],
    );
  }
}

// ── Empty / loading state ─────────────────────────────────────────────────────

class _EmptyProfile extends StatelessWidget {
  final S s;
  final bool isDark;
  const _EmptyProfile({required this.s, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Avatar(label: '?', isDark: isDark),
        const SizedBox(width: 14),
        Text(s.authAccountInfo,
            style: YLText.body.copyWith(color: YLColors.zinc400)),
      ],
    );
  }
}

// ── Full profile content ──────────────────────────────────────────────────────

class _ProfileContent extends ConsumerWidget {
  final UserProfile profile;
  final S s;
  final bool isDark;

  const _ProfileContent({
    required this.profile,
    required this.s,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final used = (profile.uploadUsed ?? 0) + (profile.downloadUsed ?? 0);
    final total = profile.transferEnable;
    final percent = profile.usagePercent ?? 0.0;
    final remaining = profile.remaining;
    final expiryColor = _expiryColor(profile);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header: avatar + email + plan chip + action icons ─────
        Row(
          children: [
            _Avatar(
              label: profile.email?.isNotEmpty == true
                  ? profile.email![0].toUpperCase()
                  : '?',
              isDark: isDark,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.email ?? '—',
                    style: YLText.titleMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (profile.planName != null) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? YLColors.zinc700
                            : YLColors.zinc100,
                        borderRadius: BorderRadius.circular(YLRadius.sm),
                      ),
                      child: Text(
                        profile.planName!,
                        style: YLText.caption.copyWith(
                          color:
                              isDark ? YLColors.zinc300 : YLColors.zinc600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // ── Action icons: change password + logout ─────────────
            _ActionIcon(
              icon: Icons.lock_outline_rounded,
              tooltip: s.mineChangePassword,
              color: YLColors.zinc400,
              onTap: () => _showChangePasswordDialog(context, ref),
            ),
            const SizedBox(width: 2),
            _ActionIcon(
              icon: Icons.logout_rounded,
              tooltip: s.authLogout,
              color: YLColors.error,
              onTap: () => _confirmLogout(context, ref),
            ),
          ],
        ),

        if (total != null) ...[
          const SizedBox(height: 20),

          // ── Traffic progress bar ───────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(s.authTraffic,
                  style: YLText.caption.copyWith(color: YLColors.zinc500)),
              Text(
                '${formatBytes(used)} / ${formatBytes(total)}',
                style: YLText.caption.copyWith(
                  color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor:
                  isDark ? YLColors.zinc700 : YLColors.zinc200,
              valueColor: AlwaysStoppedAnimation<Color>(
                _progressColor(percent),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Remaining + devices + expiry row ─────────────────
          Row(
            children: [
              // Remaining
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.mineRemaining,
                        style: YLText.caption
                            .copyWith(color: YLColors.zinc500)),
                    const SizedBox(height: 2),
                    Text(
                      remaining != null ? formatBytes(remaining) : '—',
                      style: YLText.label.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : YLColors.zinc900,
                      ),
                    ),
                  ],
                ),
              ),
              // Devices online
              if (profile.deviceLimit != null) ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(s.mineDevices,
                          style: YLText.caption
                              .copyWith(color: YLColors.zinc500)),
                      const SizedBox(height: 2),
                      Text(
                        _deviceText(profile),
                        style: YLText.label.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _deviceColor(profile, isDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Expiry
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(s.authExpiry,
                      style: YLText.caption
                          .copyWith(color: YLColors.zinc500)),
                  const SizedBox(height: 2),
                  Text(
                    _expiryText(s, profile),
                    style: YLText.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: expiryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ] else ...[
          // No traffic info — show only expiry if available
          if (profile.expiredAt != null) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(s.authExpiry,
                    style:
                        YLText.body.copyWith(color: YLColors.zinc500)),
                Text(
                  _expiryText(s, profile),
                  style: YLText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: expiryColor,
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  String _expiryText(S s, UserProfile p) {
    if (p.expiredAt == null) return '—';
    if (p.isExpired) return s.authExpired;
    final days = p.daysRemaining ?? 0;
    return s.authDaysRemaining(days);
  }

  Color _progressColor(double percent) {
    if (percent < 0.6) return const Color(0xFF22C55E); // green
    if (percent < 0.85) return Colors.orange;
    return Colors.red;
  }

  Color _expiryColor(UserProfile p) {
    if (p.isExpired) return Colors.red;
    final d = p.daysRemaining;
    if (d != null && d <= 7) return Colors.orange;
    return YLColors.zinc500;
  }

  String _deviceText(UserProfile p) {
    final online = p.onlineCount ?? 0;
    final limit = p.deviceLimit;
    if (limit == null || limit <= 0) return '$online';
    return '$online / $limit';
  }

  Color _deviceColor(UserProfile p, bool isDark) {
    final online = p.onlineCount ?? 0;
    final limit = p.deviceLimit;
    if (limit != null && limit > 0 && online >= limit) return Colors.orange;
    return isDark ? Colors.white : YLColors.zinc900;
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
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
              await _doChangePassword(oldPw, newPw, ref);
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

  Future<void> _doChangePassword(String oldPassword, String newPassword, WidgetRef ref) async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    try {
      final host = await AuthTokenService.instance.getApiHost() ??
          'https://d7ccm19ki90mg.cloudfront.net';
      final api = XBoardApi(baseUrl: host);
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

  void _confirmLogout(BuildContext context, WidgetRef ref) {
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
            style: FilledButton.styleFrom(backgroundColor: YLColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            child: Text(s.authLogout),
          ),
        ],
      ),
    );
  }
}

// ── Small action icon button ─────────────────────────────────────────────────

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String label;
  final bool isDark;
  const _Avatar({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc700 : YLColors.zinc100,
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white70 : YLColors.zinc600,
          ),
        ),
      ),
    );
  }
}
