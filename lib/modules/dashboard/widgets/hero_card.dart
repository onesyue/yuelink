import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_provider.dart';
import '../../../i18n/app_strings.dart';
import '../../../app/main_shell.dart';
import '../../../theme.dart';
import '../../nodes/providers/nodes_providers.dart';
import '../../profiles/providers/profiles_providers.dart';
import '../mode_actions.dart';
import 'overview_card.dart';

class HeroCard extends ConsumerWidget {
  final CoreStatus status;
  final VoidCallback onToggle;

  const HeroCard({super.key, required this.status, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRunning = status == CoreStatus.running;
    final isDegraded = status == CoreStatus.degraded;
    final isTransitioning =
        status == CoreStatus.starting || status == CoreStatus.stopping;
    final tunSnapshot = ref.watch(desktopTunHealthProvider);

    // Active node — uses derived provider so HeroCard only rebuilds when
    // the main group's selected node changes, not on any group mutation.
    String activeNodeName = s.dashDisconnectedTitle;
    String activeNodeGroup = s.dashDisconnectedDesc;
    if (isRunning) {
      final info = ref.watch(activeProxyInfoProvider);
      if (info != null) {
        activeNodeName = info.nodeName.isNotEmpty
            ? info.nodeName
            : s.directAuto;
        activeNodeGroup = info.groupName;
      } else {
        // Status is running but the proxy graph hasn't materialised yet
        // — happens with subscriptions whose proxy-providers / rule-
        // providers fetch from the network on first start (waitProxies
        // soft-timed-out as 'slow'). Showing dashDisconnectedTitle
        // ('未连接') here was wrong: the top label already says
        // statusConnected ('保护中'), and bottom + top contradicting
        // each other made users think connect failed when it didn't.
        // ProxyGroupsNotifier's background-retry loop will populate
        // the graph as soon as mihomo finishes parsing.
        activeNodeName = s.statusProcessing; // '处理中...' / 'Processing...'
        activeNodeGroup = '';
      }
    }

    // Pills data — select() narrows rebuilds to only when active name changes.
    final activeId = ref.watch(activeProfileIdProvider);
    final routingMode = ref.watch(routingModeProvider);
    final profileName = ref.watch(
      profilesProvider.select(
        (async) => async.whenOrNull(
          data: (list) => list.where((p) => p.id == activeId).firstOrNull?.name,
        ),
      ),
    );

    final routeLabel = routingMode == 'rule'
        ? s.routeModeRule
        : routingMode == 'global'
        ? s.routeModeGlobal
        : s.routeModeDirect;

    // Connection mode pill (desktop only — mobile is always VPN/TUN)
    final connectionMode = ref.watch(connectionModeProvider);
    final showModePill =
        isRunning &&
        (Theme.of(context).platform == TargetPlatform.macOS ||
            Theme.of(context).platform == TargetPlatform.windows ||
            Theme.of(context).platform == TargetPlatform.linux);
    final isTun = connectionMode == 'tun';
    final modePillLabel = isTun ? 'TUN' : s.modeSystemProxy;

    // Active "running" accent: emerald for system-proxy, indigo for TUN.
    // Gives the user a mode signal even before reading the pill text.
    final runningAccent = isDegraded
        ? YLColors.connecting
        : YLColors.runningAccent(tun: isTun);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration:
          YLGlass.surfaceDecoration(
            context,
            radius: YLRadius.xxl,
            strong: true,
          ).copyWith(
            border: Border.all(
              color: isRunning
                  ? runningAccent.withValues(alpha: 0.30)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.72)),
              width: isRunning ? 1.0 : 0.5,
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Status dot + label ───────── Power button
          Row(
            children: [
              _PulsingStatusDot(
                color: isRunning || isDegraded
                    ? runningAccent
                    : (isTransitioning
                          ? YLColors.connecting
                          : YLColors.zinc400),
                pulsing: status == CoreStatus.starting || isDegraded,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previousChildren, ?currentChild],
                  ),
                  child: Text(
                    isRunning
                        ? s.statusConnected
                        : isDegraded
                        ? '连接异常'
                        : (isTransitioning
                              ? s.statusProcessing
                              : s.statusDisconnected),
                    key: ValueKey<String>(
                      isRunning
                          ? 'connected'
                          : isDegraded
                          ? 'degraded'
                          : (isTransitioning ? 'processing' : 'disconnected'),
                    ),
                    style: YLText.label.copyWith(
                      color: (isRunning || isDegraded)
                          ? runningAccent
                          : YLColors.zinc500,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PowerButton(
                isRunning: isRunning,
                isTransitioning: isTransitioning,
                accent: runningAccent,
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
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: YLColors.zinc400,
                  ),
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
          //
          // Routing-mode and connection-mode Pills are tappable quick
          // switches so the user doesn't have to leave the dashboard:
          //   - Tap routeLabel  → cycle rule → global → direct → rule
          //   - Tap modePill    → toggle TUN ↔ systemProxy (desktop only)
          // The underlying plumbing mirrors _FullWidthRoutingMode in
          // nodes_page.dart and ServiceModeActions in settings, routed
          // through CoreManager.api / lifecycle.
          if (isRunning) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Pill(
                  routeLabel,
                  primary: true,
                  accent: runningAccent,
                  onTap: () => _cycleRoutingMode(ref, routingMode),
                  tooltip: s.tipTapToSwitchRouting,
                ),
                if (showModePill)
                  Pill(
                    modePillLabel,
                    primary: isTun,
                    accent: runningAccent,
                    onTap: () => _toggleConnectionMode(ref, isTun),
                    tooltip: s.tipTapToSwitchConnection,
                  ),
                if (profileName != null) Pill(profileName),
              ],
            ),
          ],

          // Startup error banner with expandable report
          if ((!isRunning && !isTransitioning) || isDegraded) ...[
            Consumer(
              builder: (context, ref, _) {
                final error =
                    tunSnapshot?.userMessage ??
                    ref.watch(coreStartupErrorProvider);
                if (error == null) return const SizedBox.shrink();
                return StartupErrorBanner(error: error);
              },
            ),
          ],
        ],
      ),
    );
  }

  /// Rotate routing mode rule → global → direct → rule. The actual
  /// switch plumbing (optimistic state → persist → PATCH mihomo →
  /// revert on error) lives in [ModeActions.setRoutingMode] so the
  /// tray menu (P2-6) and this pill stay in lockstep.
  Future<void> _cycleRoutingMode(WidgetRef ref, String currentMode) async {
    const order = ['rule', 'global', 'direct'];
    final next = order[(order.indexOf(currentMode) + 1) % order.length];
    await ModeActions.setRoutingMode(ref, next);
  }

  /// Toggle TUN ↔ systemProxy. See [ModeActions.setConnectionMode] for
  /// the shared contract used by both this pill and the tray menu.
  Future<void> _toggleConnectionMode(WidgetRef ref, bool isTun) async {
    final next = isTun ? 'systemProxy' : 'tun';
    await ModeActions.setConnectionMode(ref, next);
  }
}

class PowerButton extends StatelessWidget {
  final bool isRunning;
  final bool isTransitioning;
  final Color? accent;
  final VoidCallback onTap;

  const PowerButton({
    super.key,
    required this.isRunning,
    required this.isTransitioning,
    this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isTransitioning) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: CupertinoActivityIndicator(radius: 12),
      );
    }

    final fill = accent ?? YLColors.connected;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isRunning
              ? fill
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

/// Status dot that pulses (scale + opacity) while [pulsing] is true.
/// Falls back to a steady [YLStatusDot] otherwise.
class _PulsingStatusDot extends StatefulWidget {
  final Color color;
  final bool pulsing;

  const _PulsingStatusDot({required this.color, required this.pulsing});

  @override
  State<_PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<_PulsingStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.pulsing) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulsing && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = YLStatusDot(color: widget.color);
    if (!widget.pulsing) return dot;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value; // 0 → 1
        final scale = 0.85 + 0.25 * t; // 0.85 → 1.10
        final opacity = 0.55 + 0.45 * (1 - t); // 1.0 → 0.55
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: dot,
    );
  }
}

class Pill extends StatelessWidget {
  final String label;
  final bool primary;
  final Color? accent;
  final VoidCallback? onTap;

  /// Optional hover/long-press hint. v1.0.22 P2-1 — exists so the
  /// "Pills are tappable" affordance is discoverable without
  /// dedicated onboarding UI; users on multiple platforms reported
  /// not realising the routing/connection pills could be clicked.
  final String? tooltip;
  const Pill(
    this.label, {
    super.key,
    this.primary = false,
    this.accent,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = accent ?? YLColors.connected;
    final container = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YLRadius.xl),
        color: primary
            ? (isDark
                  ? tint.withValues(alpha: 0.12)
                  : tint.withValues(alpha: 0.08))
            : (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: YLText.caption.copyWith(
          fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
          color: primary
              ? tint
              : (isDark ? YLColors.zinc400 : YLColors.zinc600),
        ),
      ),
    );
    if (onTap == null) return container;
    // Wrap in Material + InkWell for ripple feedback so tappable Pills
    // are visually distinguishable from the profile-name decorative Pill.
    final tappable = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(YLRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        child: container,
      ),
    );
    // Tooltip wraps the tappable surface so hover (desktop) and
    // long-press (mobile) both surface the hint without forcing an
    // onboarding flow. Only attaches when a hint is provided —
    // decorative Pills (e.g. profile name) stay untooltipped.
    if (tooltip == null) return tappable;
    return Tooltip(message: tooltip!, child: tappable);
  }
}
