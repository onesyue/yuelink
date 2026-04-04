import 'package:flutter/material.dart';

// ── Action types ──────────────────────────────────────────────────────────────

/// Supported action types for a [HeroBannerItem] tap.
///
/// v2 extension: add [external] / [deepLink] as needed when remote config
/// provides richer action payloads.
enum BannerActionType {
  /// Open the Emby / 悦视频 native player (or web fallback).
  openEmby,

  /// Navigate to the in-app store / plan selection page.
  openStore,

  /// Open the announcements list page.
  openAnnouncement,

  /// Launch an external URL via the system browser.
  /// [HeroBannerItem.actionTarget] must be a valid HTTPS URL.
  openUrl,

  /// Open an external URL via the system browser (alias for richer payloads).
  external,

  /// App-internal deep link. [HeroBannerItem.actionTarget] is a route path.
  deepLink,

  /// Open the native feedback page.
  openFeedback,
}

// ── Model ─────────────────────────────────────────────────────────────────────

/// One slide in the hero banner carousel.
///
/// v1: built locally from [kLocalHeroBanners].
/// v2: deserialize from XBoard `GET /api/v1/client/home` → `.banners[]`.
class HeroBannerItem {
  /// Stable identifier used as a PageView key and for dedup.
  final String id;

  final String title;
  final String subtitle;

  /// Optional remote image URL. When null, the [iconEmoji] + gradient is shown.
  final String? imageUrl;

  /// Gradient left / top colour (dark side).
  final Color gradientStart;

  /// Gradient right / bottom colour (light side).
  final Color gradientEnd;

  /// Emoji displayed as a large decorative element when [imageUrl] is absent.
  final String? iconEmoji;

  final BannerActionType actionType;

  /// Context-specific target:
  ///   openEmby        — ignored
  ///   openStore       — ignored
  ///   openAnnouncement— announcement slug / ID (ignored in v1, opens list)
  ///   openUrl         — HTTPS URL string
  final String? actionTarget;

  const HeroBannerItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    required this.gradientStart,
    required this.gradientEnd,
    this.iconEmoji,
    required this.actionType,
    this.actionTarget,
  });

  // ── v2 extension point ──────────────────────────────────────────────────

  /// Deserialize from the XBoard home-config API JSON payload.
  ///
  /// Expected JSON shape:
  /// ```json
  /// {
  ///   "id": "emby_promo",
  ///   "title": "悦视频",
  ///   "subtitle": "4K 精选内容",
  ///   "imageUrl": "https://cdn.example.com/banner.jpg",
  ///   "gradientStart": "#0f2027",
  ///   "gradientEnd": "#203a43",
  ///   "iconEmoji": "🎬",
  ///   "actionType": "openEmby",
  ///   "actionTarget": null
  /// }
  /// ```
  factory HeroBannerItem.fromJson(Map<String, dynamic> json) {
    Color parseHex(String? hex, Color fallback) {
      if (hex == null || hex.isEmpty) return fallback;
      final s = hex.replaceFirst('#', '');
      final value = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
      return value != null ? Color(value) : fallback;
    }

    return HeroBannerItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      gradientStart:
          parseHex(json['gradientStart'] as String?, const Color(0xFF1a1a2e)),
      gradientEnd:
          parseHex(json['gradientEnd'] as String?, const Color(0xFF16213e)),
      iconEmoji: json['iconEmoji'] as String?,
      actionType: BannerActionType.values.firstWhere(
        (t) => t.name == json['actionType'],
        orElse: () => BannerActionType.openStore,
      ),
      actionTarget: json['actionTarget'] as String?,
    );
  }
}

// ── Static editorial content ──────────────────────────────────────────────────

/// Default banner slides used in v1.
///
/// Moved here from [hero_banner_provider.dart] so that [home_content_provider.dart]
/// can reference them without a circular import. The provider file now delegates
/// to [heroBannerConfigProvider] from the unified config layer.
///
/// Order matters: first item is shown on cold start.
/// Keep to ≤ 4 items to avoid carousel fatigue.
const kLocalHeroBanners = [
  HeroBannerItem(
    id: 'emby_promo',
    title: '悦视频',
    subtitle: '4K 精选电影 · 日剧 · 动漫，随时随地畅看',
    gradientStart: Color(0xFF0f2027),
    gradientEnd: Color(0xFF2c5364),
    iconEmoji: '🎬',
    actionType: BannerActionType.openEmby,
  ),
  HeroBannerItem(
    id: 'ai_mode',
    title: 'AI 加速模式',
    subtitle: '专线直连 ChatGPT / Gemini，低延迟稳定访问',
    gradientStart: Color(0xFF1a1a2e),
    gradientEnd: Color(0xFF533483),
    iconEmoji: '🤖',
    actionType: BannerActionType.openAnnouncement,
  ),
  HeroBannerItem(
    id: 'upgrade',
    title: '解锁更多权益',
    subtitle: '升级套餐，享受更多节点 · 更高流量 · 更快速度',
    gradientStart: Color(0xFF1f4037),
    gradientEnd: Color(0xFF2a6049),
    iconEmoji: '⚡',
    actionType: BannerActionType.openStore,
  ),
];
