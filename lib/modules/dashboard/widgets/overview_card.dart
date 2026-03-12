import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/core_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../theme.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../shared/app_notifier.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Layer 2 — Overview Card (disconnect state only)
// ═══════════════════════════════════════════════════════════════════════════════

class OverviewCard extends ConsumerWidget {
  const OverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final autoConnect = ref.watch(autoConnectProvider);

    String? profileName;
    String? lastUpdated;
    profiles.whenData((list) {
      final active = list.where((p) => p.id == activeId).firstOrNull;
      if (active != null) {
        profileName = active.name;
        if (active.lastUpdated != null) {
          final dt = active.lastUpdated!;
          lastUpdated = '${dt.month}/${dt.day} '
              '${dt.hour.toString().padLeft(2, '0')}:'
              '${dt.minute.toString().padLeft(2, '0')}';
        }
      }
    });

    final hasProfile = profileName != null;

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile row
          Row(
            children: [
              Icon(
                hasProfile ? Icons.description_outlined : Icons.warning_amber_rounded,
                size: 14,
                color: hasProfile ? YLColors.zinc400 : YLColors.connecting,
              ),
              const SizedBox(width: 6),
              Text(
                s.navProfile,
                style: YLText.caption.copyWith(color: YLColors.zinc500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            profileName ?? s.dashNoProfileHint,
            style: hasProfile
                ? YLText.titleMedium.copyWith(fontSize: 14)
                : YLText.body.copyWith(fontSize: 13, color: YLColors.zinc500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          if (lastUpdated != null) ...[
            const SizedBox(height: 2),
            Text(
              s.updatedAt(lastUpdated!),
              style: YLText.caption.copyWith(color: YLColors.zinc400),
            ),
          ],

          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 12),

          // Status pills
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _OverviewPill(
                icon: Icons.bolt_rounded,
                label: autoConnect ? s.dashAutoConnectOn : s.dashAutoConnectOff,
                isDark: isDark,
              ),
              if (hasProfile)
                _OverviewPill(
                  icon: Icons.check_circle_outline,
                  label: s.dashReadyHint.split('.').first,
                  isDark: isDark,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _OverviewPill({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YLRadius.pill),
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: YLColors.zinc400),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YLText.caption.copyWith(
                  fontSize: 11,
                  color: isDark ? YLColors.zinc400 : YLColors.zinc600,
                )),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Startup Error Banner — shows failed step + expandable report
// ═══════════════════════════════════════════════════════════════════════════════

class StartupErrorBanner extends StatefulWidget {
  final String error;
  const StartupErrorBanner({super.key, required this.error});

  @override
  State<StartupErrorBanner> createState() => _StartupErrorBannerState();
}

class _StartupErrorBannerState extends State<StartupErrorBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final report = CoreManager.instance.lastReport;
    final steps = report?.steps ?? [];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(YLRadius.md),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Error summary + expand button
            GestureDetector(
              onTap: steps.isNotEmpty
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.error,
                      style: YLText.caption.copyWith(color: Colors.red.shade700),
                      maxLines: _expanded ? 10 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (steps.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: Colors.red.shade400,
                    ),
                  ],
                ],
              ),
            ),

            // Expanded step-by-step report
            if (_expanded && steps.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              for (final step in steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        step.success ? Icons.check_circle : Icons.cancel,
                        size: 14,
                        color: step.success ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${step.name} (${step.durationMs}ms)'
                          '${step.errorCode != null ? ' [${step.errorCode}]' : ''}'
                          '${step.error != null ? '\n${step.error}' : ''}'
                          '${step.detail != null && !step.success ? '\n${step.detail}' : ''}',
                          style: YLText.caption.copyWith(
                            fontSize: 11,
                            color: step.success
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Go core logs (last few lines)
              if (report != null && report.coreLogs.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Divider(height: 1),
                const SizedBox(height: 6),
                Text(
                  'Go Core 日志 (最后${report.coreLogs.length}行):',
                  style: YLText.caption.copyWith(
                    fontSize: 11,
                    color: Colors.red.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    report.coreLogs.take(20).join('\n'),
                    style: YLText.caption.copyWith(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: Colors.red.shade800,
                    ),
                  ),
                ),
              ],
              // Copy report button
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () {
                    final text = report?.toDebugString() ?? widget.error;
                    Clipboard.setData(ClipboardData(text: text));
                    AppNotifier.info('已复制启动报告');
                  },
                  child: Text(
                    '复制报告',
                    style: YLText.caption.copyWith(
                      fontSize: 11,
                      color: Colors.red.shade400,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
