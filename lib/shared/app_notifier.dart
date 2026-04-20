import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'haptics.dart';

/// Global [ScaffoldMessengerKey] — set on [MaterialApp.scaffoldMessengerKey].
/// Allows showing styled snackbars from anywhere (services, tray callbacks, etc.)
/// without needing a [BuildContext].
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum _SnackType { success, error, warning, info }

/// Utility for showing styled floating toast notifications.
///
/// Shows an Apple-style top capsule that slides down from under the status
/// bar with blurred background — on all platforms, for cross-platform
/// visual consistency (Telegram-style unified design). Falls back to
/// Material [SnackBar] only when no Overlay is available yet.
///
/// ```dart
/// AppNotifier.success('Upload successful');
/// AppNotifier.error('Connection failed');
/// ```
class AppNotifier {
  AppNotifier._();

  static OverlayEntry? _currentTopEntry;

  static void _show(String message, _SnackType type) {
    _showTopCapsule(message, type);
  }

  static (IconData, Color) _styleFor(_SnackType type) {
    return switch (type) {
      _SnackType.success => (Icons.check_circle_outline_rounded, Colors.green.shade600),
      _SnackType.error   => (Icons.error_outline_rounded, Colors.red.shade600),
      _SnackType.warning => (Icons.warning_amber_rounded, Colors.orange.shade700),
      _SnackType.info    => (Icons.info_outline_rounded, const Color(0xFF3B82F6)),
    };
  }

  static void _showSnackBar(String message, _SnackType type) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    final (icon, color) = _styleFor(type);

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 3),
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }

  static void _showTopCapsule(String message, _SnackType type) {
    final messengerCtx = scaffoldMessengerKey.currentContext;
    final overlay = messengerCtx == null ? null : Overlay.maybeOf(messengerCtx);
    if (overlay == null) {
      // Fallback to SnackBar if overlay isn't available yet.
      _showSnackBar(message, type);
      return;
    }

    // Dismiss any existing toast first.
    _dismissCurrent();

    final (icon, color) = _styleFor(type);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _TopCapsule(
        message: message,
        icon: icon,
        accent: color,
        onDismissed: () {
          if (identical(_currentTopEntry, entry)) {
            _currentTopEntry = null;
          }
          if (entry.mounted) entry.remove();
        },
      ),
    );

    _currentTopEntry = entry;
    overlay.insert(entry);
  }

  static void _dismissCurrent() {
    final entry = _currentTopEntry;
    _currentTopEntry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }

  static void success(String message) {
    Haptics.success();
    _show(message, _SnackType.success);
  }
  static void error(String message) {
    Haptics.error();
    _show(message, _SnackType.error);
  }
  static void warning(String message) {
    Haptics.selection();
    _show(message, _SnackType.warning);
  }
  static void info(String message)    => _show(message, _SnackType.info);
}

class _TopCapsule extends StatefulWidget {
  const _TopCapsule({
    required this.message,
    required this.icon,
    required this.accent,
    required this.onDismissed,
  });

  final String message;
  final IconData icon;
  final Color accent;
  final VoidCallback onDismissed;

  @override
  State<_TopCapsule> createState() => _TopCapsuleState();
}

class _TopCapsuleState extends State<_TopCapsule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    _ctrl.forward();
    _holdTimer = Timer(const Duration(milliseconds: 2500), _dismiss);
  }

  Future<void> _dismiss() async {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!mounted) {
      widget.onDismissed();
      return;
    }
    try {
      await _ctrl.reverse();
    } catch (_) {}
    widget.onDismissed();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topInset = MediaQuery.of(context).padding.top;
    final bg = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.72);
    final borderColor = (isDark ? Colors.white : Colors.black)
        .withValues(alpha: isDark ? 0.08 : 0.06);
    final fg = isDark ? Colors.white : Colors.black87;

    return Positioned(
      top: topInset + 8,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < 0) _dismiss();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: borderColor, width: 0.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                    alpha: isDark ? 0.4 : 0.12),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(widget.icon,
                                  color: widget.accent, size: 18),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  widget.message,
                                  style: TextStyle(
                                    color: fg,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: -0.1,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
