import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_provider.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';
import '../smart_select/smart_select_provider.dart';
import 'scene_mode.dart';
import 'scene_mode_provider.dart';

/// Bottom sheet for switching between the 4 preset scene modes.
///
/// Usage:
/// ```dart
/// SceneModeSheet.show(context);
/// ```
class SceneModeSheet extends ConsumerWidget {
  const SceneModeSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SceneModeSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeAsync = ref.watch(sceneModeProvider);
    final active = activeAsync.value ?? SceneMode.daily;

    final bg = isDark ? YLColors.zinc900 : Colors.white;
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                '场景模式',
                style: YLText.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? YLColors.zinc100 : YLColors.zinc800,
                ),
              ),
            ),

            Divider(height: 1, color: divider),

            // Scene tiles
            for (final mode in SceneMode.values) ...[
              _SceneTile(
                mode: mode,
                config: kSceneModeDefaults[mode]!,
                isActive: mode == active,
                isDark: isDark,
                onTap: () async {
                  // 1. 切换场景
                  await ref.read(sceneModeProvider.notifier).setMode(mode);

                  // 2. 切 mihomo routing mode（rule/global/direct）
                  final config = ref.read(sceneModeConfigProvider);
                  final api = ref.read(mihomoApiProvider);
                  try {
                    await api.setRoutingMode(config.routingMode);
                  } catch (e) {
                    // Scene switched but routing mode didn't follow — user
                    // sees the chip flip but traffic keeps old routing. Log
                    // so support can map "scene doesn't take effect" to an
                    // API failure instead of guessing.
                    debugPrint(
                        '[SceneMode] setRoutingMode(${config.routingMode}) '
                        'failed after switching to $mode: $e');
                  }

                  // 3. VPN 在跑 → 自动触发智能选线
                  final isRunning = ref.read(coreStatusProvider) == CoreStatus.running;
                  if (isRunning) {
                    ref.read(smartSelectProvider.notifier).runTest();
                    if (context.mounted) {
                      AppNotifier.info('已切换到${mode.label}模式，正在智能选线...');
                    }
                  }

                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              if (mode != SceneMode.values.last)
                Divider(height: 1, indent: 60, color: divider),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _SceneTile extends StatelessWidget {
  final SceneMode mode;
  final SceneModeConfig config;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _SceneTile({
    required this.mode,
    required this.config,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isDark ? YLColors.zinc100 : YLColors.zinc800;
    final inactiveColor = isDark ? YLColors.zinc400 : YLColors.zinc500;
    final labelColor = isActive ? activeColor : inactiveColor;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Icon
            SizedBox(
              width: 36,
              child: Text(
                mode.icon,
                style: const TextStyle(fontSize: 22),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 4),

            // Label + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: YLText.body.copyWith(
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    config.description,
                    style: YLText.caption.copyWith(color: YLColors.zinc400),
                  ),
                ],
              ),
            ),

            // Check mark
            if (isActive)
              Icon(
                Icons.check_rounded,
                size: 18,
                color: isDark ? YLColors.zinc200 : YLColors.zinc700,
              ),
          ],
        ),
      ),
    );
  }
}
