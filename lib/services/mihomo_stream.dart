import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Real-time WebSocket streaming from mihomo external-controller.
///
/// All streams automatically reconnect with a 2-second delay if the
/// WebSocket connection drops (e.g., network blip, core restart).
///
/// mihomo exposes these WebSocket endpoints:
/// - /traffic — upload/download bytes per second
/// - /logs — log entries with type and payload
/// - /connections — live connection snapshots
/// - /memory — memory usage (inuse bytes)
class MihomoStream {
  MihomoStream({
    this.host = '127.0.0.1',
    this.port = 9090,
    this.secret,
  });

  final String host;
  final int port;
  final String? secret;

  String get _wsBase => 'ws://$host:$port';

  // ------------------------------------------------------------------
  // Traffic stream
  // ------------------------------------------------------------------

  Stream<({int up, int down})> trafficStream() {
    return _connectWithRetry('/traffic').map((data) => (
          up: (data['up'] as num?)?.toInt() ?? 0,
          down: (data['down'] as num?)?.toInt() ?? 0,
        ));
  }

  // ------------------------------------------------------------------
  // Log stream
  // ------------------------------------------------------------------

  Stream<LogEntry> logStream({String level = 'info'}) {
    return _connectWithRetry('/logs?level=$level').map((data) => LogEntry(
          type: data['type'] as String? ?? 'info',
          payload: data['payload'] as String? ?? '',
        ));
  }

  // ------------------------------------------------------------------
  // Memory stream
  // ------------------------------------------------------------------

  Stream<int> memoryStream() {
    return _connectWithRetry('/memory')
        .map((data) => (data['inuse'] as num?)?.toInt() ?? 0);
  }

  // ------------------------------------------------------------------
  // Connections stream
  // ------------------------------------------------------------------

  Stream<Map<String, dynamic>> connectionsStream() {
    return _connectWithRetry('/connections');
  }

  // ------------------------------------------------------------------
  // Internal — reconnecting stream
  // ------------------------------------------------------------------

  /// Creates a WebSocket stream that automatically reconnects on disconnect.
  ///
  /// When the connection drops (network blip, core restart, etc.) the stream
  /// waits [_reconnectDelay] then transparently reconnects. Callers never
  /// see a stream termination — they just keep receiving events.
  ///
  /// The retry loop stops as soon as the consumer cancels its subscription.
  Stream<Map<String, dynamic>> _connectWithRetry(String path) {
    late StreamController<Map<String, dynamic>> controller;
    bool cancelled = false;

    Future<void> connect() async {
      while (!cancelled) {
        try {
          final sep = path.contains('?') ? '&' : '?';
          final authPath =
              secret != null ? '$path${sep}token=$secret' : path;
          final uri = Uri.parse('$_wsBase$authPath');
          final channel = WebSocketChannel.connect(uri);

          await for (final event in channel.stream) {
            if (cancelled) return;
            try {
              controller
                  .add(json.decode(event as String) as Map<String, dynamic>);
            } catch (_) {
              // Malformed JSON — skip frame
            }
          }
          // Stream ended cleanly (server closed); fall through to reconnect
        } catch (_) {
          // Connection failed or dropped
        }

        if (!cancelled) {
          await Future.delayed(_reconnectDelay);
        }
      }
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () => connect(),
      onCancel: () => cancelled = true,
    );

    return controller.stream;
  }

  static const _reconnectDelay = Duration(seconds: 2);
}

/// A single log entry from mihomo.
class LogEntry {
  final String type; // info, warning, error, debug
  final String payload;
  final DateTime timestamp;

  LogEntry({
    required this.type,
    required this.payload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
