import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/home/home_repository.dart';
import '../yue_auth/providers/yue_auth_providers.dart';
import '../nodes/scene_mode/scene_mode.dart';
import 'widgets/hero_banner_model.dart';

// ── Emby preview config ───────────────────────────────────────────────────────

/// Which content set to show in the dashboard Emby preview row.
enum EmbyPreviewSource {
  /// Most recently added items — default query on the Emby server.
  recent,

  /// Server-curated featured items.
  /// Requires a "featured" playlist / collection configured on the Emby server.
  featured,
}

/// Configuration for the dashboard Emby preview row.
///
/// **v1:** Returned via [HomeContent.local] with defaults.
/// **v2:** Passed from server config; wire into [emby_preview_provider.dart]
/// to alter the Emby Items query parameters.
class EmbyPreviewConfig {
  /// Content source — controls which items the preview row fetches.
  final EmbyPreviewSource source;

  /// Maximum poster count shown in the row (server caps at 10 in v1).
  final int maxItems;

  const EmbyPreviewConfig({
    this.source = EmbyPreviewSource.recent,
    this.maxItems = 10,
  });

  factory EmbyPreviewConfig.fromJson(Map<String, dynamic> json) =>
      EmbyPreviewConfig(
        source: EmbyPreviewSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => EmbyPreviewSource.recent,
        ),
        maxItems: json['maxItems'] as int? ?? 10,
      );
}

// ── Quick actions config ──────────────────────────────────────────────────────

/// Visibility toggles for each quick-action tile on the dashboard.
///
/// **v1:** All tiles visible (defaults). Not yet wired to [quick_actions.dart].
/// **v2 wiring:** In [quick_actions.dart], read [quickActionsConfigProvider]
/// and conditionally render each tile:
/// ```dart
/// final cfg = ref.watch(quickActionsConfigProvider);
/// if (cfg.showSmartSelect) _ActionTile(label: '智能选线', ...),
/// ```
class QuickActionsConfig {
  final bool showSmartSelect;
  final bool showSceneMode;
  final bool showSpeedTest;

  const QuickActionsConfig({
    this.showSmartSelect = true,
    this.showSceneMode = true,
    this.showSpeedTest = true,
  });

  factory QuickActionsConfig.fromJson(Map<String, dynamic> json) =>
      QuickActionsConfig(
        showSmartSelect: json['showSmartSelect'] as bool? ?? true,
        showSceneMode: json['showSceneMode'] as bool? ?? true,
        showSpeedTest: json['showSpeedTest'] as bool? ?? true,
      );
}

// ── Unified home content model ────────────────────────────────────────────────

/// All server-configurable content shown on the dashboard home screen.
///
/// **v1:** Constructed from [HomeContent.local] — compile-time constants, zero
/// network calls.
///
/// **v2 JSON shape** (from `GET /api/v1/client/home`):
/// ```json
/// {
///   "banners": [ { "id": "...", "title": "...", ... } ],
///   "quickActions": {
///     "showSmartSelect": true,
///     "showSceneMode": true,
///     "showSpeedTest": false
///   },
///   "embyPreview": {
///     "source": "featured",
///     "maxItems": 8
///   }
/// }
/// ```
class HomeContent {
  final List<HeroBannerItem> banners;
  final QuickActionsConfig quickActions;
  final EmbyPreviewConfig embyPreview;

  /// Whether the service-status summary bar is visible on the dashboard.
  ///
  /// **v1:** `true` (always shown).
  /// **v2:** Server can set `false` to hide it (e.g. for trial accounts or
  /// regions where the bar is not meaningful).
  final bool showServiceStatusBar;

  /// 远程场景模式覆盖配置。null = 使用本地预设。
  final Map<String, dynamic>? sceneModes;

  const HomeContent({
    required this.banners,
    this.quickActions = const QuickActionsConfig(),
    this.embyPreview = const EmbyPreviewConfig(),
    this.showServiceStatusBar = true,
    this.sceneModes,
  });

  /// Local static config used in v1 and as a fallback in v2.
  factory HomeContent.local() => HomeContent(
        banners: kLocalHeroBanners,
      );

  /// Deserialize from the XBoard `/api/v1/client/home` JSON response.
  ///
  /// Falls back to [kLocalHeroBanners] when the server returns an empty list.
  factory HomeContent.fromJson(Map<String, dynamic> json) {
    final rawBanners = json['banners'] as List<dynamic>? ?? [];
    final banners = rawBanners
        .whereType<Map<String, dynamic>>()
        .map(HeroBannerItem.fromJson)
        .toList();

    return HomeContent(
      banners: banners.isNotEmpty ? banners : kLocalHeroBanners,
      quickActions: json['quickActions'] is Map<String, dynamic>
          ? QuickActionsConfig.fromJson(
              json['quickActions'] as Map<String, dynamic>)
          : const QuickActionsConfig(),
      embyPreview: json['embyPreview'] is Map<String, dynamic>
          ? EmbyPreviewConfig.fromJson(
              json['embyPreview'] as Map<String, dynamic>)
          : const EmbyPreviewConfig(),
      showServiceStatusBar: json['showServiceStatusBar'] as bool? ?? true,
      sceneModes: json['sceneModes'] as Map<String, dynamic>?,
    );
  }
}

// ── Root provider ─────────────────────────────────────────────────────────────

/// Unified home-content config provider.
///
/// **v1 (current):** Returns [HomeContent.local()] immediately — zero network
/// calls, resolves synchronously, never shows a loading state in practice.
///
/// **v2 migration (XBoard home API):** Replace the body with:
/// ```dart
/// final homeContentProvider = FutureProvider<HomeContent>((ref) async {
///   final token = ref.watch(authProvider).token;
///   if (token == null) return HomeContent.local();
///   try {
///     final api = ref.watch(xboardApiProvider);
///     final json = await api.getHomeContent(token)
///         .timeout(const Duration(seconds: 5));
///     return HomeContent.fromJson(json);
///   } catch (_) {
///     return HomeContent.local(); // graceful fallback on error
///   }
/// });
/// ```
///
/// Derived providers ([heroBannerConfigProvider], [quickActionsConfigProvider],
/// [embyPreviewConfigProvider]) fall back to local config while loading/error,
/// so **no widget changes** are required when migrating to v2.
final homeContentProvider = FutureProvider<HomeContent>((ref) async {
  try {
    final proxyPort = ref.watch(businessProxyPortProvider);
    final json = await HomeRepository(proxyPort: proxyPort).fetchHomeConfig();
    if (json != null) return HomeContent.fromJson(json);
  } catch (e) {
    // Non-fatal: widget layer falls back to local defaults. Log so the cause
    // (network / JSON shape / parse) is visible in diagnostics instead of
    // silently degrading to the local banner set.
    debugPrint('[HomeContent] remote fetch failed, using local defaults: $e');
  }
  return HomeContent.local();
});

// ── Derived sync providers ────────────────────────────────────────────────────
// All three are sync Providers that unwrap the AsyncValue from homeContentProvider
// and fall back to local defaults. Widgets read these, never homeContentProvider
// directly — this insulates the widget layer from the async/sync distinction.

/// Banner slides for the homepage carousel.
///
/// Falls back to [kLocalHeroBanners] during [homeContentProvider] load/error,
/// so the carousel is never empty on cold start.
final heroBannerConfigProvider = Provider<List<HeroBannerItem>>((ref) {
  return ref.watch(homeContentProvider).value?.banners ??
      kLocalHeroBanners;
});

/// Visibility flags for each quick-action tile.
///
/// **v1:** All tiles visible (defaults). Not yet wired — see [QuickActionsConfig].
final quickActionsConfigProvider = Provider<QuickActionsConfig>((ref) {
  return ref.watch(homeContentProvider).value?.quickActions ??
      const QuickActionsConfig();
});

/// Source and item-count config for the Emby preview row.
///
/// **v1:** Defaults to [EmbyPreviewSource.recent] / 10 items.
/// **v2 wiring:** Pass [EmbyPreviewConfig.source] and [EmbyPreviewConfig.maxItems]
/// into the Emby Items query inside [emby_preview_provider.dart].
final embyPreviewConfigProvider = Provider<EmbyPreviewConfig>((ref) {
  return ref.watch(homeContentProvider).value?.embyPreview ??
      const EmbyPreviewConfig();
});

/// Whether the service-status summary bar should be rendered on the dashboard.
///
/// Falls back to `true` (default-on) while [homeContentProvider] is loading
/// or in error — the bar should remain visible unless the server explicitly
/// sets `showServiceStatusBar: false`.
final serviceStatusBarVisibleProvider = Provider<bool>((ref) {
  return ref.watch(homeContentProvider).value?.showServiceStatusBar ??
      true;
});

/// 场景模式有效配置（本地预设 + 远程覆盖合并）。
final sceneModeConfigsProvider =
    Provider<Map<SceneMode, SceneModeConfig>>((ref) {
  final remote = ref.watch(homeContentProvider).value?.sceneModes;
  if (remote == null) return kSceneModeDefaults;

  // 合并：对每个 mode，如果远程有覆盖就 merge，否则用本地默认
  final merged = <SceneMode, SceneModeConfig>{};
  for (final mode in SceneMode.values) {
    final base = kSceneModeDefaults[mode]!;
    final remoteJson = remote[mode.name];
    if (remoteJson is Map<String, dynamic>) {
      merged[mode] = SceneModeConfig.fromRemote(base: base, json: remoteJson);
    } else {
      merged[mode] = base;
    }
  }
  return merged;
});
