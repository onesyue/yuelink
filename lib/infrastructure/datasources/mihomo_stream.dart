import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import '../../domain/logs/log_entry.dart';
import '../../shared/event_log.dart';
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
  MihomoStream({this.host = '127.0.0.1', this.port = 9090, this.secret});

  final String host;
  final int port;
  final String? secret;

  String get _wsBase => 'ws://$host:$port';

  // ------------------------------------------------------------------
  // Traffic stream
  // ------------------------------------------------------------------

  /// [idleTimeout] exists mainly so tests can override the 15s production
  /// default for determinism. Production code should call `trafficStream()`
  /// with no args.
  Stream<({int up, int down})> trafficStream({
    Duration idleTimeout = const Duration(seconds: 15),
  }) {
    // mihomo emits /traffic at 1Hz; a 15s gap means the socket is wedged
    // (half-open after suspend/NAT rebind). Idle watchdog force-closes so
    // the retry loop reconnects without user action.
    return _connectWithRetry('/traffic', idleTimeout: idleTimeout).map(
      (data) => (
        up: (data['up'] as num?)?.toInt() ?? 0,
        down: (data['down'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  // ------------------------------------------------------------------
  // Log stream
  // ------------------------------------------------------------------

  Stream<LogEntry> logStream({String level = 'info'}) {
    return _connectWithRetry('/logs?level=$level').map(
      (data) => LogEntry(
        type: data['type'] as String? ?? 'info',
        payload: data['payload'] as String? ?? '',
      ),
    );
  }

  // ------------------------------------------------------------------
  // Memory stream
  // ------------------------------------------------------------------

  Stream<int> memoryStream() {
    // Also 1Hz periodic — apply the same half-open watchdog as /traffic.
    return _connectWithRetry(
      '/memory',
      idleTimeout: const Duration(seconds: 15),
    ).map((data) => (data['inuse'] as num?)?.toInt() ?? 0);
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
  /// [idleTimeout] enables a half-open watchdog: if no frame arrives within
  /// that duration (including the initial connect), the channel is force-
  /// closed so the retry loop reconnects. Intended for endpoints that emit
  /// periodically (`/traffic`, `/memory`). Pass `null` for event-driven
  /// endpoints like `/logs` where a long quiet period is normal.
  ///
  /// The retry loop stops as soon as the consumer cancels its subscription.
  Stream<Map<String, dynamic>> _connectWithRetry(
    String path, {
    Duration? idleTimeout,
  }) {
    late StreamController<Map<String, dynamic>> controller;
    bool cancelled = false;
    IOWebSocketChannel? activeChannel;
    HttpClient? activeClient;
    Timer? idleTimer;

    HttpClient buildLocalClient() {
      final client = HttpClient();
      client.findProxy = (_) => 'DIRECT';
      client.connectionTimeout = const Duration(seconds: 5);
      client.idleTimeout = const Duration(seconds: 15);
      return client;
    }

    void closeActive({bool force = false}) {
      idleTimer?.cancel();
      idleTimer = null;
      activeChannel?.sink.close();
      activeChannel = null;
      activeClient?.close(force: force);
      activeClient = null;
    }

    Future<void> connect() async {
      var retryDelay = const Duration(seconds: 2);
      const maxDelay = Duration(seconds: 30);

      while (!cancelled) {
        try {
          final uri = Uri.parse('$_wsBase$path');
          final client = buildLocalClient();
          activeClient = client;
          // Pass token via HTTP header instead of URL query parameter
          // to prevent it from appearing in proxy/server access logs.
          final channel = IOWebSocketChannel.connect(
            uri,
            headers: secret != null
                ? {'Authorization': 'Bearer $secret'}
                : null,
            pingInterval: const Duration(seconds: 15),
            connectTimeout: const Duration(seconds: 5),
            customClient: client,
          );
          activeChannel = channel;
          var gotFirstMessage = false;

          // Arm the idle watchdog immediately — a wedged TCP handshake
          // would otherwise park us inside `await for` with no error.
          void bumpIdle() {
            if (idleTimeout == null) return;
            idleTimer?.cancel();
            idleTimer = Timer(idleTimeout, () {
              debugPrint(
                '[MihomoStream] idle_timeout path=$path '
                'after=${idleTimeout.inMilliseconds}ms — force-reconnect',
              );
              // Closing the sink makes `channel.stream` terminate, which
              // exits the `await for` and falls into the reconnect branch.
              activeChannel?.sink.close();
            });
          }

          bumpIdle();

          await for (final event in channel.stream) {
            bumpIdle();
            // Reset backoff only after receiving first message — prevents
            // tight 2s retry loop when server accepts then immediately closes.
            if (!gotFirstMessage) {
              gotFirstMessage = true;
              retryDelay = const Duration(seconds: 2);
            }
            if (cancelled) {
              idleTimer?.cancel();
              activeChannel = null;
              return;
            }
            try {
              controller.add(
                json.decode(event as String) as Map<String, dynamic>,
              );
            } catch (e) {
              // Malformed JSON — skip frame
              final msg = e.toString();
              debugPrint(
                '[MihomoStream] decode_fail path=$path '
                'err=${msg.substring(0, msg.length.clamp(0, 200))}',
              );
            }
          }
          closeActive();
          // Stream ended cleanly (server closed); fall through to reconnect
        } catch (e) {
          closeActive(force: true);
          // Connection failed or dropped
          final msg = e.toString();
          final shortMsg = msg.substring(0, msg.length.clamp(0, 200));
          debugPrint(
            '[MihomoStream] ws_fail path=$path type=${e.runtimeType} '
            'retry_in=${retryDelay.inSeconds}s err=$shortMsg',
          );
          EventLog.write(
            '[MihomoStream] ws_fail path=$path type=${e.runtimeType} '
            'retry_in=${retryDelay.inSeconds}s',
          );
        }

        if (!cancelled) {
          await Future.delayed(retryDelay);
          // Exponential backoff: 2s → 4s → 8s → 16s → 30s (cap)
          retryDelay = Duration(
            milliseconds: (retryDelay.inMilliseconds * 2).clamp(
              0,
              maxDelay.inMilliseconds,
            ),
          );
        }
      }
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () => connect(),
      onCancel: () {
        cancelled = true;
        closeActive(force: true);
        controller.close();
      },
    );

    return controller.stream;
  }
}

/// A single log entry from mihomo.
// LogEntry moved to lib/domain/logs/log_entry.dart
