import 'package:flutter/material.dart';

/// Global [ScaffoldMessengerKey] — set on [MaterialApp.scaffoldMessengerKey].
/// Allows showing styled snackbars from anywhere (services, tray callbacks, etc.)
/// without needing a [BuildContext].
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum _SnackType { success, error, warning, info }

/// Utility for showing styled floating snackbars.
///
/// ```dart
/// AppNotifier.success('Upload successful');
/// AppNotifier.error('Connection failed');
/// ```
class AppNotifier {
  AppNotifier._();

  static void _show(String message, _SnackType type) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    final (icon, color) = switch (type) {
      _SnackType.success => (Icons.check_circle_outline_rounded, Colors.green.shade600),
      _SnackType.error   => (Icons.error_outline_rounded, Colors.red.shade600),
      _SnackType.warning => (Icons.warning_amber_rounded, Colors.orange.shade700),
      _SnackType.info    => (Icons.info_outline_rounded, const Color(0xFF3B82F6)),
    };

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

  static void success(String message) => _show(message, _SnackType.success);
  static void error(String message)   => _show(message, _SnackType.error);
  static void warning(String message) => _show(message, _SnackType.warning);
  static void info(String message)    => _show(message, _SnackType.info);
}
