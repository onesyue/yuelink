import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/account/account_overview.dart';
import '../../../domain/account/notice.dart';
import '../../../domain/announcements/announcement_entity.dart';
import '../../../infrastructure/account/account_repository.dart';
import '../../announcements/providers/announcements_providers.dart';
import '../../yue_auth/providers/yue_auth_providers.dart';

// ── DI ───────────────────────────────────────────────────────────────────────

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final proxyPort = ref.watch(businessProxyPortProvider);
  return AccountRepository(proxyPort: proxyPort);
});

// ── Providers ─────────────────────────────────────────────────────────────────

/// 账户总览数据（需要 token，用户未登录时返回 null）。
///
/// The sidecar overview endpoint is useful for richer fields (renewal URL,
/// last-online freshness), but it must not be the only source of truth for
/// the "我的" card. XBoard subscribe data is already cached in auth state and
/// contains the core identity/plan/traffic fields, so we render that snapshot
/// immediately and refresh the richer overview in the background.
final accountOverviewProvider =
    AsyncNotifierProvider<AccountOverviewNotifier, AccountOverview?>(
      AccountOverviewNotifier.new,
    );

class AccountOverviewNotifier extends AsyncNotifier<AccountOverview?> {
  @override
  FutureOr<AccountOverview?> build() {
    final token = ref.watch(authProvider.select((s) => s.token));
    final profile = ref.watch(authProvider.select((s) => s.userProfile));
    if (token == null) return null;

    final fallback = accountOverviewFromProfile(profile);
    if (fallback != null) {
      unawaited(_refreshInBackground(token, fallback));
      return fallback;
    }
    return _fetchOverview(token, fallback: null);
  }

  Future<void> refresh() async {
    final auth = ref.read(authProvider);
    final token = auth.token;
    if (token == null) {
      state = const AsyncData(null);
      return;
    }

    final current = state.when<AccountOverview?>(
      data: (value) => value,
      loading: () => null,
      error: (_, _) => null,
    );
    final fallback = current ?? accountOverviewFromProfile(auth.userProfile);
    state = fallback == null ? const AsyncLoading() : AsyncData(fallback);

    final next = await _fetchOverview(token, fallback: fallback);
    if (!ref.mounted || !_isCurrentToken(token)) return;
    state = AsyncData(next);
  }

  Future<void> _refreshInBackground(
    String token,
    AccountOverview fallback,
  ) async {
    final next = await _fetchOverview(token, fallback: fallback);
    if (!ref.mounted || !_isCurrentToken(token)) return;
    state = AsyncData(next);
  }

  Future<AccountOverview?> _fetchOverview(
    String token, {
    required AccountOverview? fallback,
  }) async {
    try {
      final repo = ref.read(accountRepositoryProvider);
      final fresh = await repo.getAccountOverview(token);
      return fresh ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  bool _isCurrentToken(String token) {
    return ref.read(authProvider.select((s) => s.token)) == token;
  }
}

AccountOverview? accountOverviewFromProfile(UserProfile? profile) {
  if (profile == null) return null;
  final used = (profile.uploadUsed ?? 0) + (profile.downloadUsed ?? 0);
  final total = profile.transferEnable ?? 0;
  final remaining = profile.remaining ?? (total - used).clamp(0, total);
  final planName = profile.planName?.trim();
  return AccountOverview(
    email: profile.email ?? '—',
    planName: planName == null || planName.isEmpty ? '无套餐' : planName,
    transferUsedBytes: used,
    transferTotalBytes: total,
    transferRemainingBytes: remaining,
    expireAt: profile.expiryDate,
    daysRemaining: profile.daysRemaining,
    renewalUrl: 'https://yuetong.app/#/plan',
    onlineCount: profile.onlineCount,
    deviceLimit: profile.deviceLimit,
  );
}

/// 用户通知列表（需要 token，未登录时返回空列表）。
final accountNoticesProvider = FutureProvider<List<AccountNotice>>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];
  final repo = ref.read(accountRepositoryProvider);
  return repo.getNotices(token);
});

/// Dashboard notices prefer the dedicated account notices endpoint, but
/// gracefully fall back to XBoard announcements when that sidecar service is
/// empty or temporarily unavailable.
final dashboardNoticesProvider = FutureProvider<List<AccountNotice>>((
  ref,
) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];

  final notices = await ref.watch(accountNoticesProvider.future);
  if (notices.isNotEmpty) return notices;

  final repo = ref.read(announcementsRepositoryProvider);
  try {
    final announcements = await repo.getAnnouncements(token);
    return announcements.map(_mapAnnouncementToNotice).toList();
  } on XBoardApiException catch (e) {
    if (e.statusCode == 401 || e.statusCode == 403) {
      await ref.read(authProvider.notifier).handleUnauthenticated();
    }
    return [];
  } catch (_) {
    return [];
  }
});

AccountNotice _mapAnnouncementToNotice(Announcement announcement) {
  return AccountNotice(
    title: announcement.title,
    content: announcement.content,
    createdAt: announcement.createdDate?.toIso8601String(),
  );
}
