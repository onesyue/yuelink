import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../yue_auth/providers/yue_auth_providers.dart';
import '../../../l10n/app_strings.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../shared/formatters/subscription_parser.dart' show formatBytes;
import '../../../theme.dart';

/// Shows subscription traffic quota (from XBoard) + real-time speed (from mihomo).
class TrafficUsageCard extends ConsumerWidget {
  const TrafficUsageCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.watch(userProfileProvider);
    final divider = Divider(
      height: 1,
      thickness: 0.5,
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.06),
    );

    // XBoard cumulative values (always available from cached profile)
    final uploadUsed = profile?.uploadUsed;
    final downloadUsed = profile?.downloadUsed;

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
          // ── Total quota (from XBoard) ──────────────────────────
          if (profile?.transferEnable != null) ...[
            _TrafficRow(
              icon: Icons.data_usage_rounded,
              iconColor: YLColors.zinc400,
              label: s.authTraffic,
              value: _usageText(profile!),
              isDark: isDark,
            ),
            divider,
          ],

          // ── Upload used (from XBoard u field) ─────────────────
          _TrafficRow(
            icon: Icons.arrow_upward_rounded,
            iconColor: const Color(0xFF3B82F6),
            label: s.trafficUpload,
            value: uploadUsed != null ? formatBytes(uploadUsed) : '—',
            isDark: isDark,
          ),
          divider,

          // ── Download used (from XBoard d field) ───────────────
          _TrafficRow(
            icon: Icons.arrow_downward_rounded,
            iconColor: const Color(0xFF22C55E),
            label: s.trafficDownload,
            value: downloadUsed != null ? formatBytes(downloadUsed) : '—',
            isDark: isDark,
          ),

        ],
      ),
    );
  }

  String _usageText(UserProfile profile) {
    final used = (profile.uploadUsed ?? 0) + (profile.downloadUsed ?? 0);
    final total = profile.transferEnable!;
    // transferEnable and u/d are all in bytes (XBoard users table)
    return '${formatBytes(used)} / ${formatBytes(total)}';
  }
}

class _TrafficRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool isDark;

  const _TrafficRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: YLText.body.copyWith(color: YLColors.zinc500)),
          ),
          Text(
            value,
            style: YLText.body.copyWith(
              color: isDark ? YLColors.zinc200 : YLColors.zinc700,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
