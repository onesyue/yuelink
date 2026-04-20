import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../domain/emby/emby_info_entity.dart';
import '../../../modules/emby/emby_client.dart';
import '../../../modules/emby/emby_detail_page.dart';
import '../../../modules/emby/emby_media_page.dart';
import '../../../modules/emby/emby_providers.dart';
import '../../../modules/emby/emby_web_page.dart';
import '../../../core/providers/core_provider.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/telemetry.dart';
import '../../../theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../providers/emby_preview_provider.dart';

/// 悦视频推荐条 — 接入 Emby 真实数据。
///
/// 数据来源由 [source] 控制（默认 [EmbyPreviewSource.recent]）：
/// - [EmbyPreviewSource.recent]   — 最近新增
/// - [EmbyPreviewSource.featured] — 编辑推荐（IsFavorite；空时自动降级到最近新增）
///
/// 状态层级：
///   1. No permission  → 开通引导
///   2. Web-only access → "进入悦视频" 引导
///   3. Native access, loading → 灰色骨架占位
///   4. Native access, error   → 占位 + 可点击进入（graceful degradation）
///   5. Native access, empty   → 暂无内容提示
///   6. Native access, data    → 真实海报横向列表
class EmbyPreviewRow extends ConsumerWidget {
  final EmbyPreviewSource source;
  const EmbyPreviewRow({
    super.key,
    this.source = EmbyPreviewSource.recent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final embyAsync = ref.watch(embyProvider);
    final emby = embyAsync.value;
    final hasAccess = emby?.hasAccess == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──────────────────────────────────────────────
        Row(
          children: [
            Text(
              s.navEmby,
              style: YLText.label.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? YLColors.zinc200 : YLColors.zinc800,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _openLibrary(context, ref, s),
              child: Row(
                children: [
                  Text(
                    s.embyEnter,
                    style: YLText.caption.copyWith(color: YLColors.zinc400),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: YLColors.zinc400,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Content area ────────────────────────────────────────────────
        // Guard: embyProvider still resolving its initial value.
        // Without this, `emby == null` would briefly show the "no permission"
        // banner for users who already have Emby access — a noticeable flash.
        if (embyAsync.isLoading && emby == null)
          _AccessLoadingSkeleton(isDark: isDark)
        else if (!hasAccess)
          _NoPermissionBanner(onTap: () => _openLibrary(context, ref, s), isDark: isDark)
        else if (emby?.hasNativeAccess != true)
          _WebOnlyBanner(onTap: () => _openLibrary(context, ref, s), isDark: isDark)
        else if (ref.watch(coreStatusProvider) != CoreStatus.running)
          _VpnOffBanner(isDark: isDark)
        else
          _PosterRow(emby: emby!, isDark: isDark, onTapLibrary: () => _openLibrary(context, ref, s), source: source),
      ],
    );
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  /// Open the full Emby library (native or web).
  Future<void> _openLibrary(BuildContext context, WidgetRef ref, S s) async {
    if (ref.read(coreStatusProvider) != CoreStatus.running) {
      AppNotifier.warning(s.mineEmbyNeedsVpn);
      return;
    }
    var emby = ref.read(embyProvider).value;
    if (emby == null || !emby.hasAccess) {
      AppNotifier.info(s.mineEmbyOpening);
      ref.invalidate(embyProvider);
      emby = await ref.read(embyProvider.future);
      if (!context.mounted) return;
      if (emby == null || !emby.hasAccess) {
        AppNotifier.warning(s.mineEmbyNoAccess);
        return;
      }
    }
    if (!context.mounted) return;
    Telemetry.event(
      TelemetryEvents.embyOpen,
      props: {'mode': emby.hasNativeAccess ? 'native' : 'web'},
    );
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

// ── State widgets ─────────────────────────────────────────────────────────────

/// State 1: No Emby permission — upgrade prompt.
class _NoPermissionBanner extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;

  const _NoPermissionBanner({required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc800 : Colors.white,
          borderRadius: BorderRadius.circular(YLRadius.xl),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: YLShadow.card(context),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.play_circle_outline_rounded,
              size: 24,
              color: YLColors.zinc400,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                S.of(context).embyNoAccessHint,
                style: YLText.caption.copyWith(
                  color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: YLColors.zinc400,
            ),
          ],
        ),
      ),
    );
  }
}

/// State 2.5: Has Emby native access but VPN is not connected.
/// The Emby server (emby.yue.to) is SNI-blocked from China without VPN,
/// so showing "no content" would be misleading. Prompt user to connect.
class _VpnOffBanner extends StatelessWidget {
  final bool isDark;
  const _VpnOffBanner({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Row(
        children: [
          Icon(Icons.vpn_lock_rounded,
              size: 20, color: YLColors.currentAccent.withValues(alpha: 0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              S.of(context).mineEmbyNeedsVpn,
              style: YLText.caption.copyWith(color: YLColors.zinc500),
            ),
          ),
        ],
      ),
    );
  }
}

/// State 2: Has Emby access but only web-only (no native API credentials).
class _WebOnlyBanner extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;

  const _WebOnlyBanner({required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc800 : Colors.white,
          borderRadius: BorderRadius.circular(YLRadius.xl),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: YLShadow.card(context),
        ),
        child: Row(
          children: [
            const Icon(Icons.open_in_browser_rounded,
                size: 20, color: YLColors.zinc400),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                S.of(context).embyWebHint,
                style: YLText.caption.copyWith(color: YLColors.zinc500),
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 12, color: YLColors.zinc400),
          ],
        ),
      ),
    );
  }
}

/// State 3–6: Has native access. Watches [embyPreviewProvider] for real items.
class _PosterRow extends ConsumerWidget {
  final EmbyInfo emby;
  /// Which source to display. Defaults to [EmbyPreviewSource.recent].
  final EmbyPreviewSource source;
  final bool isDark;
  final VoidCallback onTapLibrary;

  const _PosterRow({
    required this.emby,
    required this.isDark,
    required this.onTapLibrary,
    this.source = EmbyPreviewSource.recent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewAsync = ref.watch(embyPreviewProvider(source));

    return previewAsync.when(
      // State 3: Loading
      loading: () => _buildSkeleton(isDark),
      // State 4: Error → graceful degradation (placeholder tiles, still tappable)
      error: (_, _) => _buildPlaceholderTiles(context, isDark, onTapLibrary),
      data: (items) {
        // State 5: Empty
        if (items.isEmpty) return _buildEmpty(context, isDark, onTapLibrary);
        // State 6: Real poster data
        return _buildPosters(context, items, isDark);
      },
    );
  }

  // ── State builders ──────────────────────────────────────────────────────

  /// Skeleton loading placeholders — same height as poster row.
  Widget _buildSkeleton(bool isDark) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 8,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, _) => _SkeletonPoster(isDark: isDark),
      ),
    );
  }

  /// Fallback placeholder tiles when API failed — same visual as old placeholder,
  /// still tappable to enter the full library page.
  Widget _buildPlaceholderTiles(
      BuildContext context, bool isDark, VoidCallback onTap) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, _) => GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(YLRadius.md),
            child: Container(
              width: 90,
              color: isDark ? YLColors.zinc700 : YLColors.zinc200,
              child: Center(
                child: Icon(
                  Icons.movie_outlined,
                  size: 28,
                  color: isDark ? YLColors.zinc500 : YLColors.zinc400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Empty state — no items returned by the server.
  Widget _buildEmpty(BuildContext context, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: YLEmptyState(
            icon: Icons.movie_outlined,
            title: S.of(context).embyNoContent,
            size: 72,
          ),
        ),
      ),
    );
  }

  /// Real poster tiles from the Emby API.
  Widget _buildPosters(
      BuildContext context, List<EmbyPreviewItem> items, bool isDark) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return _PosterTile(
            item: item,
            emby: emby,
            isDark: isDark,
            onTap: () => _openItem(context, item),
          );
        },
      ),
    );
  }

  /// Navigate to the item's detail page, managing the EmbyClient lifecycle
  /// via [_EmbyDetailRoute].
  void _openItem(BuildContext context, EmbyPreviewItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EmbyDetailRoute(
          serverUrl: emby.serverBaseUrl!,
          userId: emby.parsedUserId!,
          accessToken: emby.parsedAccessToken!,
          serverId: emby.parsedServerId ?? '',
          item: item,
        ),
      ),
    );
  }
}

// ── Poster tile ───────────────────────────────────────────────────────────────

class _PosterTile extends StatelessWidget {
  final EmbyPreviewItem item;
  final EmbyInfo emby;
  final bool isDark;
  final VoidCallback onTap;

  const _PosterTile({
    required this.item,
    required this.emby,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
    final physWidth = (90 * dpr).toInt();
    final serverUrl = emby.serverBaseUrl!;
    final token = emby.parsedAccessToken!;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(YLRadius.md),
        child: SizedBox(
          width: 90,
          height: 130,
          child: item.hasPoster
              ? CachedNetworkImage(
                  imageUrl:
                      '$serverUrl/emby/Items/${item.id}/Images/Primary'
                      '?fillWidth=$physWidth&quality=90&api_key=$token',
                  cacheManager: EmbyClient.imageCacheManager,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 200),
                  memCacheWidth: physWidth.clamp(0, 480),
                  memCacheHeight: (physWidth * 3 ~/ 2).clamp(0, 720),
                  placeholder: (_, _) => Container(
                    color: isDark
                        ? const Color(0xFF1C1C1E)
                        : const Color(0xFFE4E4E7),
                  ),
                  errorWidget: (_, _, _) =>
                      _PosterFallback(isDark: isDark),
                )
              : _PosterFallback(isDark: isDark),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  final bool isDark;
  const _PosterFallback({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? YLColors.zinc700 : YLColors.zinc200,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 28,
          color: isDark ? YLColors.zinc500 : YLColors.zinc400,
        ),
      ),
    );
  }
}

class _SkeletonPoster extends StatelessWidget {
  final bool isDark;
  const _SkeletonPoster({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(YLRadius.md),
      child: Container(
        width: 90,
        height: 130,
        color: isDark ? YLColors.zinc700 : YLColors.zinc200,
      ),
    );
  }
}

/// Skeleton row shown while [embyProvider] is resolving its initial value.
///
/// Prevents the "no permission" banner from flashing for users who already
/// have Emby access but whose credentials haven't been fetched yet.
class _AccessLoadingSkeleton extends StatelessWidget {
  final bool isDark;
  const _AccessLoadingSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, _) => ClipRRect(
          borderRadius: BorderRadius.circular(YLRadius.md),
          child: Container(
            width: 90,
            height: 130,
            color: isDark ? YLColors.zinc700 : YLColors.zinc200,
          ),
        ),
      ),
    );
  }
}

// ── Navigation wrapper ────────────────────────────────────────────────────────

/// Thin StatefulWidget that owns the EmbyClient lifecycle for the detail page.
///
/// EmbyDetailPage requires a pre-built [EmbyClient] from its caller.
/// This wrapper creates it in [initState] and disposes in [dispose],
/// so the detail page does not need to manage the client itself.
class _EmbyDetailRoute extends StatefulWidget {
  final String serverUrl;
  final String userId;
  final String accessToken;
  final String serverId;
  final EmbyPreviewItem item;

  const _EmbyDetailRoute({
    required this.serverUrl,
    required this.userId,
    required this.accessToken,
    required this.serverId,
    required this.item,
  });

  @override
  State<_EmbyDetailRoute> createState() => _EmbyDetailRouteState();
}

class _EmbyDetailRouteState extends State<_EmbyDetailRoute> {
  late final EmbyClient _api;

  @override
  void initState() {
    super.initState();
    _api = EmbyClient(
      serverUrl: widget.serverUrl,
      accessToken: widget.accessToken,
      userId: widget.userId,
    );
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EmbyDetailPage(
      api: _api,
      serverUrl: widget.serverUrl,
      userId: widget.userId,
      accessToken: widget.accessToken,
      serverId: widget.serverId,
      itemId: widget.item.id,
      itemName: widget.item.name,
      itemType: widget.item.type,
      hasPoster: widget.item.hasPoster,
    );
  }
}
