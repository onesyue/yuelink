import 'dart:developer' show Timeline;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/providers/core_runtime_providers.dart';
import '../core/storage/settings_service.dart';
import '../i18n/app_strings.dart';
import '../modules/dashboard/dashboard_page.dart';
import '../modules/emby/emby_media_page.dart';
import '../modules/emby/emby_providers.dart';
import '../modules/emby/emby_web_page.dart';
import '../modules/nodes/nodes_page.dart';
import '../modules/settings/settings_page.dart';
import '../theme.dart';

/// Initial tab index restored from SettingsService (Android process restore).
/// Overridden by main.dart's ProviderScope at boot with the persisted value.
final initialTabIndexProvider = Provider<int>((ref) => 0);

/// Pre-loaded built tabs (avoids SizedBox.shrink for previously visited tabs).
final initialBuiltTabsProvider = Provider<List<int>>((ref) => [0]);

/// One-shot navigation request from outside the widget tree (e.g. the
/// Android Quick Settings tile long-press). MainShell listens and swaps
/// to the requested tab, then resets to null.
final tileNavRequestProvider = StateProvider<int?>((ref) => null);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key = const ValueKey('mainShell')});

  /// Tab indices for programmatic navigation.
  static const tabDashboard = 0;
  static const tabProxies = 1;
  static const tabEmby = 2;
  static const tabSettings = 3;

  static void switchToTab(BuildContext context, int index) {
    context.findAncestorStateOfType<_MainShellState>()?.switchTab(index);
  }

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _currentIndex;
  late final Map<int, bool> _builtTabs;
  ProviderSubscription? _tileNavSub;

  void switchTab(int index) {
    final alreadyBuilt = _builtTabs[index] == true;
    Timeline.startSync('MainShell.switchTab[$index] built=$alreadyBuilt');
    // Always emit so profile builds (used for ANR diagnosis) can see it
    // in logcat. Cost is one log line per user tab tap — negligible.
    debugPrint('[MainShell] switchTab $index built=$alreadyBuilt');

    // Step 1: flip the visible index immediately so the user sees a
    // response. If the destination tab has never been built, IndexedStack
    // shows SizedBox.shrink for one frame — that single blank frame is
    // what gives the Choreographer enough budget to dispatch input
    // instead of accumulating a 5-s queue and triggering ANR.
    setState(() {
      _currentIndex = index;
    });
    Timeline.finishSync();

    // Step 2: schedule the heavy first-build for the next frame.
    if (!alreadyBuilt) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _builtTabs[index] == true) return;
        Timeline.startSync('MainShell.firstBuild[$index]');
        setState(() => _builtTabs[index] = true);
        Timeline.finishSync();
      });
    }

    SettingsService.setLastTabIndex(index);
    // (B) Persist only the current tab — see initState comment. We never
    // want to restore N tabs on the next cold start.
    SettingsService.setBuiltTabs([index]);
  }

  static const _pages = [
    DashboardPage(),
    NodesPage(),
    _EmbyTabPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = ref
        .read(initialTabIndexProvider)
        .clamp(0, _pages.length - 1);
    // (B) Cold-start ANR fix: only mount the current tab. Pre-warming
    // multiple tabs in a single frame builds 4 heavy pages on the
    // critical path right after auto-connect — main thread starves and
    // Android fires ANR before the first proxy_groups push lands.
    // The "feel" benefit of pre-warming is small; the ANR risk is large.
    _builtTabs = <int, bool>{_currentIndex: true};

    // Listen for one-shot navigation requests from outside the widget
    // tree (currently: Android tile long-press). Reset to null after
    // handling so a re-set to the same value still fires.
    _tileNavSub = ref.listenManual<int?>(tileNavRequestProvider, (_, next) {
      if (next == null) return;
      if (next >= 0 && next < _pages.length) switchTab(next);
      // Use microtask so the notifier isn't mutated during the notification.
      Future.microtask(
        () => ref.read(tileNavRequestProvider.notifier).state = null,
      );
    });
  }

  @override
  void dispose() {
    _tileNavSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 640;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            // ── Sidebar ────────────────────────────────────────
            RepaintBoundary(
              child: _Sidebar(
                currentIndex: _currentIndex,
                onSelect: (i) => switchTab(i),
              ),
            ),

            // ── Sidebar / content divider ──────────────────────
            Container(
              width: 0.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),

            // ── Content ────────────────────────────────────────
            Expanded(
              child: RepaintBoundary(
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    for (int i = 0; i < _pages.length; i++)
                      _builtTabs[i] == true
                          ? _pages[i]
                          : const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Mobile bottom navigation ─────────────────────────────────
    final s = S.of(context);
    final mobileItems = <YLGlassTabSpec>[
      YLGlassTabSpec(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: s.navHome,
      ),
      YLGlassTabSpec(
        icon: Icons.public_outlined,
        activeIcon: Icons.public,
        label: s.navProxies,
      ),
      YLGlassTabSpec(
        icon: Icons.play_circle_outline,
        activeIcon: Icons.play_circle_filled,
        label: s.navEmby,
      ),
      YLGlassTabSpec(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: s.navMine,
      ),
    ];

    // Let the tab bar participate in layout instead of floating over
    // content. This keeps the last card / row reachable on phones while
    // still giving the bar a light glass finish.
    return Scaffold(
      extendBody: false,
      body: RepaintBoundary(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            for (int i = 0; i < _pages.length; i++)
              _builtTabs[i] == true ? _pages[i] : const SizedBox.shrink(),
          ],
        ),
      ),
      // Keep this glass bar deliberately cheap. The previous experiment
      // animated every tab with nested switchers/scales and caused an
      // Android GPU/CPU spike. This version uses one blur layer and one
      // moving indicator; tab contents are plain static widgets.
      bottomNavigationBar: YLGlassBottomNav(
        key: const ValueKey('main_glass_bottom_nav'),
        currentIndex: _currentIndex,
        items: mobileItems,
        onSelect: (i) {
          if (i != _currentIndex) HapticFeedback.selectionClick();
          switchTab(i);
        },
      ),
    );
  }
}

// ── Bottom glass nav (iOS 26 / Telegram-inspired) ──────────────────────

class YLGlassTabSpec {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const YLGlassTabSpec({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class YLGlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<YLGlassTabSpec> items;
  final ValueChanged<int> onSelect;

  const YLGlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onSelect,
  }) : assert(items.length > 0);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomPadding = math.max(8.0, bottomInset);

    final glassColor = isDark
        ? YLColors.zinc950.withValues(alpha: 0.74)
        : Colors.white.withValues(alpha: 0.76);
    final topLine = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.68);
    final bottomLine = isDark
        ? Colors.black.withValues(alpha: 0.32)
        : Colors.black.withValues(alpha: 0.06);

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.12),
              blurRadius: 24,
              spreadRadius: -10,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: EdgeInsets.fromLTRB(10, 8, 10, bottomPadding),
              decoration: BoxDecoration(
                color: glassColor,
                border: Border(
                  top: BorderSide(color: topLine, width: 0.7),
                  bottom: BorderSide(color: bottomLine, width: 0.33),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.08 : 0.34),
                    glassColor,
                  ],
                ),
              ),
              child: SizedBox(
                height: 56,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final count = items.length;
                    final safeIndex = currentIndex.clamp(0, count - 1);
                    final itemWidth = constraints.maxWidth / count;
                    final indicatorWidth = math.min(86.0, itemWidth - 8);
                    final indicatorLeft =
                        safeIndex * itemWidth +
                        (itemWidth - indicatorWidth) / 2;

                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        AnimatedPositioned(
                          key: const ValueKey('main_glass_nav_indicator'),
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          left: indicatorLeft,
                          top: 5,
                          width: indicatorWidth,
                          height: 46,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.10)
                                  : Colors.white.withValues(alpha: 0.58),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : Colors.white.withValues(alpha: 0.82),
                                width: 0.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: YLColors.primary.withValues(
                                    alpha: isDark ? 0.18 : 0.12,
                                  ),
                                  blurRadius: 18,
                                  spreadRadius: -8,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isDark ? 0.34 : 0.08,
                                  ),
                                  blurRadius: 14,
                                  spreadRadius: -8,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (int i = 0; i < count; i++)
                              Expanded(
                                child: _YLGlassBottomNavItem(
                                  key: ValueKey('main_glass_nav_item_$i'),
                                  spec: items[i],
                                  selected: safeIndex == i,
                                  onTap: () => onSelect(i),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _YLGlassBottomNavItem extends StatelessWidget {
  final YLGlassTabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  const _YLGlassBottomNavItem({
    super.key,
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? Colors.white : YLColors.primary;
    final inactiveColor = isDark ? YLColors.zinc400 : YLColors.zinc500;

    return Semantics(
      button: true,
      selected: selected,
      label: spec.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? spec.activeIcon : spec.icon,
                size: 21,
                color: selected ? activeColor : inactiveColor,
              ),
              const SizedBox(height: 3),
              Text(
                spec.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: YLText.badge.copyWith(
                  color: selected ? activeColor : inactiveColor,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sidebar ────────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _Sidebar({required this.currentIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final navItems = [
      (Icons.home_outlined, Icons.home_filled, s.navHome),
      (Icons.public_outlined, Icons.public, s.navProxies),
      (Icons.play_circle_outline, Icons.play_circle_filled, s.navEmby),
    ];

    return Container(
      width: 230,
      color: isDark
          ? YLColors.zinc900
          : YLColors.zinc50, // Sidebar one shade lighter than zinc100 bg
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Brand ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: YLColors.primary,
                    borderRadius: BorderRadius.circular(YLRadius.xl),
                  ),
                  child: const Icon(
                    Icons.link_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '悦通',
                      style: YLText.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'AI · 全球加速',
                      style: YLText.caption.copyWith(color: YLColors.zinc400),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Navigation items ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (int i = 0; i < navItems.length; i++)
                  _SidebarItem(
                    icon: currentIndex == i ? navItems[i].$2 : navItems[i].$1,
                    label: navItems[i].$3,
                    isActive: currentIndex == i,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ),

          const Spacer(),

          // ── 我的 at bottom ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            child: _SidebarItem(
              icon: currentIndex == MainShell.tabSettings
                  ? Icons.person_rounded
                  : Icons.person_outline_rounded,
              label: s.navMine,
              isActive: currentIndex == MainShell.tabSettings,
              onTap: () => onSelect(MainShell.tabSettings),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeColor = isDark ? YLColors.zinc800 : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isActive ? activeColor : Colors.transparent,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        shadowColor: Colors.black.withValues(alpha: 0.05),
        elevation: isActive && !isDark ? 1 : 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(YLRadius.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: isActive
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(YLRadius.lg),
                    border: Border.all(color: borderColor, width: 0.5),
                  )
                : null,
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isActive
                      ? (isDark ? Colors.white : YLColors.zinc900)
                      : YLColors.zinc500,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: YLText.body.copyWith(
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? (isDark ? Colors.white : YLColors.zinc900)
                        : YLColors.zinc500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Emby tab wrapper ──────────────────────────────────────────────────────────

/// Full-screen tab wrapper for 悦视频.
/// Watches [embyProvider] and delegates to [EmbyMediaPage] (native) or
/// [EmbyWebPage] (WebView fallback) once info is loaded.
class _EmbyTabPage extends ConsumerWidget {
  const _EmbyTabPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final coreStatus = ref.watch(displayCoreStatusProvider);
    final emby = ref.watch(embyProvider);
    return emby.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => ref.invalidate(embyProvider),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(s.retry),
              ),
            ],
          ),
        ),
      ),
      data: (info) {
        if (info == null || !info.hasAccess) {
          return Scaffold(body: Center(child: Text(s.mineEmbyNoAccess)));
        }
        if (coreStatus != CoreStatus.running) {
          return _EmbyNeedsConnectionPage(
            status: coreStatus,
            onOpenHome: () =>
                MainShell.switchToTab(context, MainShell.tabDashboard),
          );
        }
        if (info.hasNativeAccess) {
          return EmbyMediaPage(
            serverUrl: info.serverBaseUrl!,
            userId: info.parsedUserId!,
            accessToken: info.parsedAccessToken!,
            serverId: info.parsedServerId ?? '',
          );
        }
        return EmbyWebPage(url: info.launchUrl!);
      },
    );
  }
}

class _EmbyNeedsConnectionPage extends StatelessWidget {
  final CoreStatus status;
  final VoidCallback onOpenHome;

  const _EmbyNeedsConnectionPage({
    required this.status,
    required this.onOpenHome,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTransitioning =
        status == CoreStatus.starting || status == CoreStatus.stopping;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(YLSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 52,
                    color: isDark ? YLColors.zinc500 : YLColors.zinc400,
                  ),
                  const SizedBox(height: YLSpacing.lg),
                  Text(
                    s.mineEmbyNeedsVpn,
                    textAlign: TextAlign.center,
                    style: YLText.titleMedium.copyWith(
                      color: isDark ? Colors.white : YLColors.zinc900,
                    ),
                  ),
                  const SizedBox(height: YLSpacing.sm),
                  Text(
                    '连接后会通过当前节点访问媒体库，避免请求打到未启动的 127.0.0.1 本地代理。',
                    textAlign: TextAlign.center,
                    style: YLText.body.copyWith(
                      color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                    ),
                  ),
                  const SizedBox(height: YLSpacing.xl),
                  FilledButton(
                    onPressed: isTransitioning ? null : onOpenHome,
                    child: Text(isTransitioning ? '正在切换连接状态' : '去首页开启保护'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
