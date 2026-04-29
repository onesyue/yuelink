import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

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
    setState(() {
      _currentIndex = index;
      _builtTabs[index] = true;
    });
    SettingsService.setLastTabIndex(index);
    SettingsService.setBuiltTabs(
      _builtTabs.keys.where((k) => _builtTabs[k] == true).toList(),
    );
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
    // Restore previously visited tabs from persistence (Android process restore)
    final savedTabs = ref.read(initialBuiltTabsProvider);
    _builtTabs = <int, bool>{
      for (final i in savedTabs)
        if (i >= 0 && i < _pages.length) i: true,
    };
    _builtTabs[_currentIndex] = true;

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
    final mobileItems = <_GlassTabSpec>[
      _GlassTabSpec(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: s.navHome,
      ),
      _GlassTabSpec(
        icon: Icons.public_outlined,
        activeIcon: Icons.public,
        label: s.navProxies,
      ),
      _GlassTabSpec(
        icon: Icons.play_circle_outline,
        activeIcon: Icons.play_circle_filled,
        label: s.navEmby,
      ),
      _GlassTabSpec(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: s.navMine,
      ),
    ];

    // extendBody all platforms — every platform paints a real
    // BackdropFilter behind the bar, so body content needs to scroll
    // through. Android uses a much smaller sigma to stay within the
    // frame budget; see _GlassBottomNav for the platform table.
    return Scaffold(
      extendBody: true,
      body: RepaintBoundary(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            for (int i = 0; i < _pages.length; i++)
              _builtTabs[i] == true ? _pages[i] : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: _GlassBottomNav(
        items: mobileItems,
        currentIndex: _currentIndex,
        onTap: (i) {
          if (i != _currentIndex) HapticFeedback.selectionClick();
          switchTab(i);
        },
        isDark: isDark,
      ),
    );
  }
}

// ── Bottom glass nav (iOS 26 / Telegram-inspired) ──────────────────────

class _GlassTabSpec {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _GlassTabSpec({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// Cross-platform glass bottom bar — translucent material with a real
/// `BackdropFilter` blur, springy icon swap, and tracking text-weight
/// transition on the active tab. Sigma is platform-tuned so every
/// target gets the frosted look without burning the frame budget.
///
/// Sigma table:
///   * iOS / macOS / Windows / Linux — 24 (matches toast, headroom on
///     every desktop GPU and on Apple Metal).
///   * Android — 8 (Impeller Android re-rasterises the scene under a
///     BackdropFilter; gaussian-blur cost grows ~O(σ²), so 30→8 cuts
///     work ~14× and stays within the frame cap on mid-tier devices).
///     Visually weaker than 24 but still reads as frosted glass — TG
///     and Apple Music use comparable values on Android. Real-world
///     report 2026-04-29: sigma 30 ANR'd app at startup on a mid-tier
///     Android — the value below is the largest one that survived in
///     manual testing.
class _GlassBottomNav extends StatelessWidget {
  final List<_GlassTabSpec> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isDark;

  const _GlassBottomNav({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    // Lighter tint on Android — the smaller blur sigma needs more
    // alpha-tint help to read as glass instead of "transparent panel
    // with smeared content under it".
    final glassColor = isAndroid
        ? (isDark
            ? Colors.black.withValues(alpha: 0.70)
            : Colors.white.withValues(alpha: 0.78))
        : (isDark
            ? Colors.black.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.65));
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final blurSigma = isAndroid ? 8.0 : 24.0;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: glassColor,
            border: Border(
              top: BorderSide(color: borderColor, width: 0.33),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 58,
              child: Padding(
                padding: EdgeInsets.only(
                  top: 4,
                  bottom: bottomInset > 0 ? 0 : 6,
                ),
                child: Row(
                  children: [
                    for (int i = 0; i < items.length; i++)
                      Expanded(
                        child: _GlassTabButton(
                          spec: items[i],
                          isActive: i == currentIndex,
                          isDark: isDark,
                          onTap: () => onTap(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One slot of [_GlassBottomNav]. Active state animates: outline→filled
/// icon swap with overshoot scale, label colour + weight crossfade, and
/// a subtle press-scale on tap-down. No text-only fallback variant —
/// labels are always shown so the bar reads consistently across locales.
class _GlassTabButton extends StatefulWidget {
  final _GlassTabSpec spec;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _GlassTabButton({
    required this.spec,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_GlassTabButton> createState() => _GlassTabButtonState();
}

class _GlassTabButtonState extends State<_GlassTabButton> {
  bool _pressed = false;

  Color get _activeColor =>
      widget.isDark ? Colors.white : YLColors.primary;
  Color get _inactiveColor =>
      widget.isDark ? YLColors.zinc500 : YLColors.zinc500;

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive ? _activeColor : _inactiveColor;
    final iconData =
        widget.isActive ? widget.spec.activeIcon : widget.spec.icon;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 24,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    return ScaleTransition(
                      scale: Tween<double>(begin: 0.55, end: 1.0).animate(
                        CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                      child: FadeTransition(opacity: anim, child: child),
                    );
                  },
                  child: Icon(
                    iconData,
                    key: ValueKey(
                      '${widget.spec.label}-${widget.isActive}',
                    ),
                    size: 22,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.1,
                  color: color,
                  fontWeight:
                      widget.isActive ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
                child: Text(widget.spec.label),
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
