import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/account/account_overview.dart';
import '../../../domain/account/notice.dart';
import '../../../infrastructure/account/account_repository.dart';
import '../../yue_auth/providers/yue_auth_providers.dart';

// ── DI ───────────────────────────────────────────────────────────────────────

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository();
});

// ── Providers ─────────────────────────────────────────────────────────────────

/// 账户总览数据（需要 token，用户未登录时返回 null）。
final accountOverviewProvider = FutureProvider<AccountOverview?>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return null;
  final repo = ref.read(accountRepositoryProvider);
  return repo.getAccountOverview(token);
});

/// 用户通知列表（需要 token，未登录时返回空列表）。
final accountNoticesProvider = FutureProvider<List<AccountNotice>>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];
  final repo = ref.read(accountRepositoryProvider);
  return repo.getNotices(token);
});
