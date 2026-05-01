import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../../../domain/surge_modules/module_entity.dart';
import '../providers/module_provider.dart';
import 'compatibility_badge.dart';

/// Card showing a single [ModuleRecord] in the modules list.
class ModuleCard extends ConsumerWidget {
  final ModuleRecord module;
  final VoidCallback? onTap;

  const ModuleCard({super.key, required this.module, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return YLSurface(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(YLRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: YLSpacing.md,
            vertical: YLSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Leading: enable/disable toggle
              SizedBox(
                width: 44,
                child: Switch(
                  value: module.enabled,
                  onChanged: (_) {
                    ref.read(moduleProvider.notifier).toggleEnabled(module.id);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Body
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            module.name,
                            style: YLText.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? YLColors.zinc100
                                  : YLColors.zinc800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (module.desc.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        module.desc,
                        style: YLText.caption.copyWith(color: YLColors.zinc500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Badges row
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // Rule count badge
                        _RuleCountBadge(
                          count: module.rules.length,
                          isDark: isDark,
                        ),
                        // Compatibility badge
                        CompatibilityBadge(counts: module.unsupportedCounts),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Source URL
                    Text(
                      _truncateUrl(module.sourceUrl),
                      style: YLText.caption.copyWith(
                        color: YLColors.zinc400,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Trailing chevron
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: YLColors.zinc400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _truncateUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.host}${uri.path}';
    } catch (_) {
      return url;
    }
  }
}

class _RuleCountBadge extends StatelessWidget {
  final int count;
  final bool isDark;

  const _RuleCountBadge({required this.count, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc700 : YLColors.zinc100,
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Text(
        '$count rules',
        style: YLText.caption.copyWith(
          color: isDark ? YLColors.zinc300 : YLColors.zinc600,
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
      ),
    );
  }
}
