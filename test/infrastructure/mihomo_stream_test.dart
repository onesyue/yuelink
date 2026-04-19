// MihomoStream integration test using a local fake WebSocket server.
//
// Verifies the three hardest-to-reason-about properties of the reconnect
// loop: (1) normal message flow, (2) transparent reconnect after the
// server closes mid-stream, (3) cancellation actually stops the retry
// loop so tearing a provider down leaves no dangling Futures.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/infrastructure/datasources/mihomo_stream.dart';

/// Tiny WebSocket server that accepts connections, pushes a configurable
/// sequence of JSON frames, and optionally drops the connection after the
/// last one — so we can simulate core restart.
class _FakeMihomoServer {
  HttpServer? _server;
  int get port => _server!.port;
  int connectionCount = 0;

  /// Frames delivered per connection. The list is index-per-connection —
  /// first accepted connection gets `frames[0]`, second gets `frames[1]`,
  /// etc. Each inner list is drained then the connection is closed.
  late List<List<Map<String, dynamic>>> frames;

  /// When true, connections whose frame list is exhausted stay OPEN and
  /// silent instead of closing. Simulates a half-open TCP socket where the
  /// kernel keeps the connection but no data flows — the exact scenario the
  /// idle watchdog targets.
  bool holdSilent = false;

  Future<void> start({
    required List<List<Map<String, dynamic>>> frames,
    bool holdSilent = false,
  }) async {
    this.frames = frames;
    this.holdSilent = holdSilent;
    _server = await HttpServer.bind('127.0.0.1', 0);
    _server!.listen((HttpRequest req) async {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        final socket = await WebSocketTransformer.upgrade(req);
        final idx = connectionCount++;
        final payload = idx < this.frames.length
            ? this.frames[idx]
            : <Map<String, dynamic>>[];
        for (final f in payload) {
          socket.add(jsonEncode(f));
          // Small gap so the client actually reads frames in order.
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        if (!this.holdSilent) {
          await socket.close();
        }
        // Otherwise leave the socket open but silent until the client
        // closes it (idle watchdog fire) or tearDown closes the server.
      } else {
        req.response.statusCode = 400;
        await req.response.close();
      }
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}

void main() {
  group('MihomoStream', () {
    late _FakeMihomoServer server;

    setUp(() async {
      server = _FakeMihomoServer();
    });

    tearDown(() async {
      await server.stop();
    });

    test('delivers frames from a single connection', () async {
      await server.start(frames: [
        [
          {'up': 100, 'down': 200},
          {'up': 300, 'down': 400},
        ],
      ]);

      final stream = MihomoStream(host: '127.0.0.1', port: server.port);
      final events = <({int up, int down})>[];
      final sub = stream.trafficStream().listen(events.add);

      // Wait for both frames. Generous margin for slow CI runners.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();

      expect(events, hasLength(greaterThanOrEqualTo(1)));
      expect(events.first.up, 100);
      expect(events.first.down, 200);
    });

    test('transparently reconnects after server-side drop', () async {
      // First connection delivers 1 frame then closes; second connection
      // delivers another frame. Consumer should see both as a continuous
      // stream without needing to resubscribe.
      await server.start(frames: [
        [
          {'up': 10, 'down': 20},
        ],
        [
          {'up': 30, 'down': 40},
        ],
      ]);

      final stream = MihomoStream(host: '127.0.0.1', port: server.port);
      final events = <({int up, int down})>[];
      final sub = stream.trafficStream().listen(events.add);

      // Needs to cover: first frame + server close + 2s retry + reconnect
      // + second frame. Allow 4s for safety.
      await Future<void>.delayed(const Duration(seconds: 4));
      await sub.cancel();

      expect(server.connectionCount, greaterThanOrEqualTo(2),
          reason: 'Client should have reconnected after drop');
      expect(events, hasLength(greaterThanOrEqualTo(2)));
      expect(events.map((e) => e.up), containsAll([10, 30]));
    });

    test('cancellation halts the retry loop', () async {
      await server.start(frames: [
        [],
      ]);

      final stream = MihomoStream(host: '127.0.0.1', port: server.port);
      final sub = stream.trafficStream().listen((_) {});

      // Let one attempt happen then tear down.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      final countAtCancel = server.connectionCount;
      // Wait longer than the retry delay — if cancellation is buggy we'd
      // see additional connection attempts during this window.
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(server.connectionCount, countAtCancel,
          reason: 'No new connections should happen after cancel');
    });

    test('idle watchdog reconnects when server goes silent mid-stream',
        () async {
      // First connection delivers one frame then holds the socket open
      // but silent — simulates a wedged/half-open TCP after OS suspend,
      // NAT rebind, or tethered-hotspot transitions. With the 500ms
      // idleTimeout, the client must force-close and reconnect; the
      // second connection then delivers another frame.
      await server.start(
        frames: [
          [
            {'up': 1, 'down': 2},
          ],
          [
            {'up': 3, 'down': 4},
          ],
        ],
        holdSilent: true,
      );

      final stream = MihomoStream(host: '127.0.0.1', port: server.port);
      final events = <({int up, int down})>[];
      final sub = stream
          .trafficStream(idleTimeout: const Duration(milliseconds: 500))
          .listen(events.add);

      // Wait longer than: first frame + idle timeout (500ms) + 2s retry
      // + second frame. 4s is the safety margin.
      await Future<void>.delayed(const Duration(seconds: 4));
      await sub.cancel();

      expect(server.connectionCount, greaterThanOrEqualTo(2),
          reason: 'Idle watchdog should have forced a reconnect');
      expect(events.map((e) => e.up), containsAll([1, 3]),
          reason: 'Both frames must reach the consumer');
    });

    test('malformed JSON frame is dropped, stream stays alive', () async {
      await server.start(frames: [
        [
          {'up': 1, 'down': 1},
          // Malformed frame injection is awkward because our _FakeServer
          // json-encodes objects, so simulate by sending an object that
          // lacks the 'up'/'down' keys — traffic parser should coerce to 0
          // without crashing the stream.
          {'garbage': 'ignored'},
          {'up': 2, 'down': 2},
        ],
      ]);

      final stream = MihomoStream(host: '127.0.0.1', port: server.port);
      final events = <({int up, int down})>[];
      final sub = stream.trafficStream().listen(events.add);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();

      expect(events.length, greaterThanOrEqualTo(3));
      expect(events.first.up, 1);
      // Middle garbage frame becomes (0, 0) — safe default, stream still
      // delivers the third frame afterward.
      expect(events.last.up, 2);
    });
  });
}
