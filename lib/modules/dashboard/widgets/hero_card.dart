import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../main.dart';
import '../../../providers/core_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../theme.dart';
import '../../nodes/providers/nodes_providers.dart';
import 'overview_card.dart';

class HeroCard extends ConsumerWidget {
  final CoreStatus status;
  final VoidCallback onToggle;

  const HeroCard({
    super.key,
    required this.status,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRunning = status == CoreStatus.running;
    final isTransitioning =
        status == CoreStatus.starting || status == CoreStatus.stopping;

    // Active node — uses derived provider so HeroCard only rebuilds when
    // the main group's selected node changes, not on any group mutation.
    String activeNodeName = s.dashDisconnectedTitle;
    String activeNodeGroup = s.dashDisconnectedDesc;
    if (isRunning) {
      final info = ref.watch(activeProxyInfoProvider);
      if (info != null) {
        activeNodeName = info.nodeName.isNotEmpty ? info.nodeName : s.directAuto;
        activeNodeGroup = info.groupName;
      }
    }

    // Pills data — select() narrows rebuilds to only when active name changes.
    final activeId = ref.watch(activeProfileIdProvider);
    final routingMode = ref.watch(routingModeProvider);
    final profileName = ref.watch(profilesProvider.select((async) =>
        async.whenOrNull(
          data: (list) =>
              list.where((p) => p.id == activeId).firstOrNull?.name,
        )));

    final routeLabel = routingMode == 'rule'
        ? s.routeModeRule
        : routingMode == 'global'
            ? s.routeModeGlobal
            : s.routeModeDirect;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xxl),
        border: Border.all(
          color: isRunning
              ? YLColors.connected.withValues(alpha: 0.30)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08)),
          width: isRunning ? 1.0 : 0.5,
        ),
        boxShadow: YLShadow.hero(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Status dot + label ───────── Power button
          Row(
            children: [
              YLStatusDot(
                color: isRunning
                    ? YLColors.connected
                    : (isTransitioning ? YLColors.connecting : YLColors.zinc400),
                glow: isRunning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isRunning
                      ? s.statusConnected
                      : (isTransitioning
                          ? s.statusProcessing
                          : s.statusDisconnected),
                  style: YLText.label.copyWith(
                    color: isRunning ? YLColors.connected : YLColors.zinc500,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              PowerButton(
                isRunning: isRunning,
                isTransitioning: isTransitioning,
                onTap: onToggle,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Row 2: Node name (tappable → Proxies)
          GestureDetector(
            onTap: isRunning
                ? () => MainShell.switchToTab(context, MainShell.tabProxies)
                : null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    activeNodeName,
                    style: YLText.titleLarge.copyWith(fontSize: 20),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isRunning)
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: YLColors.zinc400),
              ],
            ),
          ),

          const SizedBox(height: 3),
          // Row 3: Node group
          Text(
            activeNodeGroup,
            style: YLText.caption.copyWith(color: YLColors.zinc500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // Row 4: Pills (routing mode + profile name)
          if (isRunning) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Pill(routeLabel, primary: true),
                if (profileName != null) Pill(profileName),
              ],
            ),
          ],

          // Startup error banner with expandable report
          if (!isRunning && !isTransitioning) ...[
            Consumer(builder: (context, ref, _) {
              final error = ref.watch(coreStartupErrorProvider);
              if (error == null) return const SizedBox.shrink();
              return StartupErrorBanner(error: error);
            }),
          ],
        ],
      ),
    );
  }
}

class PowerButton extends StatelessWidget {
  final bool isRunning;
  final bool isTransitioning;
  final VoidCallback onTap;

  const PowerButton({
    super.key,
    required this.isRunning,
    required this.isTransitioning,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isTransitioning) {
      return const SizedBox(
        width: 44, height: 44,
        child: CupertinoActivityIndicator(radius: 12),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isRunning
              ? YLColors.connected
              : (isDark ? YLColors.zinc700 : YLColors.zinc100),
          border: isRunning
              ? null
              : Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.10),
                  width: 0.5,
                ),
        ),
        child: Icon(
          Icons.power_settings_new_rounded,
          size: 22,
          color: isRunning ? Colors.white : YLColors.zinc400,
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String label;
  final bool primary;
  const Pill(this.label, {super.key, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: primary
            ? (isDark
                ? YLColors.connected.withValues(alpha: 0.12)
                : YLColors.connected.withValues(alpha: 0.08))
            : (isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04)),
      ),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: YLText.caption.copyWith(
            fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
            color: primary
                ? YLColors.connected
                : (isDark ? YLColors.zinc400 : YLColors.zinc600),
          )),
    );
  }
}
