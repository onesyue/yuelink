import 'dart:io';

import 'package:window_manager/window_manager.dart';

import '../../shared/event_log.dart';

/// Local TCP server used as a single-instance mutex on macOS / Windows.
/// Port 47866 is fixed — chosen to avoid common conflicts.
class SingleInstanceGuard {
  SingleInstanceGuard._();

  static ServerSocket? _server;

  static Future<bool> ensure() async {
    const port = 47866;
    try {
      _server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      _server!.listen((socket) {
        socket.listen((data) {
          final msg = String.fromCharCodes(data).trim();
          if (msg == 'show') {
            windowManager.show();
            windowManager.focus();
          }
          socket.close();
        });
      });
      return true;
    } on SocketException {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(seconds: 1),
        );
        socket.write('show\n');
        await socket.flush();
        await socket.close();
      } catch (e) {
        EventLog.writeTagged(
          'App',
          'single_instance_show_failed',
          context: {'error': e},
        );
      }
      return false;
    }
  }

  static void close() {
    _server?.close();
    _server = null;
  }
}
