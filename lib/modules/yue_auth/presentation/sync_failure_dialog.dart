import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../store/store_page.dart';
import '../providers/yue_auth_providers.dart';

/// Show a full-context dialog when `syncSubscription()` fails.
///
/// Two failure axes the user actually cares about:
///
///   1. **Account-side** — 401 / 403 / "subscription expired".
///      Action: open Store so the user can renew or check their plan.
///   2. **Network-side** — timeout / 5xx / TLS / socket.
///      Action: retry the sync from the same surface they triggered it.
///
/// `onRetry` is the same callback the trigger surface used (e.g. the
/// stale-subscription banner's `_refresh()`); it's invoked from the
/// dialog's "重试" button so callers don't have to pop+re-trigger
/// themselves.
Future<void> showSubscriptionSyncFailureDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Object error,
  Future<void> Function()? onRetry,
}) async {
  final s = S.of(context);
  final isEn = s.isEn;
  final isAccountIssue = _looksLikeAccountIssue(error);
  final friendly = _friendly(error, isEn: isEn);

  final action = await showDialog<_SyncFailureAction>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        isAccountIssue
            ? (isEn ? 'Subscription Issue' : '订阅出现问题')
            : (isEn ? 'Sync Failed' : '同步失败'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isAccountIssue
                ? (isEn
                    ? 'Your YueLink subscription couldn\'t be loaded. '
                        'Open the store to check your plan or renew.'
                    : '无法加载你的悦通订阅。可以打开商店查看套餐或续期。')
                : (isEn
                    ? 'Couldn\'t reach the subscription server. Check '
                        'your network and try again.'
                    : '无法连接订阅服务器。请检查网络后重试。'),
            style: const TextStyle(height: 1.4),
          ),
          if (friendly.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              friendly,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, _SyncFailureAction.cancel),
          child: Text(s.cancel),
        ),
        if (isAccountIssue)
          TextButton(
            onPressed: () => Navigator.pop(ctx, _SyncFailureAction.store),
            child: Text(isEn ? 'Open Store' : '打开商店'),
          ),
        if (onRetry != null)
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _SyncFailureAction.retry),
            child: Text(isEn ? 'Retry' : '重试'),
          ),
      ],
    ),
  );

  if (!context.mounted) return;
  switch (action) {
    case _SyncFailureAction.retry:
      if (onRetry != null) {
        try {
          await onRetry();
        } catch (e) {
          // Re-show the dialog if the retry also failed. Keeps the
          // failure visible without recursing forever — second click
          // on Retry just sees the new error in the same dialog.
          if (!context.mounted) return;
          await showSubscriptionSyncFailureDialog(
            context: context,
            ref: ref,
            error: e,
            onRetry: onRetry,
          );
        }
      }
    case _SyncFailureAction.store:
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const StorePage()),
      );
    case _SyncFailureAction.cancel:
    case null:
      // Honour the user's dismiss. The toast is intentionally suppressed
      // here — the dialog itself was the surface; chaining a toast on
      // dismiss is double-noise.
      break;
  }
}

enum _SyncFailureAction { retry, store, cancel }

bool _looksLikeAccountIssue(Object error) {
  if (error is XBoardApiException) {
    return error.statusCode == 401 ||
        error.statusCode == 403 ||
        error.statusCode == 404;
  }
  return false;
}

String _friendly(Object error, {required bool isEn}) {
  final raw = error.toString();
  if (error is XBoardApiException) {
    return isEn
        ? 'Server response: HTTP ${error.statusCode}'
        : '服务器响应：HTTP ${error.statusCode}';
  }
  // Strip the leading "Exception: " noise that Dart prepends.
  if (raw.startsWith('Exception: ')) return raw.substring(11);
  // Bound the error string so the dialog doesn't blow out vertically
  // on a wall-of-text TLS handshake message.
  return raw.length > 200 ? '${raw.substring(0, 200)}…' : raw;
}

/// Convenience for callers that already use `await syncSubscription()`
/// — wraps the call and routes the failure into [showSubscriptionSyncFailureDialog].
/// On success it returns silently. The optional `notifySuccess` toast
/// keeps user-initiated refreshes from feeling silent on the happy path.
Future<bool> syncSubscriptionWithFailureDialog({
  required BuildContext context,
  required WidgetRef ref,
  bool notifySuccess = false,
}) async {
  try {
    await ref.read(authProvider.notifier).syncSubscription();
    if (notifySuccess && context.mounted) {
      AppNotifier.success(S.of(context).syncComplete);
    }
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    await showSubscriptionSyncFailureDialog(
      context: context,
      ref: ref,
      error: e,
      onRetry: () =>
          ref.read(authProvider.notifier).syncSubscription(),
    );
    return false;
  }
}
