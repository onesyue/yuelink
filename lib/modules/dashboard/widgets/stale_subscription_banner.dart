import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/profile.dart';
import '../../../theme.dart';
import '../../profiles/providers/profiles_providers.dart';
import '../../yue_auth/providers/yue_auth_providers.dart';

/// Shows a subtle warning banner when the active subscription profile
/// has not been updated in more than 24 hours.
class StaleSubscriptionBanner extends ConsumerStatefulWidget {
  const StaleSubscriptionBanner({super.key});

  @override
  ConsumerState<StaleSubscriptionBanner> createState() =>
      _StaleSubscriptionBannerState();
}

class _StaleSubscriptionBannerState
    extends ConsumerState<StaleSubscriptionBanner> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) return const SizedBox.shrink();

    final activeId = ref.watch(activeProfileIdProvider);
    if (activeId == null) return const SizedBox.shrink();

    final profileAsync = ref.watch(profilesProvider);
    final profile = profileAsync.whenOrNull(
      data: (list) => list.where((p) => p.id == activeId).firstOrNull,
    );
    if (profile == null) return const SizedBox.shrink();

    if (!_isStale(profile)) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.orange.withValues(alpha: 0.3)
        : Colors.orange.withValues(alpha: 0.2);
    final bgColor = isDark
        ? Colors.orange.withValues(alpha: 0.08)
        : Colors.orange.withValues(alpha: 0.05);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            Icons.update_disabled_rounded,
            size: 16,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '订阅配置已过期，建议更新',
              style: YLText.caption.copyWith(
                color: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: TextButton(
              onPressed: _syncing ? null : _refresh,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
              child: _syncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '更新',
                      style: YLText.caption.copyWith(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isStale(Profile profile) {
    final lastUpdated = profile.lastUpdated;
    if (lastUpdated == null) return true;
    return DateTime.now().difference(lastUpdated) > const Duration(hours: 24);
  }

  Future<void> _refresh() async {
    setState(() => _syncing = true);
    try {
      await ref.read(authProvider.notifier).syncSubscription();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }
}
