import 'dart:io';

import 'package:flutter/material.dart';

import '../../i18n/app_strings.dart';
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

  Future<void> _finish() async {
    await SettingsService.setHasSeenOnboarding(true);
    widget.onComplete();
  }

  static const _lastPage = 3;

  void _next() {
    if (_currentPage < _lastPage) {
      if (_isDesktop) {
        setState(() => _currentPage++);
      } else {
        _controller.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Step order + icons map to the user funnel (awareness → activation
    // → value → retention), not app-page order:
    //  1. Welcome + positioning  → Public icon (global network)
    //  2. One-tap connect        → Power icon (core action)
    //  3. Emby streaming perk    → Movie icon (differentiator)
    //  4. Check-in + multi-sync  → Card-gift icon (retention hook)
    final steps = [
      _Step(
        icon: Icons.public_rounded,
        title: s.onboardingWelcome,
        desc: s.onboardingWelcomeDesc,
      ),
      _Step(
        icon: Icons.power_settings_new_rounded,
        title: s.onboardingConnect,
        desc: s.onboardingConnectDesc,
      ),
      _Step(
        icon: Icons.movie_outlined,
        title: s.onboardingNodes,
        desc: s.onboardingNodesDesc,
      ),
      _Step(
        icon: Icons.card_giftcard_rounded,
        title: s.onboardingStore,
        desc: s.onboardingStoreDesc,
      ),
    ];

    if (_isDesktop) {
      return _DesktopOnboarding(
        steps: steps,
        current: _currentPage,
        isDark: isDark,
        s: s,
        onNext: _next,
        onSkip: _finish,
      );
    }

    return _MobileOnboarding(
      steps: steps,
      controller: _controller,
      current: _currentPage,
      isDark: isDark,
      s: s,
      onPageChanged: (i) => setState(() => _currentPage = i),
      onNext: _next,
      onSkip: _finish,
    );
  }
}

class _Step {
  final IconData icon;
  final String title;
  final String desc;
  const _Step({
    required this.icon,
    required this.title,
    required this.desc,
  });
}

// ── Desktop layout ─────────────────────────────────────────────────────────

class _DesktopOnboarding extends StatelessWidget {
  final List<_Step> steps;
  final int current;
  final bool isDark;
  final S s;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _DesktopOnboarding({
    required this.steps,
    required this.current,
    required this.isDark,
    required this.s,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final step = steps[current];
    final surface = isDark ? YLColors.zinc900 : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final iconFg = isDark ? Colors.white : YLColors.primary;
    final iconBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return Scaffold(
      backgroundColor: isDark ? YLColors.zinc950 : YLColors.zinc100,
      body: Center(
        child: Container(
          width: 520,
          constraints: const BoxConstraints(maxHeight: 380),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(YLRadius.xl),
            border: Border.all(color: border, width: 0.5),
            boxShadow: YLShadow.card(context),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 32, 40, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Skip (top right)
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: onSkip,
                    child: Text(
                      s.onboardingSkip,
                      style: YLText.caption.copyWith(color: YLColors.zinc400),
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                // Icon
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    key: ValueKey(current),
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(YLRadius.lg),
                      border: Border.all(color: border, width: 0.5),
                    ),
                    child: Icon(step.icon, size: 28, color: iconFg),
                  ),
                ),
                const SizedBox(height: 24),
                // Title
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    step.title,
                    key: ValueKey('t$current'),
                    style: YLText.titleLarge.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : YLColors.zinc900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                // Description
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    step.desc,
                    key: ValueKey('d$current'),
                    style: YLText.body.copyWith(
                      color: YLColors.zinc500,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Spacer(flex: 3),
                // Indicators + button row
                Row(
                  children: [
                    ...List.generate(steps.length, (i) {
                      final active = i == current;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 6),
                        width: active ? 20 : 8,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? (isDark ? Colors.white : YLColors.primary)
                              : (isDark ? YLColors.zinc700 : YLColors.zinc200),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                    const Spacer(),
                    FilledButton(
                      onPressed: onNext,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            isDark ? Colors.white : YLColors.primary,
                        foregroundColor:
                            isDark ? YLColors.primary : Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YLRadius.md),
                        ),
                      ),
                      child: Text(
                        current == steps.length - 1 ? s.onboardingDone : s.onboardingNext,
                        style:
                            YLText.label.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mobile layout ──────────────────────────────────────────────────────────

class _MobileOnboarding extends StatelessWidget {
  final List<_Step> steps;
  final PageController controller;
  final int current;
  final bool isDark;
  final S s;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _MobileOnboarding({
    required this.steps,
    required this.controller,
    required this.current,
    required this.isDark,
    required this.s,
    required this.onPageChanged,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final iconFg = isDark ? Colors.white : YLColors.primary;
    final iconBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
                    child: TextButton(
                      onPressed: onSkip,
                      child: Text(s.onboardingSkip,
                          style:
                              YLText.body.copyWith(color: YLColors.zinc400)),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: controller,
                    onPageChanged: onPageChanged,
                    itemCount: steps.length,
                    itemBuilder: (context, i) {
                      final step = steps[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color: iconBg,
                                borderRadius:
                                    BorderRadius.circular(YLRadius.xl),
                                border:
                                    Border.all(color: border, width: 0.5),
                              ),
                              child:
                                  Icon(step.icon, size: 36, color: iconFg),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              step.title,
                              style: YLText.titleLarge.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color:
                                    isDark ? Colors.white : YLColors.zinc900,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              step.desc,
                              style: YLText.body.copyWith(
                                color: YLColors.zinc500,
                                height: 1.5,
                                fontSize: 15,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(steps.length, (i) {
                      final active = i == current;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 24 : 8,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? (isDark ? Colors.white : YLColors.primary)
                              : (isDark
                                  ? YLColors.zinc700
                                  : YLColors.zinc200),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: onNext,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            isDark ? Colors.white : YLColors.primary,
                        foregroundColor:
                            isDark ? YLColors.primary : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YLRadius.lg),
                        ),
                      ),
                      child: Text(
                        current == steps.length - 1 ? s.onboardingDone : s.onboardingNext,
                        style:
                            YLText.label.copyWith(fontWeight: FontWeight.w600),
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
