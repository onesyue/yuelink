import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../i18n/app_strings.dart';
import '../../../modules/announcements/presentation/announcements_page.dart';
import '../../../modules/emby/emby_media_page.dart';
import '../../../modules/emby/emby_providers.dart';
import '../../../modules/emby/emby_web_page.dart';
import '../../../modules/mine/views/feedback_page.dart';
import '../../../modules/store/store_page.dart';
import '../../../core/providers/core_provider.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';
import 'hero_banner_model.dart';
import 'hero_banner_provider.dart';

// ── Hero Banner ───────────────────────────────────────────────────────────────

/// 首页运营 Hero Banner —— 多页轮播 + 自动推进 + 动作路由。
///
/// 数据来源：[heroBannerItemsProvider]（v1 本地静态，v2 接 XBoard home API）。
/// UI 不感知数据来源：当 provider 切换为 FutureProvider 时，loading/error
/// 状态由内部 [AsyncValue] 处理，无需改动此 widget。
class HeroBanner extends ConsumerStatefulWidget {
  const HeroBanner({super.key});

  @override
  ConsumerState<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends ConsumerState<HeroBanner> {
  /// Large multiplier so user can swipe left/right freely (infinite loop feel).
  static const _kMultiplier = 1000;
  late final PageController _pageController;
  int _realPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Start in the middle so user can swipe both directions.
    final items = ref.read(heroBannerItemsProvider);
    final initialPage = items.isEmpty ? 0 : _kMultiplier ~/ 2 * items.length;
    _pageController = PageController(initialPage: initialPage);
    _startAutoAdvance();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoAdvance() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _advance());
  }

  void _advance() {
    if (!mounted) return;
    final items = ref.read(heroBannerItemsProvider);
    if (items.length <= 1) return;
    final nextPage = (_pageController.page?.round() ?? 0) + 1;
    _pageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // v1: Provider<List<HeroBannerItem>> — synchronous, always data.
    // v2: when switching to FutureProvider, wrap with AsyncValue handling here.
    final items = ref.watch(heroBannerItemsProvider);
    if (items.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Slide area ────────────────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(YLRadius.xl),
          child: SizedBox(
            height: 110,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification && n.dragDetails != null) {
                  _startAutoAdvance(); // reset timer on manual swipe
                }
                return false;
              },
              child: PageView.builder(
                controller: _pageController,
                itemCount: items.length <= 1 ? items.length : items.length * _kMultiplier,
                onPageChanged: (i) => setState(() => _realPage = i % items.length),
                itemBuilder: (context, index) {
                  final i = index % items.length;
                  return _BannerSlide(
                    item: items[i],
                    onTap: () => _handleAction(items[i]),
                  );
                },
              ),
            ),
          ),
        ),

        // ── Dot indicators (only when >1 item) ───────────────────────
        if (items.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(items.length, (i) {
              final active = i == _realPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: active ? 16 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: active
                      ? (isDark ? Colors.white70 : YLColors.zinc700)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.25)
                          : Colors.black.withValues(alpha: 0.15)),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  // ── Action routing ────────────────────────────────────────────────────────

  Future<void> _handleAction(HeroBannerItem item) async {
    final s = S.of(context);
    switch (item.actionType) {
      case BannerActionType.openEmby:
        await _openEmby(s);
      case BannerActionType.openStore:
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StorePage()),
        );
      case BannerActionType.openAnnouncement:
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AnnouncementsPage()),
        );
      case BannerActionType.openUrl:
      case BannerActionType.external:
        final target = item.actionTarget;
        if (target == null || target.isEmpty) return;
        final uri = Uri.tryParse(target);
        if (uri != null && uri.scheme.startsWith('http')) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      case BannerActionType.deepLink:
        // App 内部路由跳转（预留，当前无 deep link 路由表）
        break;
      case BannerActionType.openFeedback:
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FeedbackPage()),
        );
    }
  }

  Future<void> _openEmby(S s) async {
    if (ref.read(coreStatusProvider) != CoreStatus.running) {
      AppNotifier.warning(s.mineEmbyNeedsVpn);
      return;
    }
    var emby = ref.read(embyProvider).valueOrNull;
    if (emby == null || !emby.hasAccess) {
      AppNotifier.info(s.mineEmbyOpening);
      ref.invalidate(embyProvider);
      emby = await ref.read(embyProvider.future);
      if (!mounted) return;
      if (emby == null || !emby.hasAccess) {
        AppNotifier.warning(s.mineEmbyNoAccess);
        return;
      }
    }
    if (!mounted) return;
    if (emby.hasNativeAccess) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EmbyMediaPage(
            serverUrl: emby!.serverBaseUrl!,
            userId: emby.parsedUserId!,
            accessToken: emby.parsedAccessToken!,
            serverId: emby.parsedServerId ?? '',
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EmbyWebPage(url: emby!.launchUrl!),
        ),
      );
    }
  }
}

// ── Slide widget ──────────────────────────────────────────────────────────────

class _BannerSlide extends StatelessWidget {
  final HeroBannerItem item;
  final VoidCallback onTap;

  const _BannerSlide({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [item.gradientStart, item.gradientEnd],
          ),
        ),
        child: Stack(
          children: [
            // Optional background image
            if (item.imageUrl != null)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final dpr = MediaQuery.of(ctx).devicePixelRatio.clamp(1.0, 3.0);
                    final w = (constraints.maxWidth * dpr).toInt().clamp(0, 1920);
                    final h = (w * 9 / 16).toInt();
                    return Image.network(
                      item.imageUrl!,
                      fit: BoxFit.cover,
                      cacheWidth: w,
                      cacheHeight: h,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    );
                  },
                ),
              ),

            // Semi-transparent overlay to ensure text legibility on images
            if (item.imageUrl != null)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Row(
                children: [
                  // Emoji / icon area
                  if (item.iconEmoji != null) ...[
                    Text(
                      item.iconEmoji!,
                      style: const TextStyle(fontSize: 36),
                    ),
                    const SizedBox(width: 16),
                  ],

                  // Text area
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.80),
                            fontSize: 12,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Chevron affordance
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
