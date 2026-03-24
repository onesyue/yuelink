import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../l10n/app_strings.dart';
import '../../theme.dart';

/// In-app Emby browser — no external app required on any platform.
///
/// - Android / iOS / macOS : [webview_flutter] (WKWebView / Android WebView)
///   iOS/macOS use [WebKitWebViewControllerCreationParams] so video plays
///   inline without requiring a user gesture.
/// - Windows               : [webview_windows] (WebView2 / Chromium Edge)
class EmbyWebPage extends StatelessWidget {
  final String url;
  const EmbyWebPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      return _WindowsEmbyView(url: url);
    }
    return _FlutterEmbyView(url: url);
  }
}

// ── webview_flutter implementation (Android / iOS / macOS) ───────────────────

class _FlutterEmbyView extends StatefulWidget {
  final String url;
  const _FlutterEmbyView({required this.url});

  @override
  State<_FlutterEmbyView> createState() => _FlutterEmbyViewState();
}

class _FlutterEmbyViewState extends State<_FlutterEmbyView> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
    _setup();
  }

  Future<void> _setup() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);

    final delegate = NavigationDelegate(
      onPageStarted: (_) {
        if (mounted) {
          setState(() {
            _loading = true;
            _error = null;
          });
          _startTimeout();
        }
      },
      onPageFinished: (_) {
        _timeoutTimer?.cancel();
        if (mounted) setState(() => _loading = false);
      },
      onWebResourceError: (WebResourceError error) {
        // Only handle main-frame errors to avoid noise from sub-resources
        if (error.isForMainFrame == false) return;
        _timeoutTimer?.cancel();
        if (mounted) {
          setState(() {
            _loading = false;
            _error = _friendlyError(error);
          });
        }
      },
      // Accept SSL errors — Emby servers commonly use self-signed certs,
      // and proxy tunnel failures also surface as SSL errors on WKWebView.
      onSslAuthError: (SslAuthError error) => error.proceed(),
    );

    await _controller.setNavigationDelegate(delegate);
    _startTimeout(); // fallback in case onPageStarted never fires
    await _controller.loadRequest(Uri.parse(widget.url));
  }

  static String _friendlyError(WebResourceError error) {
    switch (error.errorType) {
      case WebResourceErrorType.failedSslHandshake:
        return 'SSL 连接失败，请切换到可用节点后重试';
      case WebResourceErrorType.connect:
      case WebResourceErrorType.proxyAuthentication:
        return '无法连接到服务器，请检查节点是否可用';
      case WebResourceErrorType.hostLookup:
        return 'DNS 解析失败，请检查节点是否可用';
      case WebResourceErrorType.timeout:
        return '连接超时，请切换节点后重试';
      default:
        return '连接失败，请切换节点后重试\n(${error.description})';
    }
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _loading) {
        setState(() {
          _loading = false;
          _error = '连接超时，请检查代理节点是否可用';
        });
      }
    });
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _startTimeout();
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  WebViewController _buildController() {
    if (Platform.isIOS || Platform.isMacOS) {
      final params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
      return WebViewController.fromPlatformCreationParams(params);
    }
    return WebViewController();
  }

  @override
  Widget build(BuildContext context) => _scaffold(
        context,
        child: ColoredBox(
          color: Colors.black,
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            color: Colors.white38, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.white54),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton(
                          onPressed: _retry,
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24)),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(children: [
                  WebViewWidget(controller: _controller),
                  if (_loading)
                    const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                ]),
        ),
      );
}

// ── webview_windows implementation (Windows / WebView2) ──────────────────────

class _WindowsEmbyView extends StatefulWidget {
  final String url;
  const _WindowsEmbyView({required this.url});

  @override
  State<_WindowsEmbyView> createState() => _WindowsEmbyViewState();
}

class _WindowsEmbyViewState extends State<_WindowsEmbyView> {
  final _controller = WebviewController();
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.black);
      await _controller.loadUrl(widget.url);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      // WebView2 Runtime not installed — direct user to download page.
      if (mounted) {
        setState(() => _error =
            'WebView2 Runtime 未安装，请前往 aka.ms/webview2 下载后重试。\n\n$e');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white54)),
      );
    } else if (!_ready) {
      body = const Center(
          child: CircularProgressIndicator(color: Colors.white));
    } else {
      body = Webview(_controller, permissionRequested: _onPermissionRequested);
    }
    return _scaffold(context, child: body);
  }

  Future<WebviewPermissionDecision> _onPermissionRequested(
    String url,
    WebviewPermissionKind kind,
    bool isUserInitiated,
  ) async =>
      WebviewPermissionDecision.allow;
}

// ── Shared scaffold ───────────────────────────────────────────────────────────

Widget _scaffold(BuildContext context, {required Widget child}) {
  final s = S.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Scaffold(
    appBar: AppBar(
      leading: const BackButton(),
      title: Text(s.mineEmby),
      backgroundColor: isDark ? YLColors.zinc900 : Colors.white,
      foregroundColor: isDark ? Colors.white : YLColors.zinc900,
      elevation: 0,
    ),
    backgroundColor: Colors.black,
    body: child,
  );
}
