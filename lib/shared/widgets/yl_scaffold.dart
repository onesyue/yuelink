import 'package:flutter/material.dart';

import '../../theme.dart';

enum YLTitleMode { compact, large }

/// YueLink route scaffold with compact-by-default titles.
///
/// Secondary tool pages use a single compact `SliverAppBar` title so
/// Windows/macOS do not render both a toolbar title and a large body
/// title. Entry pages can opt into [YLTitleMode.large] to get Material's
/// large-title-collapses-on-scroll behaviour.
///
/// ```dart
/// YLLargeTitleScaffold(
///   title: '我的',
///   slivers: [
///     SliverToBoxAdapter(child: _ProfileHeader()),
///     SliverList(...),
///   ],
/// )
/// ```
class YLLargeTitleScaffold extends StatelessWidget {
  /// Page title — large at top, collapses to small on scroll.
  final String title;

  /// Optional small subtitle below the small (collapsed) title row.
  /// Hidden in the large-title state for a cleaner look.
  final String? subtitle;

  /// Right-aligned action buttons (icons), shown in both states.
  final List<Widget> actions;

  /// Slivers forming the scrollable body. Don't include the app bar
  /// itself — the scaffold inserts it as the first sliver.
  final List<Widget> slivers;

  /// Optional leading widget — defaults to back button when the route
  /// has a previous page, otherwise nothing.
  final Widget? leading;

  /// Whether the page should respect the bottom safe area. Tab pages
  /// owned by the bottom-nav scaffold pass false (the nav handles it).
  final bool bottomSafe;

  /// Optional fixed bottom widget (e.g. action bar). Painted on top
  /// of the slivers without scrolling.
  final Widget? bottomBar;

  /// Whether to insert the large title app bar.
  ///
  /// Main tab pages set this to false because the bottom tab bar already
  /// labels the current area; route-level pages keep the large title.
  final bool showTitleBar;

  /// Title density. Secondary tool pages default to [YLTitleMode.compact]
  /// so they don't render marketing-scale 32pt headers. Entry pages that
  /// genuinely need a hero-like first viewport can opt into [large].
  final YLTitleMode titleMode;

  /// Pull-to-refresh callback. When non-null the scroll view is wrapped
  /// in a `RefreshIndicator` so dragging from the top triggers it.
  final Future<void> Function()? onRefresh;

  /// Maximum content width when the available viewport is wider —
  /// the scrolling region is centred with empty `Scaffold` background
  /// on each side. 720dp matches Apple's macOS Music + System
  /// Settings + most desktop client conventions (Slack, VS Code,
  /// TG Desktop). Pass `null` to fill the parent (mobile default —
  /// most phones are <600dp anyway so the constraint has no effect).
  final double? maxContentWidth;

  const YLLargeTitleScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.slivers,
    this.leading,
    this.bottomSafe = true,
    this.bottomBar,
    this.showTitleBar = true,
    this.titleMode = YLTitleMode.compact,
    this.onRefresh,
    this.maxContentWidth = 720,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? YLColors.zinc950 : YLColors.zinc100;
    final appBarBg = isDark
        ? YLColors.zinc950.withValues(alpha: 0.84)
        : Colors.white.withValues(alpha: 0.72);
    final fg = isDark ? Colors.white : YLColors.zinc900;
    final isLargeTitle = titleMode == YLTitleMode.large;
    const expandedTitleSize = 30.0;
    const expandedHeight = 152.0;

    final body = CustomScrollView(
      slivers: [
        if (showTitleBar)
          if (isLargeTitle)
            SliverAppBar.large(
              expandedHeight: expandedHeight,
              backgroundColor: appBarBg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              pinned: true,
              stretch: true,
              centerTitle: false,
              automaticallyImplyLeading: leading == null,
              leading: leading,
              actions: actions,
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YLText.collapsedTitle.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsetsDirectional.only(
                  start: YLSpacing.lg,
                  bottom: YLSpacing.sm,
                ),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YLText.display.copyWith(
                    fontSize: expandedTitleSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    color: fg,
                  ),
                ),
                collapseMode: CollapseMode.pin,
              ),
            )
          else
            SliverAppBar(
              backgroundColor: appBarBg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              pinned: true,
              centerTitle: false,
              automaticallyImplyLeading: leading == null,
              leading: leading,
              actions: actions,
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YLText.collapsedTitle.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
        if (showTitleBar && subtitle != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                YLSpacing.lg,
                0,
                YLSpacing.lg,
                YLSpacing.sm,
              ),
              child: Text(
                subtitle!,
                style: YLText.caption.copyWith(
                  color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ...slivers,
        // Bottom inset spacer — pushes the last item above the system
        // gesture / navigation bar without each caller having to remember.
        const SliverPadding(padding: EdgeInsets.only(bottom: YLSpacing.xxl)),
      ],
    );

    final scrollable = onRefresh == null
        ? body
        : RefreshIndicator(onRefresh: onRefresh!, child: body);

    // Centre + cap the scrollable region on wide viewports so the
    // page reads like Apple's macOS Music / System Settings rather
    // than like a stretched mobile list. The two side gutters fall
    // back to the Scaffold background so the visual seam is invisible.
    final constrained = maxContentWidth == null
        ? scrollable
        : Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth!),
              child: scrollable,
            ),
          );

    return Scaffold(
      backgroundColor: bg,
      body: DecoratedBox(
        decoration: YLGlass.pageBackground(context),
        child: SafeArea(
          bottom: bottomSafe && bottomBar == null,
          child: constrained,
        ),
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}
