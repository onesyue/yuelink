import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../app/main_shell.dart';
import '../../../theme.dart';
import '../../nodes/scene_mode/scene_mode_sheet.dart';
import '../../nodes/smart_select/smart_select_sheet.dart';
import '../home_content_provider.dart';

/// 首页快捷操作行 — 智能选线 / 场景模式 / 测速
///
/// Reads [quickActionsConfigProvider] to decide which tiles are visible.
/// Dividers are placed only between adjacent visible tiles; if all tiles are
/// hidden the widget returns [SizedBox.shrink].
class QuickActions extends ConsumerWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.of(context);
    // Falls back to QuickActionsConfig() (all visible) on error / loading.
    final cfg = ref.watch(quickActionsConfigProvider);

    // Build the ordered list of visible actions.
    final actions = <({IconData icon, String label, VoidCallback onTap})>[];

    if (cfg.showSmartSelect) {
      actions.add((
        icon: Icons.auto_awesome_rounded,
        label: s.qaSmartSelect,
        onTap: () => showSmartSelectSheet(context),
      ));
    }
    if (cfg.showSceneMode) {
      actions.add((
        icon: Icons.theater_comedy_rounded,
        label: s.qaSceneMode,
        onTap: () => SceneModeSheet.show(context),
      ));
    }
    if (cfg.showSpeedTest) {
      actions.add((
        icon: Icons.speed_rounded,
        label: s.qaSpeedTest,
        onTap: () => MainShell.switchToTab(context, MainShell.tabProxies),
      ));
    }

    // Nothing to show — collapse entirely so no dead space remains.
    if (actions.isEmpty) return const SizedBox.shrink();

    // Build Row children: interleave dividers only between visible tiles.
    final rowChildren = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) rowChildren.add(_VerticalDivider(isDark: isDark));
      rowChildren.add(Expanded(
        child: _ActionTile(
          icon: actions[i].icon,
          label: actions[i].label,
          isDark: isDark,
          onTap: actions[i].onTap,
        ),
      ));
    }

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
      child: Row(children: rowChildren),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  final bool isDark;
  const _VerticalDivider({required this.isDark});

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
  final bool isDark;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
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
            Icon(
              icon,
              size: 20,
              color: isDark ? Colors.white70 : YLColors.zinc700,
            ),
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
