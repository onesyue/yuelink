import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/logs/log_entry.dart';
export '../../domain/logs/log_entry.dart';

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
    WebSocketChannel? activeChannel;

    Future<void> connect() async {
      var retryDelay = const Duration(seconds: 2);
      const maxDelay = Duration(seconds: 30);

      while (!cancelled) {
        try {
          final sep = path.contains('?') ? '&' : '?';
          final authPath =
              secret != null ? '$path${sep}token=$secret' : path;
          final uri = Uri.parse('$_wsBase$authPath');
          final channel = WebSocketChannel.connect(uri);
          activeChannel = channel;
          var gotFirstMessage = false;

          await for (final event in channel.stream) {
            // Reset backoff only after receiving first message — prevents
            // tight 2s retry loop when server accepts then immediately closes.
            if (!gotFirstMessage) {
              gotFirstMessage = true;
              retryDelay = const Duration(seconds: 2);
            }
            if (cancelled) {
              activeChannel = null;
              return;
            }
            try {
              controller
                  .add(json.decode(event as String) as Map<String, dynamic>);
            } catch (_) {
              // Malformed JSON — skip frame
            }
          }
          activeChannel = null;
          // Stream ended cleanly (server closed); fall through to reconnect
        } catch (_) {
          activeChannel = null;
          // Connection failed or dropped
        }

        if (!cancelled) {
          await Future.delayed(retryDelay);
          // Exponential backoff: 2s → 4s → 8s → 16s → 30s (cap)
          retryDelay = Duration(
            milliseconds: (retryDelay.inMilliseconds * 2)
                .clamp(0, maxDelay.inMilliseconds),
          );
        }
      }
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () => connect(),
      onCancel: () {
        cancelled = true;
        activeChannel?.sink.close();
        activeChannel = null;
        controller.close();
      },
    );

    return controller.stream;
  }
}

/// A single log entry from mihomo.
// LogEntry moved to lib/domain/logs/log_entry.dart
