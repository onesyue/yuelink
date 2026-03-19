import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../core/storage/settings_service.dart';
import '../../theme.dart';

class OnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingPage({super.key, required this.onComplete});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _currentPage = 0;

  static final bool _isDesktop = Platform.isMacOS || Platform.isWindows;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    SettingsService.setHasSeenOnboarding(true);
    widget.onComplete();
  }

  void _next() {
    if (_currentPage < 3) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final pages = [
      _OnboardingContent(
        icon: Icons.link_rounded,
        iconColor: isDark ? Colors.white : YLColors.primary,
        title: s.onboardingWelcome,
        description: s.onboardingWelcomeDesc,
      ),
      _OnboardingContent(
        icon: Icons.power_settings_new_rounded,
        iconColor: YLColors.connected,
        title: s.onboardingConnect,
        description: s.onboardingConnectDesc,
      ),
      _OnboardingContent(
        icon: Icons.public_rounded,
        iconColor: Colors.blue,
        title: s.onboardingNodes,
        description: s.onboardingNodesDesc,
      ),
      _OnboardingContent(
        icon: Icons.storefront_rounded,
        iconColor: Colors.orange,
        title: s.onboardingStore,
        description: s.onboardingStoreDesc,
      ),
    ];

    // Desktop: horizontal layout with preview on left, content on right
    if (_isDesktop) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 480),
            child: Container(
              margin: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark ? YLColors.zinc900 : Colors.white,
                borderRadius: BorderRadius.circular(YLRadius.xl),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.5,
                ),
                boxShadow: YLShadow.card(context),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  // Left: colored accent panel with icon
                  Expanded(
                    flex: 2,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            pages[_currentPage].iconColor.withValues(alpha: 0.15),
                            pages[_currentPage].iconColor.withValues(alpha: 0.05),
                          ],
                        ),
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Container(
                            key: ValueKey(_currentPage),
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: pages[_currentPage]
                                  .iconColor
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Icon(
                              pages[_currentPage].icon,
                              size: 44,
                              color: pages[_currentPage].iconColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Right: text content + controls
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Skip
                          Align(
                            alignment: Alignment.topRight,
                            child: TextButton(
                              onPressed: _finish,
                              child: Text(s.onboardingSkip,
                                  style: YLText.caption
                                      .copyWith(color: YLColors.zinc400)),
                            ),
                          ),
                          const Spacer(),
                          // Title + description
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Column(
                              key: ValueKey(_currentPage),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pages[_currentPage].title,
                                  style: YLText.titleLarge.copyWith(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : YLColors.zinc900,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  pages[_currentPage].description,
                                  style: YLText.body.copyWith(
                                    color: YLColors.zinc500,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // Indicators + button
                          Row(
                            children: [
                              // Dots
                              ...List.generate(4, (i) {
                                final isActive = i == _currentPage;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin:
                                      const EdgeInsets.only(right: 6),
                                  width: isActive ? 20 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? (isDark
                                            ? Colors.white
                                            : YLColors.primary)
                                        : (isDark
                                            ? YLColors.zinc700
                                            : YLColors.zinc200),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                );
                              }),
                              const Spacer(),
                              FilledButton(
                                onPressed: _next,
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      isDark ? Colors.white : YLColors.primary,
                                  foregroundColor:
                                      isDark ? YLColors.primary : Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(YLRadius.lg),
                                  ),
                                ),
                                child: Text(
                                  _currentPage == 3
                                      ? s.onboardingDone
                                      : s.onboardingNext,
                                  style: YLText.label
                                      .copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Mobile: vertical full-screen layout
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                // Skip button
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
                    child: TextButton(
                      onPressed: _finish,
                      child: Text(s.onboardingSkip,
                          style:
                              YLText.body.copyWith(color: YLColors.zinc400)),
                    ),
                  ),
                ),

                // Page content
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    children: pages,
                  ),
                ),

                // Page indicators
                Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final isActive = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: isActive ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? (isDark ? Colors.white : YLColors.primary)
                              : (isDark
                                  ? YLColors.zinc700
                                  : YLColors.zinc200),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),

                // Next / Done button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            isDark ? Colors.white : YLColors.primary,
                        foregroundColor:
                            isDark ? YLColors.primary : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YLRadius.xl),
                        ),
                      ),
                      child: Text(
                        _currentPage == 3
                            ? s.onboardingDone
                            : s.onboardingNext,
                        style: YLText.label
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
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

class _OnboardingContent extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const _OnboardingContent({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 44, color: iconColor),
          ),
          const SizedBox(height: 36),
          Text(
            title,
            style: YLText.titleLarge.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : YLColors.zinc900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: YLText.body.copyWith(
              color: YLColors.zinc500,
              height: 1.6,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
