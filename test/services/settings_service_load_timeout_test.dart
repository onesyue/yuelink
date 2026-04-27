import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/storage/settings_service.dart';

/// Regression coverage for `SettingsService.loadWithTimeout`. The contract
/// the v1.0.22 P0-4a fix relies on:
///   1. Returns within roughly `timeout` even if the underlying file IO
///      would block forever.
///   2. After the call, subsequent `get<T>` reads do not re-block on the
///      same hung future (cache is seeded so they hit memory).
///   3. Never throws — the fallback path on TimeoutException must catch
///      it and return the empty cache.
///
/// These together prove the white-screen scenario (Windows AV scan
/// stalling settings.json access during cold start) cannot prevent
/// `runApp()` from firing.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Completer<String>? hangCompleter;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('yuelink_settings_to_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory' ||
            call.method == 'getApplicationDocumentsDirectory') {
          // If a test wants to simulate a storage hang, await on the
          // current hangCompleter — that future never completes until
          // tearDown, so the underlying load() blocks forever and only
          // the timeout fallback can rescue runApp().
          if (hangCompleter != null) return hangCompleter!.future;
          return tempDir.path;
        }
        return null;
      },
    );
  });

  tearDownAll(() {
    hangCompleter?.complete(tempDir.path);
    tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    SettingsService.invalidateCache();
    hangCompleter = null;
  });

  tearDown(() {
    hangCompleter?.complete(tempDir.path);
    hangCompleter = null;
  });

  test(
    'returns within budget + seeds empty cache when path_provider hangs',
    () async {
      // Simulate the "storage hang doesn't white-screen" scenario: the
      // OS call to resolve the support directory never returns, so
      // `load()` would block forever. `loadWithTimeout` MUST still
      // return inside its budget so `runApp()` can fire.
      hangCompleter = Completer<String>();
      final sw = Stopwatch()..start();

      final result = await SettingsService.loadWithTimeout(
        const Duration(milliseconds: 200),
      );
      sw.stop();

      expect(result, isA<Map<String, dynamic>>());
      expect(result, isEmpty,
          reason: 'storage hang fallback must seed an empty cache');
      expect(
        sw.elapsedMilliseconds,
        lessThan(2000),
        reason:
            'must return within roughly the timeout budget '
            '(measured ${sw.elapsedMilliseconds} ms)',
      );

      // Subsequent get<T> must NOT re-block on the same hung future —
      // the empty cache must be seeded so reads complete in microtasks.
      final read = await SettingsService.get<String>('any_key')
          .timeout(const Duration(milliseconds: 100));
      expect(read, isNull,
          reason: 'cached empty payload returns null for missing keys');
    },
  );

  test('completes normally and returns real cache when storage is healthy',
      () async {
    // Healthy path: no hang, the temp dir resolves immediately, file
    // doesn't exist so cache becomes empty. Must not be slowed down by
    // the timeout wrapper.
    hangCompleter = null;
    final result = await SettingsService.loadWithTimeout(
      const Duration(seconds: 4),
    );

    expect(result, isA<Map<String, dynamic>>());
    expect(result, isEmpty);
  });

  test('honours pre-populated cache without re-reading disk', () async {
    // Once the cache is seeded (either by load() or the timeout
    // fallback), repeated calls return the same instance synchronously.
    // This is the warm-path contract main() relies on for the cascade
    // of getX calls below loadWithTimeout.
    SettingsService.invalidateCache();
    final first = await SettingsService.loadWithTimeout(
      const Duration(milliseconds: 500),
    );
    final second = await SettingsService.loadWithTimeout(
      const Duration(milliseconds: 1),
    );
    expect(identical(first, second), isTrue,
        reason: 'second call must hit the in-memory cache');
  });
}
