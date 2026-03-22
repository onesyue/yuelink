import 'package:flutter/material.dart';

/// Shows a modal loading overlay with animation.
///
/// Usage:
/// ```dart
/// final result = await LoadingOverlay.show(
///   context,
///   message: '正在下载订阅...',
///   future: ref.read(profileRepositoryProvider).addProfile(name: name, url: url),
/// );
/// ```
class LoadingOverlay {
  LoadingOverlay._();

  /// Show a loading overlay while [future] executes.
  /// Returns the result of [future]. Throws if [future] throws.
  static Future<T> show<T>(
    BuildContext context, {
    required Future<T> future,
    String? message,
  }) async {
    final overlay = OverlayEntry(
      builder: (_) => _LoadingOverlayWidget(message: message),
    );
    Overlay.of(context).insert(overlay);
    try {
      final result = await future;
      return result;
    } finally {
      overlay.remove();
    }
  }

  /// Show overlay, run [action], then dismiss.
  static Future<T> run<T>(
    BuildContext context, {
    required Future<T> Function() action,
    String? message,
  }) async {
    final overlay = OverlayEntry(
      builder: (_) => _LoadingOverlayWidget(message: message),
    );
    Overlay.of(context).insert(overlay);
    try {
      final result = await action();
      return result;
    } finally {
      overlay.remove();
    }
  }
}

class _LoadingOverlayWidget extends StatefulWidget {
  final String? message;
  const _LoadingOverlayWidget({this.message});

  @override
  State<_LoadingOverlayWidget> createState() => _LoadingOverlayWidgetState();
}

class _LoadingOverlayWidgetState extends State<_LoadingOverlayWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FadeTransition(
      opacity: _fadeIn,
      child: Material(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                if (widget.message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    widget.message!,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
