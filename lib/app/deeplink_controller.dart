import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'deeplink_provider.dart';

/// Listens for `clash://install-config?url=...` and
/// `mihomo://install-config?url=...` deep links and routes them into
/// [deepLinkUrlProvider] so the profile page can pre-fill its add
/// dialog. Foregrounds the desktop window when a link arrives while
/// the app is hidden in the system tray.
///
/// Was inlined in `_YueLinkAppState` (lib/main.dart) as
/// `_initDeepLinks` + `_handleDeepLink` + the `_appLinks` /
/// `_appLinksSub` fields. Pulling them out keeps main.dart focused on
/// widget concerns and lets the deep-link plumbing be reused by
/// future surfaces (in-app webview opening a custom URL, share sheet,
/// etc.) without duplicating the parser.
///
/// Wiring (from main.dart):
///   1. `init(deepLinkUrlProvider: ...)` once after first frame.
///   2. `dispose()` from the widget's dispose.
class DeeplinkController {
  DeeplinkController({required this.ref, required this.deepLinkUrlProvider});

  final WidgetRef ref;

  /// Riverpod state provider whose write triggers the profile page to
  /// open its add-subscription dialog with the URL pre-filled. Passed
  /// in rather than imported so the controller stays decoupled from
  /// main.dart's top-level provider declaration.
  final NotifierProvider<DeepLinkUrlNotifier, String?> deepLinkUrlProvider;

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool Function() _mounted = () => true;

  /// Wire up the listener and drain any pending cold-start link.
  /// `mounted` is evaluated at dispatch time so the controller can
  /// short-circuit when the host widget is gone.
  void init({required bool Function() mounted}) {
    _mounted = mounted;
    // Handle links that launched the app cold
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handle(uri);
    });
    // Handle links while app is already running — stored as a field so
    // dispose() cancels it.
    _sub = _appLinks.uriLinkStream.listen(_handle);
  }

  /// Cancel the link stream subscription. Idempotent.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Parse `clash://install-config?url=...` /
  /// `mihomo://install-config?url=...`. Empty URL or unmounted host →
  /// silent no-op.
  void _handle(Uri uri) {
    if (!_mounted()) return;
    final rawUrl = uri.queryParameters['url'];
    if (rawUrl == null || rawUrl.isEmpty) return;
    // Notify the profile page to pre-fill the add dialog
    ref.read(deepLinkUrlProvider.notifier).setUrl(rawUrl);
    // If window is hidden (desktop), bring it to front
    if (Platform.isMacOS || Platform.isWindows) {
      windowManager.show();
      windowManager.focus();
    }
  }
}
